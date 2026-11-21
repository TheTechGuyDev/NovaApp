# NOVA Finance: Security and Readiness Report

Date: 21 November 2026. Scope: live backend (Supabase project `iegtcejcgizufqkzgkhe`), Edge Functions, Android/iOS/web app.
Method: 113 automated attacks run against the live system using throwaway `@example.com` accounts only. No real user data was touched.

## 1. Verdict

**Not ready for public launch yet, but the core is solid.** The money engine (double-entry ledger, row-level security, idempotency, balance checks) held up against every direct attack. What stands between this and a real launch is mostly licensing, real providers and paid infrastructure, not code.

| Area | Status |
| --- | --- |
| Data isolation between users | Ready |
| Ledger and balance integrity | Ready |
| Key handling (Vault, masked admin) | Ready |
| Abuse protection (rate limits, lockouts, honeypots) | Ready (after this phase) |
| Login protection | Partly: needs captcha (free Cloudflare Turnstile sign-up) |
| Infrastructure for real traffic | Needs paid plans (see section 3) |
| Regulation and providers | Not started (see section 5) |

## 2. Attack test results

### Fixed in this phase

| # | Severity | Finding | Fix | Re-test |
| --- | --- | --- | --- | --- |
| 1 | High | 20 parallel transfers moved ₦309,950 on a ₦200,000 daily limit | Limit check and reservation in one locked database call (`outflow_reserve`) | 10 parallel ₦25k sends: stopped at ₦184,950 |
| 2 | High | Unlimited PIN guesses on transfers, withdrawals, cards, savings, exchange | One shared lockout: 5 wrong PINs = 15 min lock on every money action. Failures are saved even when the action is refused | Locked after 5 |
| 3 | High | One user could exhaust the shared Tatum allowance (crypto down for everyone) | Per-user limits, global Tatum cap with queue and retry, caching of chain-wide reads | Own 429s, no upstream failures |
| 4 | High | Hot wallet unlock sent the master seed phrase to Tatum | Keys now derived on our server; must match the stored xpub or signing is refused | Verified on BTC, ETH, BSC |
| 5 | Medium | No rate limits on any Edge Function | Per-user and per-IP limits on all functions, 10 payments/minute, KYC 5/hour, test top-ups 5/hour | Pass |
| 6 | Medium | Name could be changed after BVN verification (impersonation in transfers) | Name and date of birth lock after KYC | Pass |
| 7 | Medium | One BVN/NIN could verify many accounts | Keyed hash of each BVN/NIN; reuse blocked in live mode and logged | Logic deployed |
| 8 | Medium | Card purchase simulator worked outside sandbox | Sandbox-only | Pass |
| 9 | Medium | Session stored in plain app storage | Android Keystore / iOS Keychain, migrated silently (no sign-out) | Build |
| 10 | Low | Anyone could check if a phone number or username is registered | Phone check moved to a rate-limited function (per IP, per network, global); RPCs closed | Blocked after ~30 tries |
| 11 | Low | Users could rewrite their own notification text | Only "mark as read" allowed | Pass |
| 12 | Low | Access token valid 1 hour after logout | Lifetime cut to 15 minutes (app refreshes silently, users stay signed in) | Config |
| 13 | Low | Small helper functions callable by anyone | Closed | Pass |

### Added protection

- **Honeypots:** decoy functions (`get_service_role_key`, `debug_exec_sql`, `admin_export_all_users`, `wallet_credit`). Any call is logged as critical and a signed-in caller's account is frozen instantly.
- **Security page** in the admin dashboard: honeypot hits, PIN/login lockouts, rate limiting, BVN reuse, with a Restore button for frozen accounts.
- **Root/jailbreak detection:** blocked in live mode, warning in sandbox.
- **Screenshot and screen-recording block (Android)** in live mode. Off in sandbox so testing screenshots still work.
- Stronger passwords: upper case, lower case and a number.

### Still open (need sign-up or paid plan)

