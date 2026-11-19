// KYC verification via Dojah (BVN -> Level 1, NIN -> Level 2).
// POST { "type": "bvn" | "nin", "value": "11 digits" }
import { adminClient, corsHeaders, getUser, isSandbox, json, env, loadConfig } from "../_shared/common.ts";


async function dojah(path: string) {
  const base = env("DOJAH_BASE_URL") || (isSandbox() ? "https://sandbox.dojah.io" : "https://api.dojah.io");
  const res = await fetch(`${base}${path}`, {
    headers: {
      AppId: env("DOJAH_APP_ID"),
      Authorization: env("DOJAH_SECRET_KEY"),
    },
  });
  const body = await res.json().catch(() => ({}));
  return { ok: res.ok, status: res.status, body };
}

const norm = (s?: string) => (s ?? "").toLowerCase().replace(/[^a-z]/g, "");

function namesMatch(profileName: string, first?: string, last?: string) {
  const p = norm(profileName);
  return !!first && !!last && p.includes(norm(first)) && p.includes(norm(last));
}

Deno.serve(async (req) => {
  await loadConfig();
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const user = await getUser(req);
  if (!user) return json({ error: "Unauthorized" }, 401);

  const { type, value } = await req.json().catch(() => ({}));
  if (!["bvn", "nin"].includes(type)) return json({ error: "type must be bvn or nin" }, 400);
  if (!/^\d{11}$/.test(value ?? "")) return json({ error: `${type.toUpperCase()} must be 11 digits` }, 400);

  const db = adminClient();
  const { data: profile } = await db.from("profiles")
    .select("full_name, kyc_level").eq("id", user.id).single();
  if (!profile) return json({ error: "Profile not found" }, 404);

  if (type === "nin" && profile.kyc_level < 1) {
    return json({ error: "Verify your BVN first" }, 400);
  }

  const r = type === "bvn"
    ? await dojah(`/api/v1/kyc/bvn/full?bvn=${value}`)
    : await dojah(`/api/v1/kyc/nin?nin=${value}`);

  const entity = r.body?.entity ?? null;
  const first = entity?.first_name ?? entity?.firstname;
  const last = entity?.last_name ?? entity?.surname;
  const matched = namesMatch(profile.full_name ?? "", first, last);

  // Sandbox returns mock identities, so name mismatch is recorded but not blocking.
  const verified = r.ok && !!entity && (matched || isSandbox());
  const masked = value.slice(0, 3) + "*****" + value.slice(-3);

  await db.from("kyc_verifications").insert({
    user_id: user.id,
    check_type: type,
    provider: "dojah",
    reference: masked,
    status: verified ? "verified" : "rejected",
    result: {
      name_match: matched,
      sandbox: isSandbox(),
      first_name: first ?? null,
      last_name: last ?? null,
      provider_status: r.status,
      error: r.ok ? null : r.body?.error ?? "Verification failed",
    },
  });

  if (!verified) {
    return json({ verified: false, error: r.body?.error ?? "Details did not match our records" }, 422);
  }

  const newLevel = Math.max(profile.kyc_level, type === "bvn" ? 1 : 2);
  await db.from("profiles").update({ kyc_level: newLevel }).eq("id", user.id);
  await db.from("notifications").insert({
    user_id: user.id,
    title: `${type.toUpperCase()} verified`,
    body: `Your account is now on KYC Level ${newLevel}.`,
    category: "kyc",
  });
  await db.from("audit_logs").insert({
    actor_id: user.id, action: `kyc_${type}_verified`, entity: "profile", entity_id: user.id,
    details: { level: newLevel, name_match: matched },
  });

  return json({ verified: true, kyc_level: newLevel, name_match: matched, sandbox: isSandbox() });
});
