// Pre-signup checks (phone already registered?), rate limited per IP so the
// phone list can't be scraped. Called without a user session.
import { adminClient, allow, clientIp, corsHeaders, json, securityEvent, tooMany } from "../_shared/common.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const ip = clientIp(req);
  // Per IP, per /24 network (catches rotating IPs from one provider) and a
  // global ceiling, all per 10 minutes.
  const subnet = ip.includes(".") ? ip.split(".").slice(0, 3).join(".") : ip.split(":").slice(0, 4).join(":");
  const ok = (await allow(`authcheck:${ip}`, 10, 600)) &&
    (await allow(`authcheck-net:${subnet}`, 30, 600)) &&
    (await allow("authcheck-global", 600, 600));
  if (!ok) {
    if (await allow(`authcheck-logged:${ip}`, 1, 600)) {
      await securityEvent("phone_enumeration", "medium", null, ip, {});
    }
    return tooMany("Too many attempts. Please wait a few minutes.");
  }
  const { phone } = await req.json().catch(() => ({}));
  const digits = String(phone ?? "").replace(/\D/g, "");
  if (digits.length < 10 || digits.length > 13) return json({ error: "Enter a valid phone number" }, 400);
  const { data, error } = await adminClient().rpc("phone_available", { _phone: String(phone) });
  if (error) return json({ error: "Could not check phone number" }, 500);
  return json({ available: data === true });
});
