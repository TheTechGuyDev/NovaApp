-- =====================================================================
-- Phase 9: Admin dashboard backend + secure integrations
-- Every admin function checks staff roles server-side and writes an
-- audit record. API keys live in Supabase Vault (encrypted at rest) and
-- are WRITE-ONLY from the dashboard: no client role can ever read them.
-- =====================================================================

-- ---------- Role helpers ----------
create or replace function public._require_role(_roles public.app_role[])
returns void language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null or not exists (
    select 1 from user_roles where user_id = auth.uid() and (role = any(_roles) or role = 'super_admin')
  ) then
    raise exception 'Not authorised';
  end if;
end $$;
revoke all on function public._require_role(public.app_role[]) from public, anon, authenticated;

create or replace function public._audit(_action text, _entity text, _entity_id text, _details jsonb default null)
returns void language sql security definer set search_path = public as $$
  insert into audit_logs (actor_id, action, entity, entity_id, details) values (auth.uid(), _action, _entity, _entity_id, _details)
$$;
revoke all on function public._audit(text, text, text, jsonb) from public, anon, authenticated;

create or replace function public.my_roles()
returns text[] language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(role::text), '{}') from user_roles where user_id = auth.uid()
$$;
revoke all on function public.my_roles() from public, anon;
grant execute on function public.my_roles() to authenticated;

-- ---------- Runtime settings ----------
insert into public.app_settings (key, value) values
  ('withdrawals_paused', 'false'),
  ('trading_paused', 'false')
on conflict (key) do nothing;

-- =====================================================================
-- INTEGRATIONS (Vault)
-- =====================================================================
create table if not exists public.integration_catalog (
  name text primary key,                -- secret name read by Edge Functions
  provider text not null,
  label text not null,
  description text,
  is_secret boolean not null default true,
  sort_order int not null default 100,
  editable boolean not null default true
);
alter table public.integration_catalog enable row level security;
create policy "staff read catalog" on public.integration_catalog for select to authenticated using (public.is_staff());

insert into public.integration_catalog (name, provider, label, description, is_secret, sort_order, editable) values
  ('PAYSTACK_SECRET_KEY', 'Paystack', 'Secret key', 'sk_test_... (sandbox) or sk_live_... (live). Used for funding, transfers and account numbers.', true, 10, true),
  ('PAYSTACK_PUBLIC_KEY', 'Paystack', 'Public key', 'pk_test_... or pk_live_...', false, 11, true),
  ('DOJAH_APP_ID', 'Dojah', 'App ID', 'From Dojah dashboard > Developers > Configuration.', false, 20, true),
  ('DOJAH_SECRET_KEY', 'Dojah', 'Secret key', 'test_sk_... (sandbox) or live secret key.', true, 21, true),
  ('DOJAH_BASE_URL', 'Dojah', 'API base URL', 'https://sandbox.dojah.io (sandbox) or https://api.dojah.io (live).', false, 22, true),
  ('TATUM_API_KEY', 'Tatum', 'API key', 'Testnet key for the preview; a mainnet key moves custody to real networks.', true, 30, true),
  ('COINGECKO_API_KEY', 'CoinGecko', 'API key (optional)', 'Leave empty to use the free public API. A Demo/Pro key raises rate limits.', true, 40, true),
  ('GEMINI_API_KEY', 'Google Gemini', 'API key', 'Powers the AI assistant (Phase 10).', true, 50, true),
  ('RESEND_API_KEY', 'Resend', 'API key', 'Transactional email (receipts, alerts).', true, 60, true),
  ('REOWN_PROJECT_ID', 'Reown (WalletConnect)', 'Project ID', 'Public project ID used by the app to connect external wallets.', false, 70, true),
  ('CUSTODY_ENCRYPTION_KEY', 'NOVA Custody', 'Custody encryption key', 'Encrypts custodial wallet seeds. Locked: changing it would make existing wallets unreadable.', true, 90, false)
on conflict (name) do update set provider = excluded.provider, label = excluded.label,
  description = excluded.description, is_secret = excluded.is_secret, sort_order = excluded.sort_order,
  editable = excluded.editable;

