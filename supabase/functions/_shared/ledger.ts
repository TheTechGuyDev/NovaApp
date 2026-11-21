import { SupabaseClient } from "jsr:@supabase/supabase-js@2";

export const KYC_DAILY_LIMIT: Record<number, number> = {
  0: 50_000, 1: 200_000, 2: 5_000_000, 3: 50_000_000,
};

export class AppError extends Error {
  constructor(message: string, public status = 400) { super(message); }
}

export async function walletOf(db: SupabaseClient, userId: string, asset: string) {
  const { data, error } = await db.from("wallets")
    .select("id, available, status").eq("user_id", userId).eq("asset_code", asset).single();
  if (error || !data) throw new AppError(`${asset} wallet not found`, 404);
  if (data.status !== "active") throw new AppError("Wallet is not active", 403);
  return { id: data.id as string, available: Number(data.available) };
}

export async function postJournal(
  db: SupabaseClient,
  key: string,
  description: string,
  entries: Array<{ wallet_id?: string; system?: string; asset: string; amount: number }>,
): Promise<string> {
  const { data, error } = await db.rpc("post_journal", {
    _idempotency_key: key,
    _description: description,
    _entries: entries,
  });
  if (error) {
    if (/available_check|violates check constraint/i.test(error.message)) {
      throw new AppError("Insufficient balance");
    }
    throw new AppError(error.message, 500);
  }
  return data as string;
}

// Daily-limit reservations made during the current request (per db client).
const holds = new WeakMap<SupabaseClient, string[]>();

/**
 * Checks account status, KYC, PIN (with lockout) and the daily limit, and
 * reserves the amount in one locked database call, so parallel requests
 * can't slip past the limit. If the request later fails, call
 * releaseHolds(db) to give the allowance back.
 */
export async function guardOutflow(
  db: SupabaseClient,
  userId: string,
  pin: string,
  amountNgn: number,
  kind = "outflow",
) {
  const { data, error } = await db.rpc("outflow_reserve", {
    _user: userId, _pin: String(pin ?? ""), _amount_ngn: Math.round(amountNgn * 100) / 100, _kind: kind,
  });
  if (error) throw new AppError(error.message, 500);
  if (!data?.ok) throw new AppError(data?.error ?? "Not allowed", data?.status ?? 403);
  holds.set(db, [...(holds.get(db) ?? []), data.id as string]);
  return { kyc_level: data.kyc_level as number, status: "active" };
}

/** Gives back reservations from a request that failed before money moved. */
export async function releaseHolds(db: SupabaseClient) {
  for (const id of holds.get(db) ?? []) {
    await db.rpc("outflow_release", { _id: id });
  }
  holds.delete(db);
}

/** Call once money has actually moved, so a later error can't release it. */
export function commitHolds(db: SupabaseClient) {
  holds.delete(db);
}

export function bankTransferFee(amount: number) {
  if (amount <= 5000) return 10;
  if (amount <= 50000) return 25;
  return 50;
}

export async function notify(db: SupabaseClient, userId: string, title: string, body: string, category = "transaction") {
  await db.from("notifications").insert({ user_id: userId, title, body, category });
}
