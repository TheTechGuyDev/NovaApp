import { env } from "./common.ts";
const BASE = "https://api.paystack.co";

export async function paystack(path: string, init: { method?: string; body?: unknown } = {}) {
  const res = await fetch(`${BASE}${path}`, {
    method: init.method ?? "GET",
    headers: {
      Authorization: `Bearer ${env("PAYSTACK_SECRET_KEY")}`,
      "Content-Type": "application/json",
    },
    body: init.body ? JSON.stringify(init.body) : undefined,
  });
  const json = await res.json().catch(() => ({}));
  return { ok: res.ok && json?.status !== false, status: res.status, data: json?.data, message: json?.message as string | undefined };
}

export async function verifySignature(raw: string, signature: string | null) {
  if (!signature) return false;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(env("PAYSTACK_SECRET_KEY")),
    { name: "HMAC", hash: "SHA-512" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(raw));
  const hex = Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, "0")).join("");
  return hex === signature;
}