-- Status only. Values are never returned, only a short mask.
create or replace function public.admin_integrations()
returns table (name text, provider text, label text, description text, is_secret boolean, editable boolean,
               in_vault boolean, masked text, updated_at timestamptz)
language plpgsql stable security definer set search_path = public, vault as $$
begin
  perform _require_role(array['tech']::app_role[]);
  return query
  select c.name, c.provider, c.label, c.description, c.is_secret, c.editable,
         s.id is not null,
         case when s.id is null then null
              when length(d.decrypted_secret) <= 8 then repeat('•', length(d.decrypted_secret))
              when c.is_secret then left(d.decrypted_secret, 4) || '••••••••' || right(d.decrypted_secret, 4)
              else d.decrypted_secret end,
         s.updated_at
  from integration_catalog c
  left join vault.secrets s on s.name = 'nova:' || c.name
  left join vault.decrypted_secrets d on d.id = s.id
  order by c.sort_order;
end $$;
revoke all on function public.admin_integrations() from public, anon;
grant execute on function public.admin_integrations() to authenticated;

create or replace function public.admin_set_secret(_name text, _value text)
returns void language plpgsql security definer set search_path = public, vault as $$
declare _id uuid; c record;
begin
  perform _require_role(array['super_admin']::app_role[]);
  select * into c from integration_catalog where name = _name;
  if c is null then raise exception 'Unknown integration key'; end if;
  if not c.editable then raise exception '% is locked', c.label; end if;
  if coalesce(trim(_value), '') = '' then raise exception 'Value cannot be empty'; end if;
  if length(_value) > 4096 then raise exception 'Value too long'; end if;
  select id into _id from vault.secrets where name = 'nova:' || _name;
  if _id is null then
    perform vault.create_secret(trim(_value), 'nova:' || _name, c.provider || ' ' || c.label);
  else
    perform vault.update_secret(_id, trim(_value));
  end if;
  perform _audit('integration_updated', 'integration', _name, jsonb_build_object('provider', c.provider));
end $$;
revoke all on function public.admin_set_secret(text, text) from public, anon;
grant execute on function public.admin_set_secret(text, text) to authenticated;

create or replace function public.admin_clear_secret(_name text)
returns void language plpgsql security definer set search_path = public, vault as $$
begin
  perform _require_role(array['super_admin']::app_role[]);
  if not exists (select 1 from integration_catalog where name = _name and editable) then
    raise exception 'Cannot clear this key'; end if;
  delete from vault.secrets where name = 'nova:' || _name;
  perform _audit('integration_cleared', 'integration', _name);
end $$;
revoke all on function public.admin_clear_secret(text) from public, anon;
grant execute on function public.admin_clear_secret(text) to authenticated;

