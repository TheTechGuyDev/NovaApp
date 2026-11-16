-- =====================================================================
-- NOVA FINANCE · Core schema (Phase 2)
-- Fiat + crypto wallets on a double-entry ledger, with RLS.
-- Balances are only ever changed by SECURITY DEFINER functions
-- (called from Edge Functions with the service role), never by clients.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------- Enums ----------
create type public.app_role as enum (
  'user', 'super_admin', 'banking_ops', 'crypto_ops', 'exchange_ops',
  'compliance', 'risk', 'treasury', 'support', 'finance', 'tech'
);
create type public.asset_type as enum ('fiat', 'crypto');
create type public.account_status as enum ('active', 'frozen', 'suspended', 'closed');
create type public.kyc_status as enum ('pending', 'verified', 'rejected');
create type public.txn_type as enum (
  'deposit', 'withdrawal', 'transfer_in', 'transfer_out', 'bill_payment',
  'conversion', 'trade', 'fee', 'reversal', 'adjustment'
);
create type public.txn_status as enum ('pending', 'processing', 'completed', 'failed', 'reversed', 'cancelled');
create type public.order_side as enum ('buy', 'sell');
create type public.order_type as enum ('market', 'limit');
create type public.order_status as enum ('open', 'partially_filled', 'filled', 'cancelled', 'rejected', 'expired');
create type public.quote_status as enum ('open', 'accepted', 'expired', 'cancelled');

-- ---------- Helpers ----------
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

-- ---------- Identity ----------
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  username text unique check (username ~ '^[a-z0-9_]{3,20}$'),
  phone text unique,
  email text,
  avatar_url text,
  date_of_birth date,
  kyc_level smallint not null default 0 check (kyc_level between 0 and 3),
  status public.account_status not null default 'active',
  transaction_pin_hash text,
  referral_code text unique default upper(substr(md5(gen_random_uuid()::text), 1, 8)),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_profiles_updated before update on public.profiles
  for each row execute function public.set_updated_at();

create table public.user_roles (
  user_id uuid references auth.users(id) on delete cascade,
  role public.app_role not null,
  granted_at timestamptz not null default now(),
  primary key (user_id, role)
);

create or replace function public.has_role(_role public.app_role)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.user_roles where user_id = auth.uid() and role = _role)
$$;

create or replace function public.is_staff()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.user_roles where user_id = auth.uid() and role <> 'user')
$$;

create table public.kyc_verifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  check_type text not null,             -- bvn, nin, selfie, address, document
  provider text not null default 'dojah',
  reference text,
  status public.kyc_status not null default 'pending',
  result jsonb,
  created_at timestamptz not null default now()
);
create index on public.kyc_verifications (user_id);

-- ---------- Asset catalogue (allowlist) ----------
create table public.assets (
  code text primary key,                 -- NGN, BTC, ETH, USDT ...
  name text not null,
  type public.asset_type not null,
  decimals smallint not null,
  icon_color text,
  sort_order smallint not null default 100,
  enabled boolean not null default true
);

-- Each asset+network is a separate deposit/withdrawal route.
create table public.networks (
  id text primary key,                   -- e.g. USDT_TRC20
  asset_code text not null references public.assets(code),
  network text not null,                 -- TRC20, ERC20, BEP20, SOL, BTC
  chain text not null,                   -- tron, ethereum, bsc, solana, bitcoin
  is_testnet boolean not null default true,
  contract_address text,
  min_deposit numeric(38,18) not null default 0,
  min_withdrawal numeric(38,18) not null default 0,
  withdrawal_fee numeric(38,18) not null default 0,
  confirmations_required int not null default 1,
  deposits_enabled boolean not null default true,
  withdrawals_enabled boolean not null default true,
  unique (asset_code, network)
);

create table public.trading_pairs (
  symbol text primary key,               -- BTC_NGN
  base_asset text not null references public.assets(code),
  quote_asset text not null references public.assets(code),
  fee_pct numeric(6,4) not null default 0.5,
  min_amount numeric(38,18) not null default 0,
  enabled boolean not null default true
);

