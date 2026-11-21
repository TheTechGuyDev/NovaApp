import { createClient, SupabaseClient, User } from "jsr:@supabase/supabase-js@2";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

export function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

export function adminClient(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );
}

/** Resolves the signed-in user from the request's JWT, or null. */
export async function getUser(req: Request): Promise<User | null> {
  const auth = req.headers.get("Authorization") ?? "";
  const token = auth.replace(/^Bearer\s+/i, "");
  if (!token) return null;
  const { data, error } = await adminClient().auth.getUser(token);
  if (error) return null;
  return data.user;
}

// ---------------------------------------------------------------------------
// Runtime config: API keys come from Supabase Vault (set on the admin
// Integrations page), falling back to deployment secrets. Cached 30s.
// Keys are only ever held in server memory, never returned to clients.
type RuntimeConfig = {
  secrets: Record<string, string>;
  environment: string;
  withdrawals_paused: boolean;
  trading_paused: boolean;
};
let _cfg: RuntimeConfig | null = null;
let _cfgAt = 0;

export async function loadConfig(force = false): Promise<RuntimeConfig> {
  if (!force && _cfg && Date.now() - _cfgAt < 30_000) return _cfg;
  try {
    const { data, error } = await adminClient().rpc("get_runtime_config");
    if (error) throw error;
    _cfg = {
      secrets: data?.secrets ?? {},
      environment: data?.environment ?? Deno.env.get("NOVA_ENV") ?? "sandbox",
      withdrawals_paused: data?.withdrawals_paused === true,
      trading_paused: data?.trading_paused === true,
    };
    _cfgAt = Date.now();
  } catch (e) {
    console.error("loadConfig", (e as Error).message);
    _cfg ??= { secrets: {}, environment: Deno.env.get("NOVA_ENV") ?? "sandbox", withdrawals_paused: false, trading_paused: false };
  }
  return _cfg;
}

/** Integration key: Vault first, then deployment secret. */
export function env(name: string): string {
  return _cfg?.secrets?.[name] || Deno.env.get(name) || "";
}

export const isSandbox = () => (_cfg?.environment ?? Deno.env.get("NOVA_ENV") ?? "sandbox") === "sandbox";
export const withdrawalsPaused = () => _cfg?.withdrawals_paused === true;

/** Kill switches are read fresh on every money-out request (no cache delay). */
export async function switchOn(key: "withdrawals_paused" | "trading_paused"): Promise<boolean> {
  const { data } = await adminClient().from("app_settings").select("value").eq("key", key).maybeSingle();
  return data?.value === true;
}

// ---------------------------------------------------------------------------
// Abuse protection

/** Caller IP (first hop). */
export function clientIp(req: Request): string {
  return (req.headers.get("x-forwarded-for") ?? req.headers.get("cf-connecting-ip") ?? "")
    .split(",")[0].trim() || "unknown";
}

/** Fixed-window limiter shared across all function instances. True = allowed. */
export async function allow(key: string, max: number, windowSeconds: number): Promise<boolean> {
  const { data, error } = await adminClient().rpc("hit_rate_limit", {
    _key: key, _max: max, _window_seconds: windowSeconds,
  });
  if (error) { console.error("rate limit", error.message); return true; } // fail open, never block on our own error
  return data === true;
}

export function tooMany(message = "Too many requests. Please slow down and try again shortly.") {
  return new Response(JSON.stringify({ error: message }), {
    status: 429,
    headers: { ...corsHeaders, "Content-Type": "application/json", "Retry-After": "30" },
  });
}

export async function securityEvent(
  kind: string, severity: "low" | "medium" | "high" | "critical",
  userId: string | null, ip: string | null, details: Record<string, unknown> = {},
) {
  await adminClient().rpc("log_security_event", {
    _kind: kind, _severity: severity, _user: userId, _ip: ip, _details: details,
  });
}

/** Per-user + per-IP request limit for a function. Returns a 429 response or null. */
export async function guardRate(req: Request, fn: string, userId: string | null, perMinute = 60) {
  const ip = clientIp(req);
  const okIp = await allow(`ip:${fn}:${ip}`, perMinute * 3, 60);
  const okUser = userId ? await allow(`user:${fn}:${userId}`, perMinute, 60) : true;
  if (okIp && okUser) return null;
  // Log once per 5 minutes per caller so the event log isn't flooded.
  if (await allow(`logged:${fn}:${userId ?? ip}`, 1, 300)) {
    await securityEvent("rate_limited", "medium", userId, ip, { fn });
  }
  return tooMany();
}