-- Edge Functions only (service role): decrypted keys + runtime switches.
create or replace function public.get_runtime_config()
returns jsonb language sql stable security definer set search_path = public, vault as $$
  select jsonb_build_object(
    'secrets', coalesce((select jsonb_object_agg(substr(d.name, 6), d.decrypted_secret)
                         from vault.decrypted_secrets d where d.name like 'nova:%'), '{}'),
    'environment', (select value #>> '{}' from app_settings where key = 'environment'),
    'withdrawals_paused', (select value from app_settings where key = 'withdrawals_paused'),
    'trading_paused', (select value from app_settings where key = 'trading_paused'))
$$;
revoke all on function public.get_runtime_config() from public, anon, authenticated;
grant execute on function public.get_runtime_config() to service_role;

-- Public, non-secret config the app may read (e.g. WalletConnect project id).
create or replace function public.public_config()
returns jsonb language sql stable security definer set search_path = public, vault as $$
  select jsonb_build_object(
    'environment', (select value #>> '{}' from app_settings where key = 'environment'),
    'reown_project_id', (select decrypted_secret from vault.decrypted_secrets where name = 'nova:REOWN_PROJECT_ID'),
    'withdrawals_paused', (select value from app_settings where key = 'withdrawals_paused'),
    'trading_paused', (select value from app_settings where key = 'trading_paused'))
$$;
revoke all on function public.public_config() from public;
grant execute on function public.public_config() to anon, authenticated;

create or replace function public.admin_set_environment(_env text, _confirm text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform _require_role(array['super_admin']::app_role[]);
  if _env not in ('sandbox', 'live') then raise exception 'Invalid environment'; end if;
  if _env = 'live' and _confirm <> 'GO LIVE' then raise exception 'Type GO LIVE to confirm'; end if;
  update app_settings set value = to_jsonb(_env), updated_at = now() where key = 'environment';
  perform _audit('environment_changed', 'settings', 'environment', jsonb_build_object('environment', _env));
end $$;
revoke all on function public.admin_set_environment(text, text) from public, anon;
grant execute on function public.admin_set_environment(text, text) to authenticated;

-- Kill switches respected by the backend.
create or replace function public.admin_set_switch(_key text, _on boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform _require_role(array['crypto_ops', 'risk', 'exchange_ops']::app_role[]);
  if _key not in ('withdrawals_paused', 'trading_paused') then raise exception 'Unknown switch'; end if;
  update app_settings set value = to_jsonb(_on), updated_at = now() where key = _key;
  perform _audit(_key || case when _on then '_on' else '_off' end, 'settings', _key);
end $$;
revoke all on function public.admin_set_switch(text, boolean) from public, anon;
grant execute on function public.admin_set_switch(text, boolean) to authenticated;

-- Trading kill switch inside the exchange itself.
create or replace function public._trading_open()
returns void language plpgsql stable security definer set search_path = public as $$
begin
  if coalesce((select value from app_settings where key = 'trading_paused')::text, 'false') = 'true' then
    raise exception 'Trading is temporarily paused';
  end if;
end $$;

-- =====================================================================
-- DASHBOARD DATA
-- =====================================================================
create or replace function public.admin_overview()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  perform _require_role(array['banking_ops','crypto_ops','exchange_ops','compliance','risk','treasury','support','finance','tech']::app_role[]);
  select jsonb_build_object(
    'users', (select count(*) from profiles),
    'users_today', (select count(*) from profiles where created_at >= date_trunc('day', now())),
    'kyc', (select jsonb_object_agg(kyc_level, n) from (select kyc_level, count(*) n from profiles group by 1) k),
    'frozen', (select count(*) from profiles where status <> 'active'),
    'ngn_balances', (select coalesce(sum(available + locked), 0) from wallets where asset_code = 'NGN'),
    'crypto_aum_ngn', (select coalesce(sum((w.available + w.locked) * r.ngn_price), 0)
                         from wallets w join rates r on r.asset_code = w.asset_code where w.asset_code <> 'NGN'),
    'savings', (select coalesce(sum(balance), 0) from savings_plans where status = 'active'),
    'txns_today', (select count(*) from transactions where created_at >= date_trunc('day', now())),
    'volume_today_ngn', (select coalesce(sum(abs(t.amount) * coalesce(r.ngn_price, 1)), 0)
                           from transactions t left join rates r on r.asset_code = t.asset_code
                          where t.created_at >= date_trunc('day', now()) and t.amount < 0),
    'fees', (select coalesce(jsonb_object_agg(asset_code, balance), '{}') from system_accounts where id = 'fees'),
    'pending', (select count(*) from transactions where status in ('pending', 'processing')),
    'recon_issues', (select count(*) from v_wallet_reconciliation where difference <> 0),
    'ledger_total', (select coalesce(sum(amount), 0) from ledger_entries),
    'open_orders', (select count(*) from orders where status = 'open'),
    'active_cards', (select count(*) from cards where status = 'active'),
    'environment', (select value #>> '{}' from app_settings where key = 'environment'),
    'withdrawals_paused', (select value from app_settings where key = 'withdrawals_paused'),
    'trading_paused', (select value from app_settings where key = 'trading_paused'),
    'daily', (select jsonb_agg(d order by d->>'day') from (
        select jsonb_build_object('day', to_char(g, 'YYYY-MM-DD'),
          'txns', (select count(*) from transactions where created_at >= g and created_at < g + interval '1 day'),
          'signups', (select count(*) from profiles where created_at >= g and created_at < g + interval '1 day')) d
        from generate_series(date_trunc('day', now()) - interval '13 days', date_trunc('day', now()), interval '1 day') g) x)
  ) into r;
  return r;
end $$;
revoke all on function public.admin_overview() from public, anon;
grant execute on function public.admin_overview() to authenticated;

create or replace function public.admin_users(_search text default null, _limit int default 50, _offset int default 0)
returns table (id uuid, full_name text, username text, email text, phone text, kyc_level smallint,
               status public.account_status, created_at timestamptz, ngn_balance numeric, roles text[])
language plpgsql stable security definer set search_path = public as $$
begin
  perform _require_role(array['support','compliance','banking_ops','risk','tech','finance']::app_role[]);
  return query
  select p.id, p.full_name, p.username, p.email, p.phone, p.kyc_level, p.status, p.created_at,
         (select w.available from wallets w where w.user_id = p.id and w.asset_code = 'NGN'),
         (select array_agg(r.role::text) from user_roles r where r.user_id = p.id and r.role <> 'user')
  from profiles p
  where _search is null or _search = '' or
        p.full_name ilike '%' || _search || '%' or p.username ilike '%' || _search || '%' or
        p.email ilike '%' || _search || '%' or p.phone ilike '%' || _search || '%'
  order by p.created_at desc limit least(_limit, 200) offset _offset;
end $$;
revoke all on function public.admin_users(text, int, int) from public, anon;
grant execute on function public.admin_users(text, int, int) to authenticated;

create or replace function public.admin_user_detail(_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform _require_role(array['support','compliance','banking_ops','risk','tech','finance']::app_role[]);
  return jsonb_build_object(
    'profile', (select to_jsonb(p) - 'transaction_pin_hash' from profiles p where p.id = _id),
    'roles', (select coalesce(jsonb_agg(role), '[]') from user_roles where user_id = _id),
    'wallets', (select coalesce(jsonb_agg(jsonb_build_object('asset', w.asset_code, 'available', w.available,
                 'locked', w.locked, 'status', w.status) order by a.sort_order), '[]')
                from wallets w join assets a on a.code = w.asset_code where w.user_id = _id),
    'kyc', (select coalesce(jsonb_agg(to_jsonb(k) order by k.created_at desc), '[]') from kyc_verifications k where k.user_id = _id),
    'transactions', (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at desc), '[]')
                     from (select * from transactions where user_id = _id order by created_at desc limit 50) t),
    'virtual_account', (select to_jsonb(v) from virtual_accounts v where v.user_id = _id),
    'savings', (select coalesce(sum(balance), 0) from savings_plans where user_id = _id and status = 'active'),
    'cards', (select count(*) from cards where user_id = _id and status <> 'terminated'),
    'deposit_addresses', (select coalesce(jsonb_agg(jsonb_build_object('network', network_id, 'address', address)), '[]')
                          from deposit_addresses where user_id = _id));
end $$;
revoke all on function public.admin_user_detail(uuid) from public, anon;
grant execute on function public.admin_user_detail(uuid) to authenticated;

create or replace function public.admin_set_user_status(_id uuid, _status public.account_status, _reason text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform _require_role(array['compliance','risk']::app_role[]);
  if coalesce(trim(_reason), '') = '' then raise exception 'A reason is required'; end if;
  if _id = auth.uid() then raise exception 'You cannot change your own status'; end if;
  update profiles set status = _status where id = _id;
  insert into notifications (user_id, title, body, category)
  values (_id, case when _status = 'active' then 'Account restored' else 'Account restricted' end,
          case when _status = 'active' then 'Your NOVA account is active again.'
               else 'Your account has been restricted. Contact support for help.' end, 'account');
  perform _audit('user_status_' || _status, 'profile', _id::text, jsonb_build_object('reason', _reason));
end $$;
revoke all on function public.admin_set_user_status(uuid, public.account_status, text) from public, anon;
grant execute on function public.admin_set_user_status(uuid, public.account_status, text) to authenticated;

create or replace function public.admin_set_kyc(_id uuid, _level int, _reason text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform _require_role(array['compliance']::app_role[]);
  if _level not between 0 and 3 then raise exception 'Invalid level'; end if;
  if coalesce(trim(_reason), '') = '' then raise exception 'A reason is required'; end if;
  update profiles set kyc_level = _level where id = _id;
  perform _audit('kyc_level_set', 'profile', _id::text, jsonb_build_object('level', _level, 'reason', _reason));
end $$;
revoke all on function public.admin_set_kyc(uuid, int, text) from public, anon;
grant execute on function public.admin_set_kyc(uuid, int, text) to authenticated;

create or replace function public.admin_set_role(_id uuid, _role public.app_role, _grant boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform _require_role(array['super_admin']::app_role[]);
  if _role = 'user' then raise exception 'Base role cannot be changed'; end if;
  if _id = auth.uid() and _role = 'super_admin' and not _grant then raise exception 'You cannot remove your own super admin role'; end if;
  if _grant then
    insert into user_roles (user_id, role) values (_id, _role) on conflict do nothing;
  else
    delete from user_roles where user_id = _id and role = _role;
  end if;
  perform _audit(case when _grant then 'role_granted' else 'role_revoked' end, 'profile', _id::text, jsonb_build_object('role', _role));
end $$;
revoke all on function public.admin_set_role(uuid, public.app_role, boolean) from public, anon;
grant execute on function public.admin_set_role(uuid, public.app_role, boolean) to authenticated;

create or replace function public.admin_transactions(_type text default null, _status text default null,
  _asset text default null, _search text default null, _limit int default 100, _offset int default 0)
returns table (id uuid, created_at timestamptz, user_id uuid, username text, type text, status text,
               asset_code text, amount numeric, fee numeric, reference text, title text, tx_hash text, metadata jsonb)
language plpgsql stable security definer set search_path = public as $$
begin
  perform _require_role(array['support','compliance','banking_ops','crypto_ops','risk','finance','treasury']::app_role[]);
  return query
  select t.id, t.created_at, t.user_id, p.username, t.type::text, t.status::text, t.asset_code, t.amount, t.fee,
         t.reference, t.title, t.tx_hash, t.metadata
  from transactions t left join profiles p on p.id = t.user_id
  where (_type is null or t.type::text = _type) and (_status is null or t.status::text = _status)
    and (_asset is null or t.asset_code = _asset)
    and (_search is null or _search = '' or t.reference ilike '%' || _search || '%'
         or t.title ilike '%' || _search || '%' or p.username ilike '%' || _search || '%' or t.tx_hash ilike '%' || _search || '%')
  order by t.created_at desc limit least(_limit, 500) offset _offset;
end $$;
revoke all on function public.admin_transactions(text, text, text, text, int, int) from public, anon;
grant execute on function public.admin_transactions(text, text, text, text, int, int) to authenticated;

create or replace function public.admin_finance()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform _require_role(array['finance','treasury']::app_role[]);
  return jsonb_build_object(
    'system_accounts', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'asset', asset_code, 'balance', balance)
                         order by id, asset_code), '[]') from system_accounts),
    'customer_balances', (select coalesce(jsonb_agg(jsonb_build_object('asset', asset_code, 'total', t)), '[]')
                          from (select asset_code, sum(available + locked) t from wallets group by 1) x),
    'ledger_by_asset', (select coalesce(jsonb_agg(jsonb_build_object('asset', asset_code, 'net', n)), '[]')
                        from (select asset_code, sum(amount) n from ledger_entries group by 1) x),
    'recon_issues', (select coalesce(jsonb_agg(to_jsonb(v)), '[]') from v_wallet_reconciliation v where difference <> 0),
    'savings_pool_vs_plans', jsonb_build_object(
        'pool', (select balance from system_accounts where id = 'savings_pool' and asset_code = 'NGN'),
        'plans', (select coalesce(sum(balance), 0) from savings_plans)),
    'journals_24h', (select count(*) from journals where created_at > now() - interval '24 hours'));
end $$;
revoke all on function public.admin_finance() from public, anon;
grant execute on function public.admin_finance() to authenticated;

create or replace function public.admin_update_network(_id text, _deposits boolean, _withdrawals boolean,
  _fee numeric default null, _min numeric default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform _require_role(array['crypto_ops']::app_role[]);
  update networks set deposits_enabled = coalesce(_deposits, deposits_enabled),
    withdrawals_enabled = coalesce(_withdrawals, withdrawals_enabled),
    withdrawal_fee = coalesce(_fee, withdrawal_fee), min_withdrawal = coalesce(_min, min_withdrawal)
   where id = _id;
  if not found then raise exception 'Network not found'; end if;
  perform _audit('network_updated', 'network', _id,
    jsonb_build_object('deposits', _deposits, 'withdrawals', _withdrawals, 'fee', _fee, 'min', _min));
end $$;
revoke all on function public.admin_update_network(text, boolean, boolean, numeric, numeric) from public, anon;
grant execute on function public.admin_update_network(text, boolean, boolean, numeric, numeric) to authenticated;

create or replace function public.admin_update_pair(_symbol text, _enabled boolean, _fee numeric)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform _require_role(array['exchange_ops']::app_role[]);
  if _fee is not null and (_fee < 0 or _fee > 5) then raise exception 'Fee must be between 0 and 5%%'; end if;
  update trading_pairs set enabled = coalesce(_enabled, enabled), fee_pct = coalesce(_fee, fee_pct) where symbol = _symbol;
  if not found then raise exception 'Pair not found'; end if;
  perform _audit('pair_updated', 'trading_pair', _symbol, jsonb_build_object('enabled', _enabled, 'fee', _fee));
end $$;
revoke all on function public.admin_update_pair(text, boolean, numeric) from public, anon;
grant execute on function public.admin_update_pair(text, boolean, numeric) to authenticated;

create or replace function public.admin_set_setting(_key text, _value jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform _require_role(array['finance']::app_role[]);
  if _key not in ('fees', 'savings_rates', 'kyc_tiers', 'daily_limits', 'quote_ttl_seconds') then
    raise exception 'This setting cannot be edited here'; end if;
  update app_settings set value = _value, updated_at = now() where key = _key;
  perform _audit('setting_updated', 'settings', _key, _value);
end $$;
revoke all on function public.admin_set_setting(text, jsonb) from public, anon;
grant execute on function public.admin_set_setting(text, jsonb) to authenticated;

create or replace function public.admin_audit(_limit int default 100)
returns table (id bigint, created_at timestamptz, actor text, action text, entity text, entity_id text, details jsonb)
language plpgsql stable security definer set search_path = public as $$
begin
  perform _require_role(array['compliance','tech']::app_role[]);
  return query
  select a.id, a.created_at, coalesce(p.username, p.email, 'system'), a.action, a.entity, a.entity_id, a.details
  from audit_logs a left join profiles p on p.id = a.actor_id
  order by a.created_at desc limit least(_limit, 500);
end $$;
revoke all on function public.admin_audit(int) from public, anon;
grant execute on function public.admin_audit(int) to authenticated;

-- Trading kill switch wired into the exchange.
create or replace function public.exchange_quote(_from text, _to text, _amount_in numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare rf record; rt record; _fee_pct numeric; _gross numeric; _fee numeric; _out numeric;
        _ngn_value numeric; _q record; _cap numeric;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  perform _trading_open();
  if _from = _to then raise exception 'Choose two different assets'; end if;
  if coalesce(_amount_in, 0) <= 0 then raise exception 'Enter an amount'; end if;
  if (select kyc_level from profiles where id = auth.uid()) < 1 then
    raise exception 'Verify your BVN to trade'; end if;

  select * into rf from rates where asset_code = _from;
  select * into rt from rates where asset_code = _to;
  if rf is null or rt is null then raise exception 'This pair is not available'; end if;
  if least(rf.updated_at, rt.updated_at) < now() - interval '30 minutes' then
    raise exception 'Prices are updating. Try again in a moment.';
  end if;

  _ngn_value := _amount_in * rf.ngn_price;
  if _ngn_value < 500 then raise exception 'Minimum trade is ₦500'; end if;
  _cap := _kyc_trade_cap(auth.uid());
  if _ngn_value > _cap then raise exception 'Maximum trade for your KYC level is ₦%', to_char(_cap, 'FM999,999,999'); end if;

  _fee_pct := _trade_fee_pct(_from, _to);
  _gross := _amount_in * rf.ngn_price / rt.ngn_price;
  _fee := _asset_round(_to, _gross * _fee_pct / 100);
  _out := _asset_round(_to, _gross - _fee);
  if _out <= 0 then raise exception 'Amount too small'; end if;

  insert into quotes (user_id, from_asset, to_asset, amount_in, rate, fee, amount_out, fee_pct,
                      from_ngn_price, to_ngn_price, expires_at)
  values (auth.uid(), _from, _to, _asset_round(_from, _amount_in), rf.ngn_price / rt.ngn_price, _fee, _out,
          _fee_pct, rf.ngn_price, rt.ngn_price, now() + interval '30 seconds')
  returning * into _q;

  return jsonb_build_object('id', _q.id, 'from', _from, 'to', _to, 'amount_in', _q.amount_in,
    'rate', _q.rate, 'fee', _q.fee, 'fee_pct', _fee_pct, 'amount_out', _q.amount_out,
    'ngn_value', round(_ngn_value, 2), 'expires_at', _q.expires_at);
end $$;

create or replace function public.exchange_place_limit(_pair text, _side public.order_side, _price numeric,
                                                       _amount numeric, _pin text)
returns uuid language plpgsql security definer set search_path = public as $$
declare p record; _lock_asset text; _lock numeric; _wallet uuid; _id uuid; _ngn numeric; _mkt numeric;
begin
  perform _require_pin(_pin);
  perform _trading_open();
  select * into p from trading_pairs where symbol = _pair and enabled;
  if p is null then raise exception 'Pair not available'; end if;
  if coalesce(_price, 0) <= 0 or coalesce(_amount, 0) <= 0 then raise exception 'Enter a price and amount'; end if;
  if (select count(*) from orders where user_id = auth.uid() and status in ('open', 'partially_filled')) >= 20 then
    raise exception 'You can have up to 20 open orders'; end if;

  _ngn := _amount * (select ngn_price from rates where asset_code = p.base_asset);
  if _ngn < 500 then raise exception 'Minimum order is ₦500'; end if;
  if _ngn > _kyc_trade_cap(auth.uid()) then raise exception 'Order exceeds your KYC trade limit'; end if;

  _mkt := (select ngn_price from rates where asset_code = p.base_asset) / (select ngn_price from rates where asset_code = p.quote_asset);
  if _price > _mkt * 3 or _price < _mkt / 3 then raise exception 'Price is too far from the market (now %)', round(_mkt, 6); end if;

  if _side = 'buy' then _lock_asset := p.quote_asset; _lock := _asset_round(p.quote_asset, _price * _amount);
  else _lock_asset := p.base_asset; _lock := _asset_round(p.base_asset, _amount); end if;

  select id into _wallet from wallets where user_id = auth.uid() and asset_code = _lock_asset;
  insert into orders (user_id, pair, side, type, price, amount, status, locked_asset, locked_amount)
  values (auth.uid(), _pair, _side, 'limit', _price, _asset_round(p.base_asset, _amount), 'open', _lock_asset, _lock)
  returning id into _id;
  begin
    perform post_journal('ord:' || _id, 'Limit order escrow', jsonb_build_array(
      jsonb_build_object('wallet_id', _wallet, 'asset', _lock_asset, 'amount', -_lock),
      jsonb_build_object('system', 'order_escrow', 'asset', _lock_asset, 'amount', _lock)));
  exception when check_violation then raise exception 'Insufficient % balance', _lock_asset;
  end;
  update wallets set locked = locked + _lock where id = _wallet;
  return _id;
end $$;

-- Make the founder account the first super admin.
insert into public.user_roles (user_id, role)
select id, 'super_admin' from auth.users where email = 'temidayohassan2024@gmail.com'
on conflict do nothing;
