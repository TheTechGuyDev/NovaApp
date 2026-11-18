# NOVA Finance

**Your Money. Your Crypto. Your World.**

A unified Nigerian banking + crypto super app built with Flutter (Android, iOS, Web) and Supabase.

## Preview
- Web app: https://thetechguydev.github.io/NovaApp/
- Download page (web + APK): https://thetechguydev.github.io/NovaApp/download.html

Every push to `main` rebuilds the web app (GitHub Pages) and the Android APK (the `preview` release).

## Build phases
1. Foundation: theme (dark/light), navigation, CI/CD ✅
2. Database schema & security rules ✅
3. Auth & KYC ✅
4. Naira wallet, transfers, bills ✅
5. Custodial crypto wallets ✅
6. Non-custodial wallets ✅
7. Exchange & crypto/Naira conversion
8. Savings, cards, spending insights ✅
9. Admin dashboard
10. Business, Agent, Developer & AI

> Prototype only: all money movement runs in sandbox/testnet mode.

## Database (Supabase)
Migrations live in `supabase/migrations/`. Key design:
- **Double-entry ledger**: every balance change is a balanced journal posted by `post_journal()` (service role only, idempotent).
- **Wallets** are read-only to users; money only moves through backend functions.
- **Asset + network allowlist** (`assets`, `networks`): e.g. USDT_TRC20 and USDT_ERC20 are separate routes.
- **Non-custodial wallets** store public addresses only; seed phrases never leave the device.
- **RLS** on every table; staff access via `user_roles`.

## Edge Functions
- `kyc-verify`: BVN (Level 1) and NIN (Level 2) checks through Dojah. Secrets live in Supabase, never in the app.

- `banking`: wallet funding (Paystack checkout, sandbox top-up), account numbers, NOVA-to-NOVA and bank transfers (PIN, KYC daily limits, idempotency, auto-reversal), bills.
- `paystack-webhook`: signature-verified Paystack events credit wallets.

- `crypto`: testnet custody via Tatum. Per-user deposit addresses (BTC testnet, ETH Sepolia, BSC testnet, Solana devnet), deposit sync with confirmations, free NOVA-to-NOVA crypto sends, on-chain withdrawals from per-chain hot wallets, sandbox faucet.
  Master seeds are AES-GCM encrypted in the Edge Function before storage (`custody_master`, service role only).

- `wallet-rpc`: JSON-RPC proxy for self-custody wallets (balances + broadcasting already-signed transactions). Keys never leave the device.

## Self-custody (Web3 tab)
- Create (12-word phrase + 3-word verification) or import a BIP39 phrase. MetaMask/Phantom-compatible derivation.
- Phrase stored with `flutter_secure_storage` on the device only; reveal/sign/remove gated by the NOVA PIN (`check_my_pin`, locks after 5 failures).
- Networks: Ethereum Sepolia, BNB Testnet, Solana Devnet (send + receive), Bitcoin Testnet (receive).
- Connect MetaMask / Trust / Phantom etc. through Reown (WalletConnect) as watch-only wallets.

## Savings, cards, insights (Phase 8, Postgres RPCs)
- Savings: flexible (10%), goal (12%, auto-save), fixed 30/90/180/365 days (14 to 20%). Daily-compounded interest, early break forfeits interest. `pg_cron` runs auto-saves and accrual hourly. Plan balances reconcile to the `savings_pool` system account.
- Virtual cards (simulated): NGN Verve (spends from wallet) and USD Visa (prefunded, 1% fee). Freeze, limits, online/international toggles, card PIN, PIN-gated reveal, test purchases, delete with refund. Card number/CVV are not selectable by clients.
- Insights: monthly cash flow, category breakdown, budgets with 80% alerts.

Sandbox test IDs: BVN `22222222222`, NIN `70123456789`.

Paystack test card: `4084 0840 8408 4081`, any future expiry, CVV `408`, PIN `0000`, OTP `123456`.
