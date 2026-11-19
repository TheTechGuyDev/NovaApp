// Refreshes the `rates` table every minute (called by pg_cron via pg_net).
// Source: CoinGecko public API (no key). Fallback: Tatum rate API.
import { adminClient, json, env, loadConfig } from "../_shared/common.ts";

const IDS: Record<string, string> = {
  BTC: "bitcoin", ETH: "ethereum", USDT: "tether", USDC: "usd-coin", SOL: "solana", BNB: "binancecoin",
};

async function fromCoinGecko() {
  const url = `https://api.coingecko.com/api/v3/simple/price?ids=${Object.values(IDS).join(",")}` +
    `&vs_currencies=usd,ngn&include_24hr_change=true`;
  const key = env("COINGECKO_API_KEY");
  const r = await fetch(url, { headers: { accept: "application/json", ...(key ? { "x-cg-demo-api-key": key } : {}) } });
  if (!r.ok) throw new Error(`coingecko ${r.status}`);
  const d = await r.json();
  return Object.entries(IDS).map(([code, id]) => ({
    asset_code: code,
    usd_price: Number(d[id]?.usd),
    ngn_price: Number(d[id]?.ngn),
    change_24h: Number(d[id]?.ngn_24h_change ?? d[id]?.usd_24h_change ?? 0),
  })).filter((x) => x.usd_price > 0 && x.ngn_price > 0);
}

async function fromTatum() {
  const key = env("TATUM_API_KEY");
  const rows = [];
  for (const code of Object.keys(IDS)) {
    const [u, n] = await Promise.all(["USD", "NGN"].map((b) =>
      fetch(`https://api.tatum.io/v3/tatum/rate/${code}?basePair=${b}`, { headers: { "x-api-key": key } })
        .then((r) => r.json()).then((j) => Number(j.value)).catch(() => 0)
    ));
    if (u > 0 && n > 0) rows.push({ asset_code: code, usd_price: u, ngn_price: n });
  }
  return rows;
}

Deno.serve(async (req) => {
  await loadConfig();
  if (req.headers.get("x-cron-secret") !== Deno.env.get("CRON_SECRET")) return json({ error: "Forbidden" }, 403);
  const db = adminClient();
  let rows: any[] = [];
  let source = "coingecko";
  try {
    rows = await fromCoinGecko();
  } catch (e) {
    console.error((e as Error).message);
  }
  if (rows.length < 4) {
    source = "tatum";
    rows = await fromTatum();
  }
  if (!rows.length) return json({ error: "No price source available" }, 502);

  const now = new Date().toISOString();
  const usdNgn = rows.find((r) => r.asset_code === "USDT")?.ngn_price ?? rows[0].ngn_price / rows[0].usd_price;
  const updates = rows.map((r) => ({ ...r, updated_at: now }));
  updates.push({ asset_code: "NGN", usd_price: 1 / usdNgn, ngn_price: 1, change_24h: 0, updated_at: now });
  const { error } = await db.from("rates").upsert(updates, { onConflict: "asset_code" });
  if (error) return json({ error: error.message }, 500);
  await db.from("app_settings").upsert({ key: "ngn_usd_rate", value: usdNgn, updated_at: now });

  // Fill any limit orders that the new prices reached.
  const { data: filled } = await db.rpc("exchange_match_limits");
  return json({ ok: true, source, updated: updates.length, limit_fills: filled ?? 0 });
});