create table public.rates (
  asset_code text primary key references public.assets(code),
  usd_price numeric(38,18) not null,
  ngn_price numeric(38,18) not null,
  change_24h numeric(10,4) not null default 0,
  updated_at timestamptz not null default now()
);

-- ---------- Wallets & ledger ----------
create table public.wallets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  asset_code text not null references public.assets(code),
  available numeric(38,18) not null default 0 check (available >= 0),
  locked numeric(38,18) not null default 0 check (locked >= 0),
  status public.account_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, asset_code)
);
create trigger trg_wallets_updated before update on public.wallets
  for each row execute function public.set_updated_at();

-- Platform-owned accounts (fees, treasury, settlement, liquidity).
create table public.system_accounts (
  id text not null,                      -- fees, treasury, settlement, liquidity
  asset_code text not null references public.assets(code),
  balance numeric(38,18) not null default 0,
  primary key (id, asset_code)
);

create table public.journals (
  id uuid primary key default gen_random_uuid(),
  idempotency_key text unique,
  description text,
  created_by uuid,
  created_at timestamptz not null default now()
);

-- Signed amounts: credit > 0, debit < 0. Each journal nets to zero per asset.
create table public.ledger_entries (
  id bigint generated always as identity primary key,
  journal_id uuid not null references public.journals(id),
  wallet_id uuid references public.wallets(id),
  system_account text,
  asset_code text not null references public.assets(code),
  amount numeric(38,18) not null check (amount <> 0),
  balance_after numeric(38,18),
  created_at timestamptz not null default now(),
  check ((wallet_id is not null) <> (system_account is not null))
);
create index on public.ledger_entries (wallet_id);
create index on public.ledger_entries (journal_id);

-- User-facing transaction history.
create table public.transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  journal_id uuid references public.journals(id),
  type public.txn_type not null,
  status public.txn_status not null default 'pending',
  asset_code text not null references public.assets(code),
  amount numeric(38,18) not null,
  fee numeric(38,18) not null default 0,
  reference text unique not null default 'NV' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,14)),
  title text,
  counterparty jsonb,                    -- bank/account/username/address details
  network_id text references public.networks(id),
  tx_hash text,
  confirmations int,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on public.transactions (user_id, created_at desc);
create trigger trg_txn_updated before update on public.transactions
  for each row execute function public.set_updated_at();

-- ---------- Fiat rails ----------
create table public.virtual_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  provider text not null default 'paystack',
  bank_name text not null,
  account_number text not null unique,
  account_name text not null,
  provider_ref text,
  created_at timestamptz not null default now()
);

create table public.beneficiaries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('bank', 'nova_user', 'crypto_address')),
  label text,
  bank_code text,
  bank_name text,
  account_number text,
  account_name text,
  nova_user_id uuid references auth.users(id),
  network_id text references public.networks(id),
  address text,
  is_whitelisted boolean not null default false,
  created_at timestamptz not null default now()
);
create index on public.beneficiaries (user_id);

-- ---------- Crypto ----------
-- Custodial deposit addresses. Private keys never live in this table.
create table public.deposit_addresses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  network_id text not null references public.networks(id),
  address text not null,
  memo text,
  derivation_index int,
  provider_ref text,
  created_at timestamptz not null default now(),
  unique (user_id, network_id),
  unique (network_id, address)
);

-- Non-custodial wallets: PUBLIC addresses only. Seeds stay on the device.
create table public.external_wallets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  label text,
  chain text not null,
  address text not null,
  source text not null default 'created' check (source in ('created', 'imported', 'connected')),
  created_at timestamptz not null default now(),
  unique (user_id, chain, address)
);

