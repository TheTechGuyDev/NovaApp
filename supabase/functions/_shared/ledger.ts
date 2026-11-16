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

/** Checks PIN, account status and KYC daily limit before any outflow. */
export async function guardOutflow(
  db: SupabaseClient,
  userId: string,
  pin: string,
  amountNgn: number,
) {
  const { data: profile } = await db.from("profiles")
    .select("kyc_level, status").eq("id", userId).single();
  if (!profile) throw new AppError("Profile not found", 404);
  if (profile.status !== "active") throw new AppError("Account is restricted", 403);
  if (profile.kyc_level < 1) throw new AppError("Verify your BVN to send money", 403);

  const { data: pinOk } = await db.rpc("verify_transaction_pin", { _user: userId, _pin: String(pin ?? "") });
  if (pinOk !== true) throw new AppError("Incorrect PIN", 401);

  const { data: spent } = await db.rpc("daily_outflow_ngn", { _user: userId });
  const limit = KYC_DAILY_LIMIT[profile.kyc_level] ?? 0;
  if (Number(spent ?? 0) + amountNgn > limit) {
    throw new AppError(
      `Daily limit of ₦${limit.toLocaleString()} reached for KYC Level ${profile.kyc_level}`, 403,
    );
  }
  return profile;
}

export function bankTransferFee(amount: number) {
  if (amount <= 5000) return 10;
  if (amount <= 50000) return 25;
  return 50;
}

export async function notify(db: SupabaseClient, userId: string, title: string, body: string, category = "transaction") {
  await db.from("notifications").insert({ user_id: userId, title, body, category });
}
