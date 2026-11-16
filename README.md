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
3. Auth & KYC
4. Naira wallet, transfers, bills
5. Custodial crypto wallets
6. Non-custodial wallets
7. Exchange & crypto/Naira conversion
8. Savings, cards, spending insights
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