-- ---------- Exchange ----------
create table public.quotes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  from_asset text not null references public.assets(code),
  to_asset text not null references public.assets(code),
  amount_in numeric(38,18) not null check (amount_in > 0),
  rate numeric(38,18) not null,
  fee numeric(38,18) not null,
  amount_out numeric(38,18) not null,
  status public.quote_status not null default 'open',
  expires_at timestamptz not null default now() + interval '30 seconds',
  created_at timestamptz not null default now()
);
create index on public.quotes (user_id, created_at desc);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  pair text not null references public.trading_pairs(symbol),
  side public.order_side not null,
  type public.order_type not null,
  price numeric(38,18),
  amount numeric(38,18) not null check (amount > 0),
  filled numeric(38,18) not null default 0,
  avg_price numeric(38,18),
  fee numeric(38,18) not null default 0,
  status public.order_status not null default 'open',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on public.orders (pair, status, side, price);
create index on public.orders (user_id, created_at desc);
create trigger trg_orders_updated before update on public.orders
  for each row execute function public.set_updated_at();

create table public.trades (
  id bigint generated always as identity primary key,
  pair text not null references public.trading_pairs(symbol),
  maker_order_id uuid references public.orders(id),
  taker_order_id uuid references public.orders(id),
  price numeric(38,18) not null,
  amount numeric(38,18) not null,
  taker_side public.order_side not null,
  created_at timestamptz not null default now()
);
create index on public.trades (pair, created_at desc);

create table public.watchlist (
  user_id uuid references auth.users(id) on delete cascade,
  asset_code text references public.assets(code),
  primary key (user_id, asset_code)
);

create table public.price_alerts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  asset_code text not null references public.assets(code),
  direction text not null check (direction in ('above', 'below')),
  target_price numeric(38,18) not null,
  currency text not null default 'USD',
  triggered_at timestamptz,
  created_at timestamptz not null default now()
);

-- ---------- Platform ----------
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  body text,
  category text not null default 'general',
  data jsonb not null default '{}',
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index on public.notifications (user_id, created_at desc);

create table public.audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid,
  action text not null,
  entity text,
  entity_id text,
  details jsonb,
  created_at timestamptz not null default now()
);

create table public.app_settings (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);

-- =====================================================================
-- Core functions
-- =====================================================================

