// Read-only + broadcast JSON-RPC proxy for NON-custodial wallets.
// Keys never reach the server: the app signs on-device and only sends
// public addresses or already-signed transactions through here.
import { corsHeaders, getUser, json, env, loadConfig } from "../_shared/common.ts";

const GATEWAYS: Record<string, string> = {
  "ethereum-sepolia": "https://ethereum-sepolia.gateway.tatum.io",
  "bsc-testnet": "https://bsc-testnet.gateway.tatum.io",
  "solana-devnet": "https://api.devnet.solana.com", // public devnet RPC (Tatum gateway is paid for Solana)
};

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

async function btc(path: string) {
  const r = await fetch(`https://api.tatum.io${path}`, { headers: { "x-api-key": env("TATUM_API_KEY") } });
  return { status: r.status, body: await r.json().catch(() => ({})) };
}

Deno.serve(async (req) => {
  await loadConfig();
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (!(await getUser(req))) return json({ error: "Unauthorized" }, 401);

  const url = new URL(req.url);
  const chain = url.searchParams.get("chain") ?? "";

  // Bitcoin testnet: balance only (REST).
  if (chain === "bitcoin-testnet") {
    const address = url.searchParams.get("address") ?? "";
    if (!/^(tb1|[mn2])[a-zA-HJ-NP-Z0-9]{25,62}$/.test(address)) return json({ error: "Invalid address" }, 400);
    const r = await btc(`/v3/bitcoin/address/balance/${address}`);
    const b = r.body;
    return json({ balance: (Number(b.incoming ?? 0) - Number(b.outgoing ?? 0)) });
  }

  const gw = GATEWAYS[chain];
  if (!gw) return json({ error: "Unsupported chain" }, 400);

  const body = await req.json().catch(() => null);
  const calls = Array.isArray(body) ? body : [body];
  if (!calls.length || calls.some((c) => !c || !ALLOWED.has(c.method))) {
    return json({ jsonrpc: "2.0", id: body?.id ?? null, error: { code: -32601, message: "Method not allowed" } }, 400);
  }
  const r = await fetch(gw, {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-api-key": env("TATUM_API_KEY") },
    body: JSON.stringify(body),
  });
  return new Response(await r.text(), {
    status: r.status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});
