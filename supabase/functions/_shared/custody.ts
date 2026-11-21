import { allow, env } from "./common.ts";
// Custody helpers: AES-GCM encryption of seeds and Tatum (testnet) calls.
import { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { AppError } from "./ledger.ts";
import { HDKey } from "npm:@scure/bip32@1.4.0";
import { mnemonicToSeedSync } from "npm:@scure/bip39@1.3.0";
import { sha256 } from "npm:@noble/hashes@1.4.0/sha256";
import { base58check } from "npm:@scure/base@1.1.7";

const TATUM = "https://api.tatum.io";

/**
 * Tatum call, kept under the plan's requests-per-second limit (shared with
 * wallet-rpc) and retried on 429 so busy moments slow down instead of failing.
 */
export async function tatum(path: string, init: { method?: string; body?: unknown } = {}) {
  const rps = Number(Deno.env.get("TATUM_RPS") ?? "3");
  let res: Response | null = null;
  for (let attempt = 0; attempt < 6; attempt++) {
    if (!(await allow("tatum:global", rps, 1))) {
      await new Promise((r) => setTimeout(r, 300 + attempt * 200));
      continue;
    }
    res = await fetch(`${TATUM}${path}`, {
      method: init.method ?? "GET",
      headers: { "x-api-key": env("TATUM_API_KEY"), "Content-Type": "application/json" },
      body: init.body ? JSON.stringify(init.body) : undefined,
    });
    if (res.status !== 429) break;
    await new Promise((r) => setTimeout(r, 400 + attempt * 300));
  }
  if (!res) return { ok: false, status: 429, data: { message: "Crypto network busy, try again shortly" } };
  const text = await res.text();
  let data: any = null;
  try { data = JSON.parse(text); } catch { data = text; }
  return { ok: res.ok, status: res.status, data };
}

async function aesKey() {
  const raw = Uint8Array.from(atob(Deno.env.get("CUSTODY_ENCRYPTION_KEY")!), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey("raw", raw, "AES-GCM", false, ["encrypt", "decrypt"]);
}

export async function encrypt(plain: string) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv }, await aesKey(), new TextEncoder().encode(plain)));
  const all = new Uint8Array(iv.length + ct.length);
  all.set(iv); all.set(ct, iv.length);
  return btoa(String.fromCharCode(...all));
}

export async function decrypt(b64: string) {
  const all = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
  const pt = await crypto.subtle.decrypt({ name: "AES-GCM", iv: all.slice(0, 12) }, await aesKey(), all.slice(12));
  return new TextDecoder().decode(pt);
}

/** Tatum v3 path segment per custody chain. */
export const V3: Record<string, string> = {
  bitcoin: "bitcoin", ethereum: "ethereum", bsc: "bsc", solana: "solana", tron: "tron",
};
const HD_CHAINS = ["bitcoin", "ethereum", "bsc", "tron"];

/** Creates the chain's master wallet on first use (race-safe via primary key). */
export async function masterFor(db: SupabaseClient, chain: string) {
  const { data: existing } = await db.from("custody_master").select("*").eq("chain", chain).maybeSingle();
  if (existing) return existing;

  const w = await tatum(`/v3/${V3[chain]}/wallet`);
  if (!w.ok) throw new AppError(`Could not create ${chain} wallet`, 502);

  let row: Record<string, unknown>;
  if (HD_CHAINS.includes(chain)) {
    const hot = await tatum(`/v3/${V3[chain]}/address/${w.data.xpub}/0`);
    if (!hot.ok) throw new AppError(`Could not derive ${chain} hot wallet`, 502);
    row = { chain, xpub: w.data.xpub, encrypted_secret: await encrypt(w.data.mnemonic), hot_address: hot.data.address };
  } else {
    row = { chain, xpub: null, encrypted_secret: await encrypt(w.data.privateKey), hot_address: w.data.address };
  }
  const { error } = await db.from("custody_master").insert(row);
  if (error && !/duplicate/i.test(error.message)) throw new AppError(error.message, 500);
  const { data } = await db.from("custody_master").select("*").eq("chain", chain).single();
  return data!;
}

