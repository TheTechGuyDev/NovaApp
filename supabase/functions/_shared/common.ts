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
