// Paystack webhook: credits wallets for checkout payments and
// transfers into dedicated virtual accounts. Signature-verified.
import { adminClient, json, loadConfig } from "../_shared/common.ts";
import { notify, postJournal, walletOf } from "../_shared/ledger.ts";
import { verifySignature } from "../_shared/paystack.ts";

Deno.serve(async (req) => {
  await loadConfig();
  const raw = await req.text();
  if (!(await verifySignature(raw, req.headers.get("x-paystack-signature")))) {
    return json({ error: "Invalid signature" }, 401);
  }
  const event = JSON.parse(raw);
  const db = adminClient();

  if (event.event !== "charge.success") return json({ ok: true, ignored: event.event });

  const d = event.data;
  const reference: string = d.reference;
  const amount = Number(d.amount) / 100;

  // Find the user: checkout metadata first, then the virtual-account customer code.
  let userId: string | null = d.metadata?.user_id ?? null;
  if (!userId && d.customer?.customer_code) {
    const { data: va } = await db.from("virtual_accounts").select("user_id")
      .eq("provider_ref", d.customer.customer_code).maybeSingle();
    userId = va?.user_id ?? null;
  }
  if (!userId) return json({ ok: true, unmatched: reference });

  const wallet = await walletOf(db, userId, "NGN");
  const journal = await postJournal(db, `fund:${reference}`, `Paystack ${d.channel} ${reference}`, [
    { wallet_id: wallet.id, asset: "NGN", amount },
    { system: "paystack_settlement", asset: "NGN", amount: -amount },
  ]);

  const { data: existing } = await db.from("transactions").select("id, status")
    .eq("reference", reference).maybeSingle();
  if (existing?.status === "completed") return json({ ok: true, duplicate: true });

  const sender = d.authorization?.sender_name ?? d.authorization?.account_name;
  if (existing) {
    await db.from("transactions").update({ status: "completed", journal_id: journal }).eq("id", existing.id);
  } else {
    await db.from("transactions").insert({
      user_id: userId, journal_id: journal, type: "deposit", status: "completed",
      asset_code: "NGN", amount, reference,
      title: d.channel === "dedicated_nuban" ? `Bank deposit${sender ? " from " + sender : ""}` : "Wallet funding",
      metadata: { channel: d.channel, provider: "paystack" },
    });
  }
  await notify(db, userId, "Money received", `₦${amount.toLocaleString()} was added to your Naira wallet.`);
  return json({ ok: true });
});
