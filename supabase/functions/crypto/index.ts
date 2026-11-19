// NOVA custodial crypto (testnet): deposit addresses, deposit sync,
// NOVA-to-NOVA crypto transfers and on-chain withdrawals.
import { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { adminClient, corsHeaders, getUser, isSandbox, json, loadConfig, switchOn } from "../_shared/common.ts";
import { AppError, guardOutflow, notify, postJournal, walletOf } from "../_shared/ledger.ts";
import { hotKey, tatum, userAddress, V3, validAddress } from "../_shared/custody.ts";

type Params = Record<string, any>;
const fmt = (n: number) => Number(n.toFixed(8)).toString();

async function ngnRate(db: SupabaseClient, asset: string) {
  const { data } = await db.from("rates").select("ngn_price").eq("asset_code", asset).single();
  return Number(data?.ngn_price ?? 0);
}

// ------------------------------------------------------------- addresses
async function addresses(db: SupabaseClient, userId: string) {
  const { data: profile } = await db.from("profiles").select("kyc_level").eq("id", userId).single();
  if ((profile?.kyc_level ?? 0) < 1) throw new AppError("Verify your BVN to receive crypto", 403);

  const { data: nets } = await db.from("networks").select("*").order("asset_code");
  const out = [];
  const byChain: Record<string, { address: string; index: number | null }> = {};
  for (const n of nets ?? []) {
    if (n.chain === "tron") continue; // TRC20 routes switch on with a testnet USDT contract
    byChain[n.chain] ??= await userAddress(db, userId, n.chain);
    const a = byChain[n.chain];
    await db.from("deposit_addresses").upsert({
      user_id: userId, network_id: n.id, address: a.address, derivation_index: a.index,
    }, { onConflict: "user_id,network_id", ignoreDuplicates: true });
    out.push({
      network_id: n.id, asset: n.asset_code, network: n.network, chain: n.chain,
      address: a.address, deposits_enabled: n.deposits_enabled, withdrawals_enabled: n.withdrawals_enabled,
      min_withdrawal: Number(n.min_withdrawal), withdrawal_fee: Number(n.withdrawal_fee),
      confirmations: n.confirmations_required,
      explorer: n.explorer_address_url?.replace("{address}", a.address) ?? null,
    });
  }
  return { addresses: out, testnet: true };
}

// ------------------------------------------------------------ deposit sync
type Incoming = { hash: string; amount: number; confirmations: number };

async function incomingEvm(chainId: string, address: string, contract: string | null): Promise<Incoming[]> {
  const q = new URLSearchParams({
    chain: chainId, addresses: address, pageSize: "50", transactionDirection: "incoming",
    transactionTypes: contract ? "fungible" : "native",
  });
  if (contract) q.set("tokenAddress", contract);
  const r = await tatum(`/v4/data/transaction/history?${q}`);
  if (!r.ok) return [];
  const blk = await tatum(`/v4/data/blockchains/block/current?chain=${chainId}`);
  const tip = Number(typeof blk.data === "number" ? blk.data : blk.data?.blockNumber ?? 0);
  return (r.data?.result ?? [])
    .filter((t: any) => t.transactionSubtype === "incoming" && Number(t.amount) > 0)
    .map((t: any) => ({
      hash: t.hash, amount: Number(t.amount),
      confirmations: tip && t.blockNumber ? tip - Number(t.blockNumber) + 1 : 99,
    }));
}

async function incomingBtc(address: string): Promise<Incoming[]> {
  const [r, info] = await Promise.all([
    tatum(`/v3/bitcoin/transaction/address/${address}?pageSize=50`),
    tatum(`/v3/bitcoin/info`),
  ]);
  if (!r.ok) return [];
  const tip = Number(info.data?.blocks ?? 0);
  return (r.data as any[]).map((t) => {
    const received = (t.outputs ?? [])
      .filter((o: any) => o.address === address)
      .reduce((s: number, o: any) => s + Number(o.value), 0);
    return {
      hash: t.hash, amount: received / 1e8,
      confirmations: t.blockNumber ? tip - Number(t.blockNumber) + 1 : 0,
    };
  }).filter((t) => t.amount > 0);
}

async function creditDeposit(db: SupabaseClient, userId: string, net: any, address: string, inc: Incoming) {
  const { data: seen } = await db.from("transactions").select("id, status")
    .eq("user_id", userId).eq("network_id", net.id).eq("tx_hash", inc.hash).eq("type", "deposit").maybeSingle();
  const confirmed = inc.confirmations >= net.confirmations_required;
  if (seen?.status === "completed") return false;

  if (!confirmed) {
    if (!seen) {
      await db.from("transactions").insert({
        user_id: userId, type: "deposit", status: "pending", asset_code: net.asset_code, amount: inc.amount,
        title: `${net.asset_code} deposit`, network_id: net.id, tx_hash: inc.hash,
        confirmations: inc.confirmations, counterparty: { kind: "crypto", address },
      });
    } else {
      await db.from("transactions").update({ confirmations: inc.confirmations }).eq("id", seen.id);
    }
    return false;
  }

  const wallet = await walletOf(db, userId, net.asset_code);
  const journal = await postJournal(db, `dep:${net.id}:${inc.hash}:${userId}`, `${net.asset_code} deposit ${inc.hash}`, [
    { wallet_id: wallet.id, asset: net.asset_code, amount: inc.amount },
    { system: `custody_${net.chain}`, asset: net.asset_code, amount: -inc.amount },
  ]);
  if (seen) {
    await db.from("transactions").update({ status: "completed", journal_id: journal, confirmations: inc.confirmations }).eq("id", seen.id);
  } else {
    await db.from("transactions").insert({
      user_id: userId, journal_id: journal, type: "deposit", status: "completed", asset_code: net.asset_code,
      amount: inc.amount, title: `${net.asset_code} deposit`, network_id: net.id, tx_hash: inc.hash,
      confirmations: inc.confirmations, counterparty: { kind: "crypto", address },
    });
  }
  await notify(db, userId, `${net.asset_code} received`, `${fmt(inc.amount)} ${net.asset_code} arrived in your wallet.`);
  return true;
}

async function sync(db: SupabaseClient, userId: string) {
  const { data: rows } = await db.from("deposit_addresses")
    .select("id, address, last_balance, networks!inner(*)").eq("user_id", userId);
  const credited: string[] = [];
  for (const r of rows ?? []) {
    const net = (r as any).networks;
    if (!net.deposits_enabled) continue;
    try {
      let incoming: Incoming[] = [];
      if (net.chain === "bitcoin") incoming = await incomingBtc(r.address);
      else if (net.chain === "ethereum" || net.chain === "bsc") {
        incoming = await incomingEvm(net.tatum_chain, r.address, net.contract_address);
      } else if (net.chain === "solana" && !net.contract_address) {
        // No history API on devnet: credit balance increases (user addresses are never debited).
        const b = await tatum(`/v3/solana/account/balance/${r.address}`);
        const bal = Number(b.data?.balance ?? 0);
        const delta = bal - Number(r.last_balance);
        if (b.ok && delta > 1e-9) {
          incoming = [{ hash: `bal-${Date.now()}`, amount: delta, confirmations: 99 }];
          await db.from("deposit_addresses").update({ last_balance: bal }).eq("id", r.id);
        }
      }
      for (const inc of incoming) {
        if (await creditDeposit(db, userId, net, r.address, inc)) credited.push(`${fmt(inc.amount)} ${net.asset_code}`);
      }
      await db.from("deposit_addresses").update({ last_synced_at: new Date().toISOString() }).eq("id", r.id);
    } catch (e) {
      console.error("sync", net.id, (e as Error).message);
    }
  }
  return { credited };
}

// --------------------------------------------------------- internal send
async function sendInternal(db: SupabaseClient, userId: string, p: Params) {
  const asset = String(p.asset ?? "").toUpperCase();
  const amount = Number(p.amount);
  if (!(amount > 0)) throw new AppError("Enter a valid amount");
  if (asset === "NGN") throw new AppError("Use Naira transfer for NGN");

  const username = String(p.username ?? "").toLowerCase().replace(/^@/, "");
  const { data: rcpt } = await db.from("profiles").select("id, full_name, status").eq("username", username).maybeSingle();
  if (!rcpt || rcpt.status !== "active") throw new AppError("NOVA user not found", 404);
  if (rcpt.id === userId) throw new AppError("You can't send to yourself");

  await guardOutflow(db, userId, p.pin, amount * await ngnRate(db, asset));
  const from = await walletOf(db, userId, asset);
  if (from.available < amount) throw new AppError(`Insufficient ${asset} balance`);
  const to = await walletOf(db, rcpt.id, asset);
  const { data: me } = await db.from("profiles").select("full_name, username").eq("id", userId).single();

  const journal = await postJournal(db, `cint:${userId}:${p.idempotency_key ?? crypto.randomUUID()}`,
    `${asset} to @${username}`, [
      { wallet_id: from.id, asset, amount: -amount },
      { wallet_id: to.id, asset, amount },
    ]);
  const { data: existing } = await db.from("transactions").select("reference").eq("journal_id", journal).limit(1);
  if (existing?.length) return { reference: existing[0].reference, status: "completed" };

  const { data: out } = await db.from("transactions").insert({
    user_id: userId, journal_id: journal, type: "transfer_out", status: "completed", asset_code: asset,
    amount: -amount, title: `${asset} to ${rcpt.full_name ?? "@" + username}`,
    counterparty: { kind: "nova_user", username, name: rcpt.full_name },
  }).select("reference").single();
  await db.from("transactions").insert({
    user_id: rcpt.id, journal_id: journal, type: "transfer_in", status: "completed", asset_code: asset,
    amount, title: `${asset} from ${me?.full_name ?? "@" + me?.username}`,
    counterparty: { kind: "nova_user", username: me?.username, name: me?.full_name },
  });
  await notify(db, rcpt.id, `${asset} received`, `${fmt(amount)} ${asset} from @${me?.username}`);
  return { reference: out?.reference, status: "completed" };
}

// ------------------------------------------------------------- withdraw
async function broadcast(db: SupabaseClient, net: any, to: string, amount: number) {
  const hot = await hotKey(db, net.chain);
  const amt = fmt(amount);
  if (net.contract_address) {
    return await tatum(`/v3/blockchain/token/transaction`, {
      method: "POST",
      body: {
        chain: net.chain === "ethereum" ? "ETH" : "BSC", to, amount: amt,
        contractAddress: net.contract_address, digits: 6, fromPrivateKey: hot.key,
      },
    });
  }
  switch (net.chain) {
    case "bitcoin":
      return await tatum(`/v3/bitcoin/transaction`, {
        method: "POST",
        body: {
          fromAddress: [{ address: hot.address, privateKey: hot.key }],
          to: [{ address: to, value: Number(amt) }], fee: "0.00001", changeAddress: hot.address,
        },
      });
    case "ethereum":
      return await tatum(`/v3/ethereum/transaction`, {
        method: "POST", body: { to, amount: amt, currency: "ETH", fromPrivateKey: hot.key },
      });
    case "bsc":
      return await tatum(`/v3/bsc/transaction`, {
        method: "POST", body: { to, amount: amt, currency: "BSC", fromPrivateKey: hot.key },
      });
    case "solana":
      return await tatum(`/v3/solana/transaction`, {
        method: "POST", body: { from: hot.address, to, amount: amt, fromPrivateKey: hot.key },
      });
  }
  return { ok: false, status: 400, data: { message: "Unsupported network" } };
}

async function withdraw(db: SupabaseClient, userId: string, p: Params) {
  if (await switchOn("withdrawals_paused")) throw new AppError("Crypto withdrawals are temporarily paused", 503);
  const { data: net } = await db.from("networks").select("*").eq("id", p.network_id).single();
  if (!net || !net.withdrawals_enabled) throw new AppError("Withdrawals are paused on this network");
  const to = String(p.address ?? "").trim();
  if (!validAddress(net.chain, to)) throw new AppError(`That is not a valid ${net.network} address`);

  const amount = Number(p.amount);
  const fee = Number(net.withdrawal_fee);
  if (!(amount >= Number(net.min_withdrawal))) throw new AppError(`Minimum withdrawal is ${net.min_withdrawal} ${net.asset_code}`);

  // Sending to another NOVA user's deposit address settles internally, free.
  const { data: internal } = await db.from("deposit_addresses").select("user_id")
    .eq("address", to).eq("network_id", net.id).maybeSingle();
  if (internal?.user_id === userId) throw new AppError("That is your own NOVA address");

  await guardOutflow(db, userId, p.pin, (amount + fee) * await ngnRate(db, net.asset_code));
  const wallet = await walletOf(db, userId, net.asset_code);
  const total = internal ? amount : amount + fee;
  if (wallet.available < total) throw new AppError(`Insufficient ${net.asset_code} balance${internal ? "" : " (including network fee)"}`);

  const key = `wd:${userId}:${p.idempotency_key ?? crypto.randomUUID()}`;

  if (internal) {
    const dest = await walletOf(db, internal.user_id, net.asset_code);
    const journal = await postJournal(db, key, `${net.asset_code} internal to ${to}`, [
      { wallet_id: wallet.id, asset: net.asset_code, amount: -amount },
      { wallet_id: dest.id, asset: net.asset_code, amount },
    ]);
    const { data: existing } = await db.from("transactions").select("reference").eq("journal_id", journal).limit(1);
    if (existing?.length) return { reference: existing[0].reference, status: "completed", internal: true };
    const { data: out } = await db.from("transactions").insert({
      user_id: userId, journal_id: journal, type: "withdrawal", status: "completed", asset_code: net.asset_code,
      amount: -amount, title: `${net.asset_code} sent`, network_id: net.id,
      counterparty: { kind: "crypto", address: to, internal: true },
    }).select("reference").single();
    await db.from("transactions").insert({
      user_id: internal.user_id, journal_id: journal, type: "deposit", status: "completed", asset_code: net.asset_code,
      amount, title: `${net.asset_code} deposit`, network_id: net.id, counterparty: { kind: "crypto", internal: true },
    });
    await notify(db, internal.user_id, `${net.asset_code} received`, `${fmt(amount)} ${net.asset_code} arrived in your wallet.`);
    return { reference: out?.reference, status: "completed", internal: true, fee: 0 };
  }

  const journal = await postJournal(db, key, `${net.asset_code} withdrawal to ${to}`, [
    { wallet_id: wallet.id, asset: net.asset_code, amount: -(amount + fee) },
    { system: `custody_${net.chain}`, asset: net.asset_code, amount },
    { system: "fees", asset: net.asset_code, amount: fee },
  ]);
  const { data: existing } = await db.from("transactions").select("reference, status, tx_hash").eq("journal_id", journal).limit(1);
  if (existing?.length) return existing[0];

  const { data: txn } = await db.from("transactions").insert({
    user_id: userId, journal_id: journal, type: "withdrawal", status: "processing", asset_code: net.asset_code,
    amount: -amount, fee, title: `${net.asset_code} withdrawal`, network_id: net.id,
    counterparty: { kind: "crypto", address: to },
  }).select("id, reference").single();

  const b = await broadcast(db, net, to, amount);
  const hash = b.data?.txId ?? b.data?.txHash ?? null;
  if (b.ok && hash) {
    await db.from("transactions").update({ status: "completed", tx_hash: hash }).eq("id", txn!.id);
    return { reference: txn!.reference, status: "completed", tx_hash: hash, fee,
      explorer: net.explorer_tx_url?.replace("{hash}", hash) };
  }
  const reason = b.data?.message ?? b.data?.cause ?? "Broadcast failed";
  if (isSandbox()) {
    // Hot wallet not funded with testnet coins yet: complete as a simulation.
    await db.from("transactions").update({ status: "completed", metadata: { simulated: true, provider_message: String(reason).slice(0, 200) } }).eq("id", txn!.id);
    return { reference: txn!.reference, status: "completed", simulated: true, fee };
  }
  await postJournal(db, `${key}:reversal`, "Reversal: failed withdrawal", [
    { wallet_id: wallet.id, asset: net.asset_code, amount: amount + fee },
    { system: `custody_${net.chain}`, asset: net.asset_code, amount: -amount },
    { system: "fees", asset: net.asset_code, amount: -fee },
  ]);
  await db.from("transactions").update({ status: "reversed", metadata: { error: String(reason) } }).eq("id", txn!.id);
  throw new AppError("Withdrawal failed and your balance was restored", 502);
}

// ------------------------------------------------------ sandbox faucet
const FAUCET: Record<string, number> = { BTC: 0.005, ETH: 0.1, BNB: 0.5, SOL: 2, USDT: 100, USDC: 100 };

async function testFaucet(db: SupabaseClient, userId: string, p: Params) {
  if (!isSandbox()) throw new AppError("Not available", 403);
  const asset = String(p.asset ?? "").toUpperCase();
  const amount = FAUCET[asset];
  if (!amount) throw new AppError("Unsupported asset");
  const since = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
  const { count } = await db.from("transactions").select("id", { count: "exact", head: true })
    .eq("user_id", userId).eq("asset_code", asset).eq("type", "deposit")
    .contains("metadata", { faucet: true }).gte("created_at", since);
  if ((count ?? 0) >= 3) throw new AppError("Faucet limit reached for today");
  const wallet = await walletOf(db, userId, asset);
  const ref = `FCT${crypto.randomUUID().replace(/-/g, "").slice(0, 14).toUpperCase()}`;
  const journal = await postJournal(db, `faucet:${ref}`, `Test ${asset}`, [
    { wallet_id: wallet.id, asset, amount },
    { system: "test_faucet", asset, amount: -amount },
  ]);
  await db.from("transactions").insert({
    user_id: userId, journal_id: journal, type: "deposit", status: "completed", asset_code: asset,
    amount, reference: ref, title: `Test ${asset} (faucet)`, metadata: { faucet: true, simulated: true },
  });
  return { status: "completed", amount };
}

// ----------------------------------------------------------------- router
Deno.serve(async (req) => {
  await loadConfig();
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  const user = await getUser(req);
  if (!user) return json({ error: "Unauthorized" }, 401);
  const p: Params = await req.json().catch(() => ({}));
  const db = adminClient();
  try {
    switch (p.action) {
      case "addresses": return json(await addresses(db, user.id));
      case "sync": return json(await sync(db, user.id));
      case "send_internal": return json(await sendInternal(db, user.id, p));
      case "withdraw": return json(await withdraw(db, user.id, p));
      case "test_faucet": return json(await testFaucet(db, user.id, p));
      default: return json({ error: "Unknown action" }, 400);
    }
  } catch (e) {
    const err = e instanceof AppError ? e : new AppError(String((e as Error)?.message ?? e), 500);
    console.error(p.action, err.message);
    return json({ error: err.message }, err.status);
  }
});
