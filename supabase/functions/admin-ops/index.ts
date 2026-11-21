// Admin operations that need server-side network access.
// Staff role is checked on every call. No secret value is ever returned.
import { adminClient, corsHeaders, env, getUser, guardRate, isSandbox, json, loadConfig } from "../_shared/common.ts";
import { tatum } from "../_shared/custody.ts";

const KEYS = [
  "PAYSTACK_SECRET_KEY", "PAYSTACK_PUBLIC_KEY", "DOJAH_APP_ID", "DOJAH_SECRET_KEY", "DOJAH_BASE_URL",
  "TATUM_API_KEY", "COINGECKO_API_KEY", "GEMINI_API_KEY", "RESEND_API_KEY", "REOWN_PROJECT_ID", "CUSTODY_ENCRYPTION_KEY",
];

async function roles(userId: string) {
  const { data } = await adminClient().from("user_roles").select("role").eq("user_id", userId);
  return (data ?? []).map((r) => r.role as string);
}

function allowed(have: string[], need: string[]) {
  return have.includes("super_admin") || need.some((r) => have.includes(r));
}

async function testProvider(provider: string) {
  const t0 = Date.now();
  try {
    switch (provider) {
      case "Paystack": {
        const k = env("PAYSTACK_SECRET_KEY");
        if (!k) return { ok: false, message: "No secret key set" };
        const r = await fetch("https://api.paystack.co/bank?country=nigeria&perPage=1", { headers: { Authorization: `Bearer ${k}` } });
        return { ok: r.ok, message: r.ok ? `Connected (${k.startsWith("sk_live") ? "LIVE" : "TEST"} key)` : `HTTP ${r.status}` };
      }
      case "Dojah": {
        const base = env("DOJAH_BASE_URL") || "https://sandbox.dojah.io";
        const r = await fetch(`${base}/api/v1/general/banks`, {
          headers: { AppId: env("DOJAH_APP_ID"), Authorization: env("DOJAH_SECRET_KEY") },
        });
        return { ok: r.ok, message: r.ok ? `Connected (${base.includes("sandbox") ? "SANDBOX" : "LIVE"})` : `HTTP ${r.status}` };
      }
      case "Tatum": {
        const r = await tatum("/v3/tatum/rate/BTC?basePair=USD");
        return { ok: r.ok, message: r.ok ? "Connected" : `HTTP ${r.status}` };
      }
      case "CoinGecko": {
        const k = env("COINGECKO_API_KEY");
        const r = await fetch("https://api.coingecko.com/api/v3/ping", { headers: k ? { "x-cg-demo-api-key": k } : {} });
        return { ok: r.ok, message: r.ok ? (k ? "Connected with key" : "Connected (free public API)") : `HTTP ${r.status}` };
      }
      case "Google Gemini": {
        const k = env("GEMINI_API_KEY");
        if (!k) return { ok: false, message: "No key set" };
        const r = await fetch(`https://generativelanguage.googleapis.com/v1beta/models?key=${encodeURIComponent(k)}`);
        return { ok: r.ok, message: r.ok ? "Connected" : `HTTP ${r.status}` };
      }
      case "Resend": {
        const k = env("RESEND_API_KEY");
        if (!k) return { ok: false, message: "No key set" };
        const r = await fetch("https://api.resend.com/domains", { headers: { Authorization: `Bearer ${k}` } });
        return { ok: r.ok, message: r.ok ? "Connected" : `HTTP ${r.status}` };
      }
      default:
        return { ok: true, message: "Nothing to test for this provider" };
    }
  } catch (e) {
    return { ok: false, message: (e as Error).message };
  } finally {
    console.log("test", provider, Date.now() - t0, "ms");
  }
}

async function hotWallets() {
  const db = adminClient();
  const { data: masters } = await db.from("custody_master").select("chain, hot_address, next_index");
  const out = [];
  for (const m of masters ?? []) {
    let balance: number | null = null;
    try {
      if (m.chain === "bitcoin") {
        const r = await tatum(`/v3/bitcoin/address/balance/${m.hot_address}`);
        if (r.ok) balance = Number(r.data.incoming) - Number(r.data.outgoing);
      } else if (m.chain === "ethereum" || m.chain === "bsc") {
        const r = await tatum(`/v3/${m.chain}/account/balance/${m.hot_address}`);
        if (r.ok) balance = Number(r.data.balance);
      } else if (m.chain === "solana") {
        const r = await tatum(`/v3/solana/account/balance/${m.hot_address}`);
        if (r.ok) balance = Number(r.data.balance);
      }
    } catch (_) { /* leave null */ }
    out.push({
      chain: m.chain, address: m.hot_address, balance, addresses_issued: m.next_index - 1,
      symbol: { bitcoin: "BTC", ethereum: "ETH", bsc: "BNB", solana: "SOL", tron: "TRX" }[m.chain as string],
    });
  }
  return { wallets: out, testnet: isSandbox() };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  await loadConfig(true);
  const user = await getUser(req);
  if (!user) return json({ error: "Unauthorized" }, 401);
  const limited = await guardRate(req, "admin-ops", user.id, 30);
  if (limited) return limited;
  const have = await roles(user.id);
  const { action, provider } = await req.json().catch(() => ({}));

  switch (action) {
    case "config_status":
      if (!allowed(have, ["tech"])) return json({ error: "Not authorised" }, 403);
      // Only whether a deployment-level fallback exists. Never the value.
      return json({ server_defaults: Object.fromEntries(KEYS.map((k) => [k, !!Deno.env.get(k)])) });
    case "test_integration":
      if (!allowed(have, ["tech"])) return json({ error: "Not authorised" }, 403);
      await adminClient().from("audit_logs").insert({ actor_id: user.id, action: "integration_tested", entity: "integration", entity_id: provider });
      return json(await testProvider(String(provider)));
    case "hot_wallets":
      if (!allowed(have, ["crypto_ops", "treasury", "finance"])) return json({ error: "Not authorised" }, 403);
      return json(await hotWallets());
    default:
      return json({ error: "Unknown action" }, 400);
  }
});