/** Returns (creating if needed) the user's deposit address on a chain. */
export async function userAddress(db: SupabaseClient, userId: string, chain: string) {
  const { data: rows } = await db.from("deposit_addresses")
    .select("address, derivation_index, networks!inner(chain)")
    .eq("user_id", userId).eq("networks.chain", chain).limit(1);
  if (rows?.length) return { address: rows[0].address as string, index: rows[0].derivation_index as number | null };

  const master = await masterFor(db, chain);
  if (HD_CHAINS.includes(chain)) {
    const { data: index } = await db.rpc("next_custody_index", { _chain: chain });
    const a = await tatum(`/v3/${V3[chain]}/address/${master.xpub}/${index}`);
    if (!a.ok) throw new AppError(`Could not derive ${chain} address`, 502);
    return { address: a.data.address as string, index: index as number };
  }
  // Solana: dedicated keypair per user.
  const { data: k } = await db.from("custody_keys").select("address").eq("user_id", userId).eq("chain", chain).maybeSingle();
  if (k) return { address: k.address as string, index: null };
  const w = await tatum(`/v3/${V3[chain]}/wallet`);
  if (!w.ok) throw new AppError(`Could not create ${chain} address`, 502);
  await db.from("custody_keys").insert({
    user_id: userId, chain, address: w.data.address, encrypted_private_key: await encrypt(w.data.privateKey),
  });
  return { address: w.data.address as string, index: null };
}

// BIP44 account paths Tatum uses for its HD wallets. Testnet wallets use
// coin type 1; mainnet uses each chain's own coin type.
const HD_PATHS: Record<string, string[]> = {
  bitcoin: ["m/44'/1'/0'/0", "m/44'/0'/0'/0"],
  ethereum: ["m/44'/1'/0'/0", "m/44'/60'/0'/0"],
  bsc: ["m/44'/1'/0'/0", "m/44'/60'/0'/0"],
  tron: ["m/44'/195'/0'/0", "m/44'/1'/0'/0"],
};
const TPRV = { private: 0x04358394, public: 0x043587cf }; // testnet tprv/tpub

const hex = (b: Uint8Array) => Array.from(b, (x) => x.toString(16).padStart(2, "0")).join("");

/**
 * Private key of the chain's hot wallet (index 0), derived here in server
 * memory. The master mnemonic never leaves our server. The derived account
 * key must match the stored xpub, or we refuse to sign.
 */
export async function hotKey(db: SupabaseClient, chain: string) {
  const master = await masterFor(db, chain);
  const secret = await decrypt(master.encrypted_secret);
  if (!HD_CHAINS.includes(chain)) return { address: master.hot_address as string, key: secret };

  const xpub = master.xpub as string;
  const root = HDKey.fromMasterSeed(mnemonicToSeedSync(secret), xpub.startsWith("tpub") ? TPRV : undefined);
  const account = HD_PATHS[chain].map((path) => root.derive(path)).find((k) => k.publicExtendedKey === xpub);
  if (!account) {
    throw new AppError("Hot wallet key check failed. Withdrawals are paused for safety.", 500);
  }
  const node = account.deriveChild(0);
  const priv = node.privateKey!;
  let key: string;
  if (chain === "bitcoin") {
    key = base58check(sha256).encode(new Uint8Array([0xef, ...priv, 0x01])); // testnet WIF, compressed
  } else if (chain === "tron") {
    key = hex(priv);
  } else {
    key = "0x" + hex(priv);
  }
  return { address: master.hot_address as string, key };
}

export function validAddress(chain: string, a: string) {
  switch (chain) {
    case "bitcoin": return /^(tb1|bcrt1|[mn2])[a-zA-HJ-NP-Z0-9]{25,62}$/.test(a);
    case "ethereum":
    case "bsc": return /^0x[a-fA-F0-9]{40}$/.test(a);
    case "solana": return /^[1-9A-HJ-NP-Za-km-z]{32,44}$/.test(a);
    case "tron": return /^T[1-9A-HJ-NP-Za-km-z]{33}$/.test(a);
    default: return false;
  }
}
