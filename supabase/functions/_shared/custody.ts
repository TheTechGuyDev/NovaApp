import { env } from "./common.ts";
// Custody helpers: AES-GCM encryption of seeds and Tatum (testnet) calls.
import { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { AppError } from "./ledger.ts";

const TATUM = "https://api.tatum.io";

export async function tatum(path: string, init: { method?: string; body?: unknown } = {}) {
  const res = await fetch(`${TATUM}${path}`, {
    method: init.method ?? "GET",
    headers: { "x-api-key": env("TATUM_API_KEY"), "Content-Type": "application/json" },
    body: init.body ? JSON.stringify(init.body) : undefined,
  });
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

/** Private key of the chain's hot wallet (index 0). */
export async function hotKey(db: SupabaseClient, chain: string) {
  const master = await masterFor(db, chain);
  const secret = await decrypt(master.encrypted_secret);
  if (!HD_CHAINS.includes(chain)) return { address: master.hot_address as string, key: secret };
  const k = await tatum(`/v3/${V3[chain]}/wallet/priv`, { method: "POST", body: { mnemonic: secret, index: 0 } });
  if (!k.ok) throw new AppError("Could not unlock hot wallet", 502);
  return { address: master.hot_address as string, key: k.data.key as string };
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