-- New sign-up: profile + one wallet per enabled asset.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, phone, full_name)
  values (new.id, new.email, new.phone, new.raw_user_meta_data->>'full_name');
  insert into public.user_roles (user_id, role) values (new.id, 'user');
  insert into public.wallets (user_id, asset_code)
    select new.id, code from public.assets where enabled;
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Post a balanced journal atomically.
-- entries: [{"wallet_id": "...", "asset": "NGN", "amount": -100}, {"system": "fees", "asset": "NGN", "amount": 100}]
-- Negative amount = debit. Fails if any wallet would go negative or the journal doesn't net to zero.
create or replace function public.post_journal(
  _idempotency_key text,
  _description text,
  _entries jsonb
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  _journal uuid;
  _e jsonb;
  _amt numeric(38,18);
  _bal numeric(38,18);
  _bad int;
begin
  select id into _journal from journals where idempotency_key = _idempotency_key;
  if _journal is not null then return _journal; end if;   -- duplicate request: no double posting

  select count(*) into _bad from (
    select e->>'asset' a, sum((e->>'amount')::numeric) s
    from jsonb_array_elements(_entries) e group by 1
  ) t where s <> 0;
  if _bad > 0 then raise exception 'Journal does not balance'; end if;

  insert into journals (idempotency_key, description, created_by)
  values (_idempotency_key, _description, auth.uid()) returning id into _journal;

  for _e in select * from jsonb_array_elements(_entries) order by (value->>'wallet_id') loop
    _amt := (_e->>'amount')::numeric;
    if _e ? 'wallet_id' then
      update wallets set available = available + _amt
        where id = (_e->>'wallet_id')::uuid and asset_code = _e->>'asset' and status = 'active'
        returning available into _bal;
      if not found then raise exception 'Wallet % unavailable', _e->>'wallet_id'; end if;
      insert into ledger_entries (journal_id, wallet_id, asset_code, amount, balance_after)
      values (_journal, (_e->>'wallet_id')::uuid, _e->>'asset', _amt, _bal);
    else
      insert into system_accounts (id, asset_code, balance) values (_e->>'system', _e->>'asset', _amt)
        on conflict (id, asset_code) do update set balance = system_accounts.balance + _amt
        returning balance into _bal;
      insert into ledger_entries (journal_id, system_account, asset_code, amount, balance_after)
      values (_journal, _e->>'system', _e->>'asset', _amt, _bal);
    end if;
  end loop;
  return _journal;
end $$;

-- Only the backend (service role) may move money.
revoke all on function public.post_journal(text, text, jsonb) from public, anon, authenticated;
grant execute on function public.post_journal(text, text, jsonb) to service_role;

-- Reconciliation view: wallet balance vs sum of ledger entries.
create or replace view public.v_wallet_reconciliation with (security_invoker = true) as
select w.id wallet_id, w.user_id, w.asset_code, w.available,
       coalesce(sum(l.amount), 0) ledger_total,
       w.available - coalesce(sum(l.amount), 0) difference
from public.wallets w left join public.ledger_entries l on l.wallet_id = w.id
group by w.id;

-- =====================================================================
-- Row Level Security
-- =====================================================================
alter table public.profiles enable row level security;
alter table public.user_roles enable row level security;
alter table public.kyc_verifications enable row level security;
alter table public.assets enable row level security;
alter table public.networks enable row level security;
alter table public.trading_pairs enable row level security;
alter table public.rates enable row level security;
alter table public.wallets enable row level security;
alter table public.system_accounts enable row level security;
alter table public.journals enable row level security;
alter table public.ledger_entries enable row level security;
alter table public.transactions enable row level security;
alter table public.virtual_accounts enable row level security;
alter table public.beneficiaries enable row level security;
alter table public.deposit_addresses enable row level security;
alter table public.external_wallets enable row level security;
alter table public.quotes enable row level security;
alter table public.orders enable row level security;
alter table public.trades enable row level security;
alter table public.watchlist enable row level security;
alter table public.price_alerts enable row level security;
alter table public.notifications enable row level security;
alter table public.audit_logs enable row level security;
alter table public.app_settings enable row level security;

-- Public catalogue: anyone signed in can read.
create policy "read assets" on public.assets for select to authenticated using (true);
create policy "read networks" on public.networks for select to authenticated using (true);
create policy "read pairs" on public.trading_pairs for select to authenticated using (true);
create policy "read rates" on public.rates for select to anon, authenticated using (true);
create policy "read trades" on public.trades for select to authenticated using (true);
create policy "read settings" on public.app_settings for select to authenticated using (true);

-- Profiles: own row; limited self-update (no kyc_level/status changes from client).
create policy "own profile" on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_staff());
create policy "update own profile" on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());
revoke update on public.profiles from authenticated;
grant update (full_name, username, avatar_url, date_of_birth) on public.profiles to authenticated;

create policy "own roles" on public.user_roles for select to authenticated
  using (user_id = auth.uid() or public.has_role('super_admin'));

-- Read-only own data (writes go through Edge Functions).
create policy "own kyc" on public.kyc_verifications for select to authenticated
  using (user_id = auth.uid() or public.is_staff());
create policy "own wallets" on public.wallets for select to authenticated
  using (user_id = auth.uid() or public.is_staff());
create policy "own transactions" on public.transactions for select to authenticated
  using (user_id = auth.uid() or public.is_staff());
create policy "own virtual account" on public.virtual_accounts for select to authenticated
  using (user_id = auth.uid() or public.is_staff());
create policy "own deposit addresses" on public.deposit_addresses for select to authenticated
  using (user_id = auth.uid() or public.is_staff());
create policy "own quotes" on public.quotes for select to authenticated
  using (user_id = auth.uid() or public.is_staff());
create policy "own orders" on public.orders for select to authenticated
  using (user_id = auth.uid() or public.is_staff());
create policy "own ledger" on public.ledger_entries for select to authenticated
  using (public.is_staff() or wallet_id in (select id from public.wallets where user_id = auth.uid()));

-- Fully user-managed rows.
create policy "manage beneficiaries" on public.beneficiaries for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "manage external wallets" on public.external_wallets for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "manage watchlist" on public.watchlist for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "manage alerts" on public.price_alerts for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "read notifications" on public.notifications for select to authenticated
  using (user_id = auth.uid());
