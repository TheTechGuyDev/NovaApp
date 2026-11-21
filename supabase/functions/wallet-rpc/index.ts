// Read-only + broadcast JSON-RPC proxy for NON-custodial wallets.
// Keys never reach the server: the app signs on-device and only sends
// public addresses or already-signed transactions through here.
// Protected by per-user limits, a global cap that keeps us under Tatum's
// plan limit (so one user can't starve everyone), and short caching of
// chain-wide reads.
import { allow, corsHeaders, env, getUser, guardRate, json, loadConfig, tooMany } from "../_shared/common.ts";

const GATEWAYS: Record<string, string> = {
  "ethereum-sepolia": "https://ethereum-sepolia.gateway.tatum.io",
  "bsc-testnet": "https://bsc-testnet.gateway.tatum.io",
  "solana-devnet": "https://api.devnet.solana.com", // public devnet RPC (Tatum gateway is paid for Solana)
};
const TATUM_CHAINS = new Set(["ethereum-sepolia", "bsc-testnet", "bitcoin-testnet"]);
const TATUM_RPS = Number(Deno.env.get("TATUM_RPS") ?? "3"); // raise when the Tatum plan is upgraded

const ALLOWED = new Set([
  // EVM
  "eth_chainId", "eth_getBalance", "eth_getTransactionCount", "eth_gasPrice", "eth_estimateGas",
  "eth_sendRawTransaction", "eth_getTransactionReceipt", "eth_blockNumber", "eth_call",
  "eth_maxPriorityFeePerGas", "eth_feeHistory", "eth_getBlockByNumber", "net_version",
  // Solana
  "getBalance", "getLatestBlockhash", "sendTransaction", "getSignatureStatuses",
  "getFeeForMessage", "getMinimumBalanceForRentExemption", "getAccountInfo", "getTokenAccountsByOwner",
  "getSignaturesForAddress", "getRecentBlockhash",
]);
const BROADCAST = new Set(["eth_sendRawTransaction", "sendTransaction"]);

// Chain-wide answers that are the same for every user (seconds to cache).
const CACHE_TTL: Record<string, number> = {
  eth_chainId: 3600, net_version: 3600, eth_blockNumber: 4, eth_gasPrice: 10,
  eth_maxPriorityFeePerGas: 10, getMinimumBalanceForRentExemption: 600,
};
const cache = new Map<string, { at: number; body: string }>();

async function btc(path: string) {
  const r = await fetch(`https://api.tatum.io${path}`, { headers: { "x-api-key": env("TATUM_API_KEY") } });
  return { status: r.status, body: await r.json().catch(() => ({})) };
}

const busy = () =>
  new Response(JSON.stringify({ jsonrpc: "2.0", id: null, error: { code: -32005, message: "Network busy, retry in a moment" } }), {
    status: 429, headers: { ...corsHeaders, "Content-Type": "application/json", "Retry-After": "1" },
  });

Deno.serve(async (req) => {
  await loadConfig();
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  const user = await getUser(req);
  if (!user) return json({ error: "Unauthorized" }, 401);
  const limited = await guardRate(req, "wallet-rpc", user.id, 60);
  if (limited) return limited;

  const url = new URL(req.url);
  const chain = url.searchParams.get("chain") ?? "";

  // Bitcoin testnet: balance only (REST).
  if (chain === "bitcoin-testnet") {
    const address = url.searchParams.get("address") ?? "";
    if (!/^(tb1|[mn2])[a-zA-HJ-NP-Z0-9]{25,62}$/.test(address)) return json({ error: "Invalid address" }, 400);
    if (!(await allow("tatum:global", TATUM_RPS, 1))) return busy();
    const r = await btc(`/v3/bitcoin/address/balance/${address}`);
    const b = r.body;
    return json({ balance: (Number(b.incoming ?? 0) - Number(b.outgoing ?? 0)) });
  }

  const gw = GATEWAYS[chain];
  if (!gw) return json({ error: "Unsupported chain" }, 400);

  const body = await req.json().catch(() => null);
  const calls = Array.isArray(body) ? body : [body];
  if (!calls.length || calls.length > 10 || calls.some((c) => !c || !ALLOWED.has(c.method))) {
    return json({ jsonrpc: "2.0", id: body?.id ?? null, error: { code: -32601, message: "Method not allowed" } }, 400);
  }
  if (calls.some((c) => BROADCAST.has(c.method)) && !(await allow(`broadcast:${user.id}`, 10, 60))) {
    return tooMany("Too many transactions in a short time. Wait a minute and try again.");
  }

  // Serve single chain-wide reads from cache.
  const single = !Array.isArray(body) && CACHE_TTL[body.method] && !(body.params?.length);
  const cacheKey = single ? `${chain}:${body.method}` : "";
  if (single) {
    const hit = cache.get(cacheKey);
    if (hit && Date.now() - hit.at < CACHE_TTL[body.method] * 1000) {
      const cached = JSON.parse(hit.body);
      cached.id = body.id ?? cached.id;
      return json(cached);
    }
  }

  if (TATUM_CHAINS.has(chain) && !(await allow("tatum:global", TATUM_RPS, 1))) return busy();

  const r = await fetch(gw, {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-api-key": env("TATUM_API_KEY") },
    body: JSON.stringify(body),
  });
  const text = await r.text();
  if (single && r.ok) cache.set(cacheKey, { at: Date.now(), body: text });
  return new Response(text, {
    status: r.status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});