| Finding | Why open | Action |
| --- | --- | --- |
| Password guessing per account | Supabase login lockout hook is a Pro feature; captcha needs a key | Sign up for Cloudflare Turnstile (free). Hook is written and ready for Pro |
| Fake signups (no email confirmation) | Free email sending is limited | Sign up for Resend (free 3,000/month), then turn on email confirmation |
| Withdrawals still send the hot wallet key (not the seed) to Tatum to sign | Needs local transaction signing | Before mainnet: sign locally or use Tatum KMS |
| Self-custody seed on web sits in browser storage | Browser limitation | Show a warning; recommend the mobile app |
| Preview signing key is in the public repo | Needed for preview installs | Before Play Store: new private key in GitHub Secrets (one reinstall) |

### Passed with no changes needed

Privilege escalation to admin, editing balances, fake wallets/transactions/ledger entries, all service-only functions, custody and Vault tables, card PAN/CVV, 18 tables of other users' data, other users' cards/savings/quotes, negative/zero/huge amounts, overdraft, exchange round-trip arbitrage, quote replay, double spending, SQL and filter injection, forged Paystack webhooks, forged cron calls, `alg=none` and tampered JWTs, secret scan of the full git history, wallet proxy method allow-list.

## 3. Will traffic affect it?

Yes, on the current free plans. Approximate safe limits today:

| Component | Free limit | What happens | Fix |
| --- | --- | --- | --- |
| Supabase database | 500 MB, shared small CPU, project pauses after 7 days idle | Slow queries past a few hundred active users; app offline if paused | Supabase Pro ($25/mo), compute add-on as users grow |
| Supabase Auth | 50,000 monthly users | Signups stop | Pro raises to 100,000 |
| Edge Functions | 500,000 calls/month | Functions stop for the month | Pro: 2M included |
| Realtime | 200 concurrent connections | Live balances stop updating for extra users | Pro: 500, then add-on |
| Tatum | 3 requests/sec | Crypto queues (now handled gracefully) | Paid Tatum plan or own nodes |
| CoinGecko public | ~10-30 calls/min | Prices cached, so fine | Paid key only at scale |
| GitHub Pages | Static hosting | Fine for the web app | None |

Already built for scale: prices cached server-side, rates refreshed once a minute for everyone (not per user), idempotent payments, indexed queries, realtime only on the user's own rows.

Recommended before launch: Supabase Pro, daily backups (included in Pro), a load test with 500 simulated users, and uptime alerts.

## 4. Missing features

**Must have for launch**
1. Email confirmation and password-reset emails (Resend).
2. Captcha on signup and login (Turnstile).
3. Real bills provider (VTpass or Flutterwave Bills); bills are simulated today.
4. Real card issuer (e.g. Bridgecard, Sudo Africa); cards are simulated today.
5. Liquidity provider for the exchange and mainnet crypto (today NOVA prices from CoinGecko and acts as the counterparty).
6. Push notifications (Firebase Cloud Messaging is free; only for push).
7. Biometric unlock (fingerprint/Face ID) and auto-lock after inactivity.
8. Transaction receipts (PDF/share) and statements.
9. Dispute and support flow (in-app chat or tickets).
10. Device binding: new-device login needs OTP.
11. Terms, privacy policy, and in-app consent records.

**Nice to have**
- Referral rewards, cashback, QR pay between users, scheduled transfers, multi-currency (USD/GBP) accounts, AI assistant (Phase 10), business and agent accounts (Phase 10).

## 5. Business and regulatory needs (not code)

- CBN licence (or partner bank / licensed PSSP) for wallets and transfers.
- SEC Nigeria VASP registration for crypto.
- NDPC data-protection registration and DPO.
- AML/CFT programme: transaction monitoring, sanctions screening, SAR reporting to NFIU.
- KYC tier rules aligned with CBN (current limits are placeholders).
- Rotate every key shared in chat (Paystack, Dojah, Tatum, Supabase token) before going live.