create policy "mark notifications read" on public.notifications for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Staff-only.
create policy "staff system accounts" on public.system_accounts for select to authenticated
  using (public.has_role('super_admin') or public.has_role('treasury') or public.has_role('finance'));
create policy "staff journals" on public.journals for select to authenticated using (public.is_staff());
create policy "staff audit" on public.audit_logs for select to authenticated
  using (public.has_role('super_admin') or public.has_role('compliance'));

-- Realtime for live balance / history updates in the app.
alter publication supabase_realtime add table public.wallets, public.transactions, public.notifications, public.rates;

-- =====================================================================
-- Seed data (testnet catalogue)
-- =====================================================================
insert into public.assets (code, name, type, decimals, icon_color, sort_order) values
  ('NGN',  'Naira',     'fiat',   2,  '#22C55E', 1),
  ('USDT', 'Tether',    'crypto', 6,  '#26A17B', 2),
  ('BTC',  'Bitcoin',   'crypto', 8,  '#F7931A', 3),
  ('ETH',  'Ethereum',  'crypto', 18, '#8C8CF7', 4),
  ('USDC', 'USD Coin',  'crypto', 6,  '#2775CA', 5),
  ('SOL',  'Solana',    'crypto', 9,  '#14F195', 6),
  ('BNB',  'BNB',       'crypto', 18, '#F3BA2F', 7);

insert into public.networks (id, asset_code, network, chain, min_withdrawal, withdrawal_fee, confirmations_required) values
  ('BTC_BTC',    'BTC',  'Bitcoin',      'bitcoin',  0.0001, 0.00002, 2),
  ('ETH_ERC20',  'ETH',  'ERC20',        'ethereum', 0.001,  0.0005,  12),
  ('USDT_ERC20', 'USDT', 'ERC20',        'ethereum', 10,     3,       12),
  ('USDT_TRC20', 'USDT', 'TRC20',        'tron',     5,      1,       20),
  ('USDT_BEP20', 'USDT', 'BEP20',        'bsc',      5,      0.5,     15),
  ('USDC_ERC20', 'USDC', 'ERC20',        'ethereum', 10,     3,       12),
  ('USDC_SOL',   'USDC', 'Solana (SPL)', 'solana',   5,      0.5,     1),
  ('SOL_SOL',    'SOL',  'Solana',       'solana',   0.05,   0.001,   1),
  ('BNB_BEP20',  'BNB',  'BEP20',        'bsc',      0.01,   0.0005,  15);

insert into public.trading_pairs (symbol, base_asset, quote_asset) values
  ('BTC_NGN','BTC','NGN'), ('ETH_NGN','ETH','NGN'), ('USDT_NGN','USDT','NGN'),
  ('USDC_NGN','USDC','NGN'), ('SOL_NGN','SOL','NGN'), ('BNB_NGN','BNB','NGN'),
  ('BTC_USDT','BTC','USDT'), ('ETH_USDT','ETH','USDT'), ('SOL_USDT','SOL','USDT'),
  ('BNB_USDT','BNB','USDT'), ('USDC_USDT','USDC','USDT'), ('ETH_BTC','ETH','BTC');

-- Starting rates (refreshed from CoinGecko in Phase 7).
insert into public.rates (asset_code, usd_price, ngn_price, change_24h) values
  ('NGN',  1.0/1500, 1,       0),
  ('USDT', 1,        1500,    0.01),
  ('BTC',  96500,    144750000, 3.48),
  ('ETH',  3450,     5175000, 5.67),
  ('USDC', 1,        1500,    0),
  ('SOL',  182,      273000,  -1.92),
  ('BNB',  640,      960000,  0.84);

insert into public.app_settings (key, value) values
  ('environment', '"sandbox"'),
  ('ngn_usd_rate', '1500'),
  ('quote_ttl_seconds', '30'),
  ('daily_limits', '{"kyc0": 50000, "kyc1": 200000, "kyc2": 5000000, "kyc3": 50000000}');
