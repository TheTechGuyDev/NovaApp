// NOVA Naira banking: funding, virtual accounts, transfers and bills.
// POST { action: "...", ...params } with the user's JWT.
import { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { adminClient, corsHeaders, getUser, isSandbox, json } from "../_shared/common.ts";
import {
  AppError, bankTransferFee, guardOutflow, notify, postJournal, walletOf,
} from "../_shared/ledger.ts";
import { paystack } from "../_shared/paystack.ts";

type Params = Record<string, any>;

const naira = (n: number) => `₦${n.toLocaleString("en-NG", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

function amountOf(p: Params, min = 1) {
  const a = Math.round(Number(p.amount) * 100) / 100;
  if (!isFinite(a) || a < min) throw new AppError(`Minimum amount is ${naira(min)}`);
  return a;
}

// ---------------------------------------------------------------- funding
async function creditFunding(db: SupabaseClient, userId: string, reference: string, amount: number, channel: string) {
  const wallet = await walletOf(db, userId, "NGN");
  const journal = await postJournal(db, `fund:${reference}`, `Wallet funding ${reference}`, [
    { wallet_id: wallet.id, asset: "NGN", amount },
    { system: "paystack_settlement", asset: "NGN", amount: -amount },
  ]);
  const { data: existing } = await db.from("transactions").select("id, status")
    .eq("reference", reference).maybeSingle();
  if (existing) {
    if (existing.status !== "completed") {
      await db.from("transactions").update({ status: "completed", journal_id: journal }).eq("id", existing.id);
    } else {
      return false; // already credited
    }
  } else {
    await db.from("transactions").insert({
      user_id: userId, journal_id: journal, type: "deposit", status: "completed",
      asset_code: "NGN", amount, reference, title: "Wallet funding",
      metadata: { channel, provider: "paystack" },
    });
  }
  await notify(db, userId, "Wallet funded", `${naira(amount)} was added to your Naira wallet.`);
  return true;
}

async function fundInit(db: SupabaseClient, userId: string, email: string, p: Params) {
  const amount = amountOf(p, 100);
  const reference = `NVF${crypto.randomUUID().replace(/-/g, "").slice(0, 16).toUpperCase()}`;
  const r = await paystack("/transaction/initialize", {
    method: "POST",
    body: {
      email, amount: Math.round(amount * 100), reference, currency: "NGN",
      callback_url: p.callback_url ?? "https://thetechguydev.github.io/NovaApp/",
      metadata: { user_id: userId, purpose: "wallet_funding" },
    },
  });
  if (!r.ok) throw new AppError(r.message ?? "Could not start payment", 502);
  await db.from("transactions").insert({
    user_id: userId, type: "deposit", status: "pending", asset_code: "NGN", amount,
    reference, title: "Wallet funding", metadata: { channel: "checkout", provider: "paystack" },
  });
  return { reference, authorization_url: r.data.authorization_url };
}

async function fundVerify(db: SupabaseClient, userId: string, p: Params) {
  const reference = String(p.reference ?? "");
  const { data: txn } = await db.from("transactions").select("user_id, status")
    .eq("reference", reference).maybeSingle();
  if (!txn || txn.user_id !== userId) throw new AppError("Payment not found", 404);
  if (txn.status === "completed") return { status: "completed" };

  const r = await paystack(`/transaction/verify/${encodeURIComponent(reference)}`);
  if (!r.ok) throw new AppError(r.message ?? "Could not verify payment", 502);
  if (r.data.status !== "success") {
    if (["failed", "abandoned"].includes(r.data.status)) {
      await db.from("transactions").update({ status: "failed" }).eq("reference", reference);
    }
    return { status: r.data.status };
  }
  await creditFunding(db, userId, reference, r.data.amount / 100, r.data.channel);
  return { status: "completed" };
}

// Sandbox shortcut so testers can add money without a card.
async function fundTest(db: SupabaseClient, userId: string, p: Params) {
  if (!isSandbox()) throw new AppError("Not available", 403);
  const amount = amountOf(p, 100);
  if (amount > 1_000_000) throw new AppError("Test top-up limit is ₦1,000,000");
  const reference = `NVT${crypto.randomUUID().replace(/-/g, "").slice(0, 16).toUpperCase()}`;
  await creditFunding(db, userId, reference, amount, "sandbox_test");
  return { status: "completed", reference };
}

// ------------------------------------------------------- virtual account
async function virtualAccount(db: SupabaseClient, userId: string) {
  const { data: va } = await db.from("virtual_accounts").select("*").eq("user_id", userId).maybeSingle();
  if (va) return va;

  const { data: profile } = await db.from("profiles")
    .select("full_name, email, phone, kyc_level").eq("id", userId).single();
  if (!profile) throw new AppError("Profile not found", 404);
  if (profile.kyc_level < 1) throw new AppError("Verify your BVN to get an account number", 403);

  const [first, ...rest] = (profile.full_name ?? "Nova User").trim().split(/\s+/);
  const last = rest.join(" ") || first;
  const phone = (profile.phone ?? "").replace(/^0/, "+234");

  const customer = await paystack("/customer", {
    method: "POST",
    body: { email: profile.email, first_name: first, last_name: last, phone, metadata: { user_id: userId } },
  });
  if (!customer.ok) throw new AppError(customer.message ?? "Could not create customer", 502);

  const dva = await paystack("/dedicated_account", {
    method: "POST",
    body: { customer: customer.data.customer_code, preferred_bank: isSandbox() ? "test-bank" : "wema-bank" },
  });

  let row;
  if (dva.ok) {
    row = {
      user_id: userId, provider: "paystack",
      bank_name: dva.data.bank?.name ?? "Test Bank",
      account_number: dva.data.account_number,
      account_name: dva.data.account_name,
      provider_ref: customer.data.customer_code,
    };
  } else if (isSandbox()) {
    // Paystack only issues dedicated accounts to approved businesses; simulate one for the preview.
    const num = "99" + String(Math.floor(Math.random() * 1e8)).padStart(8, "0");
    row = {
      user_id: userId, provider: "sandbox", bank_name: "NOVA Test Bank",
      account_number: num, account_name: `NOVA/${(profile.full_name ?? "").toUpperCase()}`,
      provider_ref: customer.data.customer_code,
    };
  } else {
    throw new AppError(dva.message ?? "Could not create account number", 502);
  }
  const { data, error } = await db.from("virtual_accounts").insert(row).select().single();
  if (error) throw new AppError(error.message, 500);
  return data;
}

// ------------------------------------------------------------- transfers
async function sendToNova(db: SupabaseClient, userId: string, p: Params) {
  const amount = amountOf(p, 1);
  const username = String(p.username ?? "").toLowerCase().replace(/^@/, "");
  const { data: rcpt } = await db.from("profiles")
    .select("id, full_name, username, status").eq("username", username).maybeSingle();
  if (!rcpt || rcpt.status !== "active") throw new AppError("NOVA user not found", 404);
  if (rcpt.id === userId) throw new AppError("You can't send money to yourself");

  await guardOutflow(db, userId, p.pin, amount);
  const from = await walletOf(db, userId, "NGN");
  if (from.available < amount) throw new AppError("Insufficient balance");
  const to = await walletOf(db, rcpt.id, "NGN");
  const { data: me } = await db.from("profiles").select("full_name, username").eq("id", userId).single();

  const key = `nova:${userId}:${p.idempotency_key ?? crypto.randomUUID()}`;
  const journal = await postJournal(db, key, `NOVA transfer to @${username}`, [
    { wallet_id: from.id, asset: "NGN", amount: -amount },
    { wallet_id: to.id, asset: "NGN", amount },
  ]);
  const { data: existing } = await db.from("transactions").select("reference").eq("journal_id", journal).limit(1);
  if (existing?.length) return { reference: existing[0].reference, status: "completed" };

  const note = (p.note ?? "").toString().slice(0, 80) || null;
  const { data: out } = await db.from("transactions").insert({
    user_id: userId, journal_id: journal, type: "transfer_out", status: "completed",
    asset_code: "NGN", amount: -amount, title: `To ${rcpt.full_name ?? "@" + username}`,
    counterparty: { kind: "nova_user", username, name: rcpt.full_name }, metadata: { note },
  }).select("reference").single();
  await db.from("transactions").insert({
    user_id: rcpt.id, journal_id: journal, type: "transfer_in", status: "completed",
    asset_code: "NGN", amount, title: `From ${me?.full_name ?? "@" + me?.username}`,
    counterparty: { kind: "nova_user", username: me?.username, name: me?.full_name }, metadata: { note },
  });
  await notify(db, rcpt.id, "Money received", `${naira(amount)} from @${me?.username}`);
  return { reference: out?.reference, status: "completed" };
}

async function listBanks() {
  const r = await paystack("/bank?country=nigeria&currency=NGN&perPage=100");
  if (!r.ok) throw new AppError(r.message ?? "Could not load banks", 502);
  return (r.data as any[]).filter((b) => b.active).map((b) => ({ name: b.name, code: b.code }));
}

async function resolveAccount(p: Params) {
  const num = String(p.account_number ?? "");
  if (!/^\d{10}$/.test(num)) throw new AppError("Account number must be 10 digits");
  const r = await paystack(`/bank/resolve?account_number=${num}&bank_code=${encodeURIComponent(p.bank_code)}`);
  if (r.ok) return { account_name: r.data.account_name, simulated: false };
  if (isSandbox()) return { account_name: "TEST ACCOUNT HOLDER", simulated: true };
  throw new AppError(r.message ?? "Could not resolve account", 422);
}

async function sendToBank(db: SupabaseClient, userId: string, p: Params) {
  const amount = amountOf(p, 100);
  const fee = bankTransferFee(amount);
  const { bank_code, bank_name, account_number, account_name } = p;
  if (!bank_code || !/^\d{10}$/.test(String(account_number ?? ""))) throw new AppError("Invalid bank details");

  await guardOutflow(db, userId, p.pin, amount + fee);
  const wallet = await walletOf(db, userId, "NGN");
  if (wallet.available < amount + fee) throw new AppError("Insufficient balance (including fee)");

  const key = `bank:${userId}:${p.idempotency_key ?? crypto.randomUUID()}`;
  const journal = await postJournal(db, key, `Bank transfer to ${account_name}`, [
    { wallet_id: wallet.id, asset: "NGN", amount: -(amount + fee) },
    { system: "bank_payouts", asset: "NGN", amount },
    { system: "fees", asset: "NGN", amount: fee },
  ]);
  const { data: existing } = await db.from("transactions").select("reference, status").eq("journal_id", journal).limit(1);
  if (existing?.length) return existing[0];

  const { data: txn } = await db.from("transactions").insert({
    user_id: userId, journal_id: journal, type: "transfer_out", status: "processing",
    asset_code: "NGN", amount: -amount, fee, title: `To ${account_name}`,
    counterparty: { kind: "bank", bank_code, bank_name, account_number, account_name },
    metadata: { note: (p.note ?? "").toString().slice(0, 80) || null },
  }).select("id, reference").single();

  // Send via Paystack Transfers.
  let simulated = false;
  const recipient = await paystack("/transferrecipient", {
    method: "POST",
    body: { type: "nuban", name: account_name, account_number, bank_code, currency: "NGN" },
  });
  const transfer = recipient.ok
    ? await paystack("/transfer", {
      method: "POST",
      body: {
        source: "balance", amount: Math.round(amount * 100), recipient: recipient.data.recipient_code,
        reference: txn!.reference.toLowerCase(), reason: p.note ?? "NOVA transfer",
      },
    })
    : recipient;

  if (!transfer.ok) {
    if (isSandbox()) {
      simulated = true; // test balance / unapproved transfers: complete as a simulation
    } else {
      // Reverse the debit so the customer is never charged for a failed payout.
      await postJournal(db, `${key}:reversal`, "Reversal: failed bank transfer", [
        { wallet_id: wallet.id, asset: "NGN", amount: amount + fee },
        { system: "bank_payouts", asset: "NGN", amount: -amount },
        { system: "fees", asset: "NGN", amount: -fee },
      ]);
      await db.from("transactions").update({ status: "reversed", metadata: { error: transfer.message } }).eq("id", txn!.id);
      throw new AppError(transfer.message ?? "Transfer failed and was reversed", 502);
    }
  }
  await db.from("transactions").update({
    status: "completed",
    metadata: { simulated, provider: "paystack", provider_message: transfer.message ?? null },
  }).eq("id", txn!.id);
  return { reference: txn!.reference, status: "completed", fee, simulated };
}

// ----------------------------------------------------------------- bills
const BILL_TYPES = ["airtime", "data", "electricity", "cable"];

async function payBill(db: SupabaseClient, userId: string, p: Params) {
  const amount = amountOf(p, 50);
  const { category, biller, customer } = p;
  if (!BILL_TYPES.includes(category)) throw new AppError("Unknown bill category");
  if (!biller || !customer) throw new AppError("Biller and customer number are required");

  await guardOutflow(db, userId, p.pin, amount);
  const wallet = await walletOf(db, userId, "NGN");
  if (wallet.available < amount) throw new AppError("Insufficient balance");

  const key = `bill:${userId}:${p.idempotency_key ?? crypto.randomUUID()}`;
  const journal = await postJournal(db, key, `${category} ${biller} ${customer}`, [
    { wallet_id: wallet.id, asset: "NGN", amount: -amount },
    { system: "bills_settlement", asset: "NGN", amount },
  ]);
  const { data: existing } = await db.from("transactions").select("reference, status").eq("journal_id", journal).limit(1);
  if (existing?.length) return existing[0];

  const token = category === "electricity"
    ? Array.from({ length: 5 }, () => String(Math.floor(1000 + Math.random() * 9000))).join("-")
    : null;
  const titles: Record<string, string> = {
    airtime: `${biller} Airtime`, data: `${biller} Data`, electricity: biller, cable: `${biller} Subscription`,
  };
  const { data: txn } = await db.from("transactions").insert({
    user_id: userId, journal_id: journal, type: "bill_payment", status: "completed",
    asset_code: "NGN", amount: -amount, title: titles[category],
    counterparty: { kind: "biller", category, biller, customer, plan: p.plan ?? null },
    metadata: { simulated: true, token },
  }).select("reference").single();
  return { reference: txn?.reference, status: "completed", token, simulated: true };
}

// ----------------------------------------------------------------- router
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  const user = await getUser(req);
  if (!user) return json({ error: "Unauthorized" }, 401);
  const p: Params = await req.json().catch(() => ({}));
  const db = adminClient();
  try {
    switch (p.action) {
      case "fund_init": return json(await fundInit(db, user.id, user.email!, p));
      case "fund_verify": return json(await fundVerify(db, user.id, p));
      case "fund_test": return json(await fundTest(db, user.id, p));
      case "virtual_account": return json(await virtualAccount(db, user.id));
      case "banks": return json({ banks: await listBanks() });
      case "resolve": return json(await resolveAccount(p));
      case "send_nova": return json(await sendToNova(db, user.id, p));
      case "send_bank": return json(await sendToBank(db, user.id, p));
      case "pay_bill": return json(await payBill(db, user.id, p));
      default: return json({ error: "Unknown action" }, 400);
    }
  } catch (e) {
    const err = e instanceof AppError ? e : new AppError(String((e as Error)?.message ?? e), 500);
    console.error(p.action, err.message);
    return json({ error: err.message }, err.status);
  }
});
