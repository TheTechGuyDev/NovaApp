// Price history for charts, cached in Postgres so CoinGecko's free limit is never hit.
import { adminClient, corsHeaders, getUser, json, loadConfig, env } from "../_shared/common.ts";

const IDS: Record<string, string> = {
  BTC: "bitcoin", ETH: "ethereum", USDT: "tether", USDC: "usd-coin", SOL: "solana", BNB: "binancecoin",
};
const TTL: Record<string, number> = { "1": 5, "7": 30, "30": 120, "365": 720 }; // minutes

Deno.serve(async (req) => {
  await loadConfig();
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (!(await getUser(req))) return json({ error: "Unauthorized" }, 401);
  const { asset, days = "7" } = await req.json().catch(() => ({}));
  const id = IDS[asset];
  if (!id || !TTL[String(days)]) return json({ error: "Unsupported" }, 400);

  const db = adminClient();
  const key = `${asset}:${days}`;
  const { data: cached } = await db.from("price_history_cache").select("*").eq("key", key).maybeSingle();
  const fresh = cached && Date.now() - new Date(cached.fetched_at).getTime() < TTL[String(days)] * 60_000;
  if (fresh) return json({ points: cached.points, cached: true });

  const cgKey = env("COINGECKO_API_KEY");
  const r = await fetch(`https://api.coingecko.com/api/v3/coins/${id}/market_chart?vs_currency=ngn&days=${days}`,
    { headers: cgKey ? { "x-cg-demo-api-key": cgKey } : {} });
  if (!r.ok) {
    if (cached) return json({ points: cached.points, cached: true, stale: true });
    return json({ error: "Price history unavailable, try again shortly" }, 502);
  }
  const d = await r.json();
  const raw: [number, number][] = d.prices ?? [];
  const step = Math.max(1, Math.floor(raw.length / 120));
  const points = raw.filter((_, i) => i % step === 0 || i === raw.length - 1);
  await db.from("price_history_cache").upsert({ key, points, fetched_at: new Date().toISOString() });
  return json({ points });
});
