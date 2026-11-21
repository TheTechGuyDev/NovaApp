-- Phase 11: security hardening after the attack test.
-- Fixes: daily-limit race, PIN lockout on every money path, rate limits,
-- KYC identity reuse, name change after KYC, notification tampering,
-- sandbox-only card simulator, phone enumeration, plus honeypot traps
-- and a security event log for the admin dashboard.

-- =====================================================================
-- Security event log
-- =====================================================================
create table if not exists public.security_events (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  user_id uuid references auth.users(id) on delete set null,
  ip text,
  kind text not null,
  severity text not null default 'medium' check (severity in ('low', 'medium', 'high', 'critical')),
  details jsonb
);
create index if not exists idx_security_events_created on public.security_events (created_at desc);
create index if not exists idx_security_events_user on public.security_events (user_id, created_at desc);
alter table public.security_events enable row level security;
drop policy if exists "staff security events" on public.security_events;
create policy "staff security events" on public.security_events for select using (public.is_staff());
revoke insert, update, delete on public.security_events from anon, authenticated;

-- Caller IP as seen by PostgREST (first hop of x-forwarded-for).
create or replace function public._request_ip()
returns text language sql stable as $$
  select nullif(split_part(coalesce(
    current_setting('request.headers', true)::json ->> 'x-forwarded-for',
    current_setting('request.headers', true)::json ->> 'cf-connecting-ip', ''), ',', 1), '')
$$;
revoke all on function public._request_ip() from public, anon, authenticated;

create or replace function public.log_security_event(
  _kind text, _severity text, _user uuid default null, _ip text default null, _details jsonb default null)
returns void language sql security definer set search_path = public as $$
  insert into security_events (user_id, ip, kind, severity, details)
  values (_user, coalesce(_ip, public._request_ip()), _kind, _severity, _details)
$$;
revoke all on function public.log_security_event(text, text, uuid, text, jsonb) from public, anon, authenticated;
grant execute on function public.log_security_event(text, text, uuid, text, jsonb) to service_role;

-- =====================================================================
-- Rate limiting (fixed window, shared by every Edge Function)
-- =====================================================================
create table if not exists public.rate_limits (
  key text not null,
  bucket bigint not null,
  hits int not null default 1,
  primary key (key, bucket)
);
alter table public.rate_limits enable row level security;
revoke all on public.rate_limits from anon, authenticated;

-- Returns true when the call is allowed.
create or replace function public.hit_rate_limit(_key text, _max int, _window_seconds int)
returns boolean language plpgsql security definer set search_path = public as $$
declare _bucket bigint := floor(extract(epoch from now()) / _window_seconds); _hits int;
begin
  insert into rate_limits (key, bucket) values (_key, _bucket)
  on conflict (key, bucket) do update set hits = rate_limits.hits + 1
  returning hits into _hits;
  return _hits <= _max;
end $$;
revoke all on function public.hit_rate_limit(text, int, int) from public, anon, authenticated;
grant execute on function public.hit_rate_limit(text, int, int) to service_role;

select cron.unschedule('nova-rate-limit-cleanup') where exists (select 1 from cron.job where jobname = 'nova-rate-limit-cleanup');
select cron.schedule('nova-rate-limit-cleanup', '*/10 * * * *',
  $$delete from public.rate_limits where bucket < floor(extract(epoch from now()) / 60) - 1440$$);

-- =====================================================================
-- PIN lockout: one shared counter for every PIN check
-- (5 wrong PINs in 15 minutes locks money actions for 15 minutes).
-- Failures are committed even when the action is refused.
-- =====================================================================
create or replace function public._pin_locked(_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select count(*) >= 5 from audit_logs
  where actor_id = _user and action = 'pin_failed' and created_at > now() - interval '15 minutes'
$$;
revoke all on function public._pin_locked(uuid) from public, anon, authenticated;

create or replace function public._pin_check(_user uuid, _pin text)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare _hash text; _fails int;
begin
  if public._pin_locked(_user) then return 'locked'; end if;
  select transaction_pin_hash into _hash from profiles where id = _user;
  if _hash is not null and crypt(coalesce(_pin, ''), _hash) = _hash then return 'ok'; end if;
  insert into audit_logs (actor_id, action, entity, entity_id) values (_user, 'pin_failed', 'profile', _user::text);
  select count(*) into _fails from audit_logs
    where actor_id = _user and action = 'pin_failed' and created_at > now() - interval '15 minutes';
  if _fails = 5 then
    perform public.log_security_event('pin_lockout', 'high', _user, null, jsonb_build_object('failures', _fails));
  end if;
  return 'wrong';
end $$;
revoke all on function public._pin_check(uuid, text) from public, anon, authenticated;

create or replace function public._pin_message(_r text)
returns text language sql immutable as $$
  select case _r when 'locked' then 'Too many wrong PIN attempts. Try again in 15 minutes.' else 'Incorrect PIN' end
$$;

-- Used by SQL money functions. Returns null when the PIN is right; otherwise
-- an error body. The caller returns it with HTTP 400, so the failure is saved.
create or replace function public._pin_gate(_pin text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare _r text;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  _r := public._pin_check(auth.uid(), _pin);
  if _r = 'ok' then return null; end if;
  perform set_config('response.status', case _r when 'locked' then '423' else '400' end, true);
  return jsonb_build_object('code', 'NOVA_PIN', 'message', public._pin_message(_r), 'details', null, 'hint', null);
end $$;
revoke all on function public._pin_gate(text) from public, anon, authenticated;

-- Old helper kept for anything still calling it (raises, so only safe for
-- read-only checks). Money functions below now use _pin_gate.
create or replace function public._require_pin(_pin text)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare _r text;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  _r := public._pin_check(auth.uid(), _pin);
  if _r <> 'ok' then raise exception '%', public._pin_message(_r); end if;
end $$;
revoke all on function public._require_pin(text) from public, anon, authenticated;

create or replace function public.check_my_pin(_pin text)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
declare _r text;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  _r := public._pin_check(auth.uid(), _pin);
  if _r = 'locked' then
    perform set_config('response.status', '423', true);
  end if;
  return _r = 'ok';
end $$;
revoke all on function public.check_my_pin(text) from public, anon;
grant execute on function public.check_my_pin(text) to authenticated;

-- Service-role PIN check for Edge Functions, with the same lockout.
create or replace function public.verify_transaction_pin(_user uuid, _pin text)
returns boolean language sql volatile security definer set search_path = public as $$
  select public._pin_check(_user, _pin) = 'ok'
$$;
revoke all on function public.verify_transaction_pin(uuid, text) from public, anon, authenticated;
grant execute on function public.verify_transaction_pin(uuid, text) to service_role;

-- =====================================================================
-- Daily outflow limit: atomic reservation (fixes the parallel-send race)
-- =====================================================================
create table if not exists public.outflow_holds (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  amount_ngn numeric(38,2) not null check (amount_ngn > 0),
  kind text not null,
  status text not null default 'held' check (status in ('held', 'released')),
  created_at timestamptz not null default now()
);
create index if not exists idx_outflow_holds_user_day on public.outflow_holds (user_id, created_at);
alter table public.outflow_holds enable row level security;
revoke all on public.outflow_holds from anon, authenticated;

create or replace function public.daily_outflow_ngn(_user uuid)
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(sum(amount_ngn), 0) from outflow_holds
  where user_id = _user and status = 'held'
    and created_at >= date_trunc('day', now() at time zone 'Africa/Lagos') at time zone 'Africa/Lagos'
$$;
revoke all on function public.daily_outflow_ngn(uuid) from public, anon, authenticated;
grant execute on function public.daily_outflow_ngn(uuid) to service_role;

-- Checks status, KYC, PIN (with lockout) and daily limit, then reserves the
-- amount, all under a per-user lock so parallel requests queue up.
create or replace function public.outflow_reserve(_user uuid, _pin text, _amount_ngn numeric, _kind text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare p record; _limit numeric; _spent numeric; _pin_r text; _id uuid;
begin
  perform pg_advisory_xact_lock(hashtext('outflow:' || _user::text));
  select kyc_level, status into p from profiles where id = _user;
  if p is null then return jsonb_build_object('ok', false, 'status', 404, 'error', 'Profile not found'); end if;
  if p.status <> 'active' then return jsonb_build_object('ok', false, 'status', 403, 'error', 'Account is restricted'); end if;
  if p.kyc_level < 1 then return jsonb_build_object('ok', false, 'status', 403, 'error', 'Verify your BVN to send money'); end if;
  if _amount_ngn is null or _amount_ngn <= 0 then return jsonb_build_object('ok', false, 'status', 400, 'error', 'Invalid amount'); end if;

  _pin_r := public._pin_check(_user, _pin);
  if _pin_r <> 'ok' then
    return jsonb_build_object('ok', false, 'status', case _pin_r when 'locked' then 423 else 401 end,
                              'error', public._pin_message(_pin_r));
  end if;

  select (t->>'daily_limit')::numeric into _limit
    from app_settings s, jsonb_array_elements(s.value) t
   where s.key = 'kyc_tiers' and (t->>'level')::int = p.kyc_level;
  _limit := coalesce(_limit, 0);
  _spent := public.daily_outflow_ngn(_user);
  if _spent + _amount_ngn > _limit then
    return jsonb_build_object('ok', false, 'status', 403,
      'error', 'Daily limit of ₦' || to_char(_limit, 'FM999,999,999,990') || ' reached for KYC Level ' || p.kyc_level);
  end if;
  insert into outflow_holds (user_id, amount_ngn, kind) values (_user, round(_amount_ngn, 2), _kind) returning id into _id;
  return jsonb_build_object('ok', true, 'id', _id, 'kyc_level', p.kyc_level);
end $$;
revoke all on function public.outflow_reserve(uuid, text, numeric, text) from public, anon, authenticated;
grant execute on function public.outflow_reserve(uuid, text, numeric, text) to service_role;

create or replace function public.outflow_release(_id uuid)
returns void language sql security definer set search_path = public as $$
  update outflow_holds set status = 'released' where id = _id
$$;
revoke all on function public.outflow_release(uuid) from public, anon, authenticated;
grant execute on function public.outflow_release(uuid) to service_role;

-- Count today's existing outflows so the switch-over doesn't reset limits.
insert into public.outflow_holds (user_id, amount_ngn, kind, created_at)
select t.user_id, sum(abs(t.amount) * coalesce(r.ngn_price, 1) + t.fee * coalesce(r.ngn_price, 1)), 'legacy', now()
from transactions t left join rates r on r.asset_code = t.asset_code
where t.type in ('transfer_out', 'withdrawal', 'bill_payment')
  and t.status in ('pending', 'processing', 'completed')
  and t.created_at >= date_trunc('day', now() at time zone 'Africa/Lagos') at time zone 'Africa/Lagos'
  and not exists (select 1 from outflow_holds h where h.kind = 'legacy' and h.user_id = t.user_id)
group by t.user_id
having sum(abs(t.amount)) > 0;

-- =====================================================================
-- KYC: one BVN / NIN per account (stored as a keyed hash, never plain)
-- =====================================================================
create table if not exists public.kyc_identities (
  kind text not null check (kind in ('bvn', 'nin')),
  id_hash text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (kind, id_hash)
);
alter table public.kyc_identities enable row level security;
revoke all on public.kyc_identities from anon, authenticated;

-- Names and date of birth lock once identity is verified.
create or replace function public._lock_verified_identity()
returns trigger language plpgsql as $$
begin
  if old.kyc_level >= 1 and current_user in ('authenticated', 'anon')
     and (new.full_name is distinct from old.full_name or new.date_of_birth is distinct from old.date_of_birth) then
    raise exception 'Your name and date of birth are locked after verification. Contact support to change them.';
  end if;
  return new;
end $$;
drop trigger if exists trg_lock_verified_identity on public.profiles;
create trigger trg_lock_verified_identity before update on public.profiles
  for each row execute function public._lock_verified_identity();

-- =====================================================================
-- Notifications: users may only mark them read
-- =====================================================================
revoke update on public.notifications from authenticated;
grant update (read_at) on public.notifications to authenticated;

-- =====================================================================
-- Enumeration: phone checks go through the rate-limited auth-check
-- Edge Function instead of a public RPC.
-- =====================================================================
revoke all on function public.phone_available(text) from public, anon, authenticated;
grant execute on function public.phone_available(text) to service_role;
revoke all on function public.username_available(text) from public, anon;
grant execute on function public.username_available(text) to authenticated;

-- Helpers that were callable by anyone by default.
revoke all on function public._asset_round(text, numeric) from public, anon, authenticated;
revoke all on function public._luhn_pan(text) from public, anon, authenticated;
revoke all on function public._trade_fee_pct(text, text) from public, anon, authenticated;
revoke all on function public._trading_open() from public, anon, authenticated;
revoke all on function public.txn_category(public.txn_type, jsonb, jsonb) from public, anon, authenticated;
revoke all on function public.normalize_ng_phone(text) from public, anon, authenticated;
revoke all on function public._spend_value(public.transactions) from public, anon, authenticated;

-- =====================================================================
-- Honeypots: decoy RPCs nobody legitimate calls. Any call is logged as a
-- critical event and a signed-in caller's account is frozen.
-- =====================================================================
create or replace function public._honeypot(_name text, _args jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.log_security_event('honeypot:' || _name, 'critical', auth.uid(), null,
    jsonb_build_object('args', _args, 'role', current_user,
      'agent', current_setting('request.headers', true)::json ->> 'user-agent'));
  if auth.uid() is not null then
    update profiles set status = 'frozen' where id = auth.uid() and status = 'active';
    insert into audit_logs (actor_id, action, entity, entity_id, details)
    values (auth.uid(), 'auto_frozen', 'profile', auth.uid()::text, jsonb_build_object('reason', 'honeypot:' || _name));
  end if;
  perform set_config('response.status', '403', true);
  return jsonb_build_object('code', '42501', 'message', 'permission denied for function ' || _name, 'details', null, 'hint', null);
end $$;
revoke all on function public._honeypot(text, jsonb) from public, anon, authenticated;

create or replace function public.get_service_role_key()
returns jsonb language sql security definer set search_path = public as $$
  select public._honeypot('get_service_role_key', '{}'::jsonb)
$$;
create or replace function public.admin_export_all_users(_format text default 'csv')
returns jsonb language sql security definer set search_path = public as $$
  select public._honeypot('admin_export_all_users', jsonb_build_object('format', _format))
$$;
create or replace function public.debug_exec_sql(_query text)
returns jsonb language sql security definer set search_path = public as $$
  select public._honeypot('debug_exec_sql', jsonb_build_object('query', left(_query, 500)))
$$;
create or replace function public.wallet_credit(_user uuid, _amount numeric)
returns jsonb language sql security definer set search_path = public as $$
  select public._honeypot('wallet_credit', jsonb_build_object('user', _user, 'amount', _amount))
$$;
revoke all on function public.get_service_role_key() from public;
revoke all on function public.admin_export_all_users(text) from public;
revoke all on function public.debug_exec_sql(text) from public;
revoke all on function public.wallet_credit(uuid, numeric) from public;
grant execute on function public.get_service_role_key() to anon, authenticated;
grant execute on function public.admin_export_all_users(text) to anon, authenticated;
grant execute on function public.debug_exec_sql(text) to anon, authenticated;
grant execute on function public.wallet_credit(uuid, numeric) to anon, authenticated;

-- =====================================================================
-- Per-account login lockout (Auth password-verification hook).
-- Needs Supabase Pro: enable in Auth > Hooks once upgraded.
-- 5 wrong passwords in 15 minutes locks sign-in for that account.
-- =====================================================================
create table if not exists public.login_failures (
  user_id uuid not null,
  created_at timestamptz not null default now()
);
create index if not exists idx_login_failures on public.login_failures (user_id, created_at);
alter table public.login_failures enable row level security;
revoke all on public.login_failures from anon, authenticated;

create or replace function public.hook_password_verification_attempt(event jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare _user uuid := (event ->> 'user_id')::uuid; _valid boolean := (event ->> 'valid')::boolean; _fails int;
begin
  select count(*) into _fails from login_failures
   where user_id = _user and created_at > now() - interval '15 minutes';
  if _fails >= 5 then
    return jsonb_build_object('decision', 'reject',
      'message', 'Too many failed sign-in attempts. Try again in 15 minutes.', 'should_logout_user', false);
  end if;
  if not _valid then
    insert into login_failures (user_id) values (_user);
    if _fails + 1 = 5 then
      insert into security_events (user_id, kind, severity, details)
      values (_user, 'login_lockout', 'high', jsonb_build_object('failures', 5));
    end if;
    return jsonb_build_object('decision', 'continue');
  end if;
  delete from login_failures where user_id = _user;
  return jsonb_build_object('decision', 'continue');
end $$;
grant usage on schema public to supabase_auth_admin;
grant execute on function public.hook_password_verification_attempt(jsonb) to supabase_auth_admin;
revoke execute on function public.hook_password_verification_attempt(jsonb) from public, anon, authenticated;
grant select, insert, delete on public.login_failures to supabase_auth_admin;
grant insert on public.security_events to supabase_auth_admin;
drop policy if exists "auth admin login failures" on public.login_failures;
create policy "auth admin login failures" on public.login_failures for all to supabase_auth_admin using (true) with check (true);
drop policy if exists "auth admin security events" on public.security_events;
create policy "auth admin security events" on public.security_events for insert to supabase_auth_admin with check (true);

-- =====================================================================
-- Admin: security events feed
-- =====================================================================
create or replace function public.admin_security_events(_limit int default 200)
returns table (id bigint, created_at timestamptz, user_id uuid, email text, ip text, kind text,
               severity text, details jsonb)
language plpgsql stable security definer set search_path = public as $$
begin
  perform _require_role(array['super_admin', 'compliance', 'risk', 'support', 'tech']::app_role[]);
  return query
    select e.id, e.created_at, e.user_id, p.email, e.ip, e.kind, e.severity, e.details
    from security_events e left join profiles p on p.id = e.user_id
    order by e.created_at desc limit least(greatest(_limit, 1), 1000);
end $$;
revoke all on function public.admin_security_events(int) from public, anon;
grant execute on function public.admin_security_events(int) to authenticated;

-- =====================================================================
-- Money functions rewritten to use _pin_gate (below, generated from the
-- live definitions so their behaviour is otherwise unchanged).
-- =====================================================================
-- card_fund
CREATE OR REPLACE FUNCTION public.card_fund(_card uuid, _usd numeric, _pin text, _key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare _pin_err jsonb; c record; _rate numeric; _ngn numeric(38,2); _fee numeric(38,2); _journal uuid;
begin
  _pin_err := public._pin_gate(_pin);
  if _pin_err is not null then return _pin_err; end if;
  select * into c from cards where id = _card and user_id = auth.uid() for update;
  if c is null or c.currency <> 'USD' then raise exception 'Only USD cards are funded'; end if;
  if c.status <> 'active' then raise exception 'Unfreeze the card first'; end if;
  if coalesce(_usd, 0) < 1 then raise exception 'Minimum is $1'; end if;
  select ngn_price into _rate from rates where asset_code = 'USDT';
  _ngn := round(_usd * _rate, 2); _fee := round(_ngn * 0.01, 2);
  begin
    _journal := post_journal('cfund:' || auth.uid() || ':' || _key, 'USD card funding', jsonb_build_array(
      jsonb_build_object('wallet_id', _ngn_wallet(auth.uid()), 'asset', 'NGN', 'amount', -(_ngn + _fee)),
      jsonb_build_object('system', 'card_settlement', 'asset', 'NGN', 'amount', _ngn),
      jsonb_build_object('system', 'fees', 'asset', 'NGN', 'amount', _fee)));
  exception when check_violation then raise exception 'Insufficient Naira balance';
  end;
  if exists (select 1 from transactions where journal_id = _journal) then return jsonb_build_object('duplicate', true); end if;
  update cards set balance = balance + _usd where id = _card;
  insert into transactions (user_id, journal_id, type, status, asset_code, amount, fee, title, metadata)
  values (auth.uid(), _journal, 'card_funding', 'completed', 'NGN', -_ngn, _fee, 'Funded card •••• ' || c.last4,
          jsonb_build_object('card_id', _card, 'usd', _usd, 'rate', _rate));
  return jsonb_build_object('ngn', _ngn, 'fee', _fee, 'rate', _rate);
end $function$;

-- card_reveal
CREATE OR REPLACE FUNCTION public.card_reveal(_card uuid, _pin text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare _pin_err jsonb; c record;
begin
  _pin_err := public._pin_gate(_pin);
  if _pin_err is not null then return _pin_err; end if;
  select * into c from cards where id = _card and user_id = auth.uid() and status <> 'terminated';
  if c is null then raise exception 'Card not found'; end if;
  insert into audit_logs (actor_id, action, entity, entity_id) values (auth.uid(), 'card_reveal', 'card', _card::text);
  return jsonb_build_object('pan', c.pan, 'cvv', c.cvv,
    'expiry', lpad(c.expiry_month::text, 2, '0') || '/' || right(c.expiry_year::text, 2));
end $function$;

-- card_terminate
CREATE OR REPLACE FUNCTION public.card_terminate(_card uuid, _pin text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare _pin_err jsonb; c record; _rate numeric; _ngn numeric(38,2) := 0; _journal uuid;
begin
  _pin_err := public._pin_gate(_pin);
  if _pin_err is not null then return _pin_err; end if;
  select * into c from cards where id = _card and user_id = auth.uid() and status <> 'terminated' for update;
  if c is null then raise exception 'Card not found'; end if;
  if c.currency = 'USD' and c.balance > 0 then   -- refund remaining USD to Naira
    select ngn_price into _rate from rates where asset_code = 'USDT';
    _ngn := round(c.balance * _rate, 2);
    _journal := post_journal('cterm:' || _card, 'Card balance refund', jsonb_build_array(
      jsonb_build_object('system', 'card_settlement', 'asset', 'NGN', 'amount', -_ngn),
      jsonb_build_object('wallet_id', _ngn_wallet(auth.uid()), 'asset', 'NGN', 'amount', _ngn)));
    insert into transactions (user_id, journal_id, type, status, asset_code, amount, title, metadata)
    values (auth.uid(), _journal, 'reversal', 'completed', 'NGN', _ngn, 'Card •••• ' || c.last4 || ' refund',
            jsonb_build_object('card_id', _card, 'usd', c.balance));
  end if;
  update cards set status = 'terminated', balance = 0 where id = _card;
  return jsonb_build_object('refunded_ngn', _ngn);
end $function$;

-- savings_withdraw
CREATE OR REPLACE FUNCTION public.savings_withdraw(_plan uuid, _amount numeric, _pin text, _key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare _pin_err jsonb; p record; _wallet uuid; _journal uuid; _amt numeric(38,2); _forfeit numeric(38,2) := 0; _all boolean;
begin
  _pin_err := public._pin_gate(_pin);
  if _pin_err is not null then return _pin_err; end if;
  perform _savings_accrue(_plan);
  select * into p from savings_plans where id = _plan and user_id = auth.uid() for update;
  if p is null then raise exception 'Plan not found'; end if;
  if p.status <> 'active' then raise exception 'This plan is closed'; end if;

  _amt := round(coalesce(_amount, p.balance), 2);
  if _amt <= 0 or _amt > p.balance then raise exception 'Amount exceeds plan balance'; end if;

  if p.kind = 'fixed' then
    _amt := p.balance;  -- fixed plans close in full
    if now() < p.locked_until then
      _forfeit := p.interest_earned;
      _amt := p.balance - _forfeit;
    end if;
  end if;
  _all := (p.kind = 'fixed') or (_amt + _forfeit >= p.balance);

  _wallet := _ngn_wallet(p.user_id);
  _journal := post_journal('savw:' || auth.uid() || ':' || _key, 'Savings withdrawal · ' || p.name,
    jsonb_build_array(
      jsonb_build_object('system', 'savings_pool', 'asset', 'NGN', 'amount', -(_amt + _forfeit)),
      jsonb_build_object('wallet_id', _wallet, 'asset', 'NGN', 'amount', _amt)) ||
    case when _forfeit > 0 then jsonb_build_array(
      jsonb_build_object('system', 'interest_expense', 'asset', 'NGN', 'amount', _forfeit)) else '[]'::jsonb end);
  if exists (select 1 from transactions where journal_id = _journal) then
    return jsonb_build_object('amount', _amt, 'duplicate', true); end if;

  update savings_plans set
    balance = balance - _amt - _forfeit,
    principal = greatest(principal - _amt, 0),
    interest_earned = interest_earned - _forfeit,
    status = case when _all and kind <> 'flexible' then 'closed' else status end
  where id = _plan;
  insert into transactions (user_id, journal_id, type, status, asset_code, amount, title, metadata)
  values (p.user_id, _journal, 'savings_withdrawal', 'completed', 'NGN', _amt, 'From ' || p.name,
          jsonb_build_object('plan_id', _plan, 'forfeited_interest', _forfeit));
  return jsonb_build_object('amount', _amt, 'forfeited_interest', _forfeit);
end $function$;

-- exchange_execute
CREATE OR REPLACE FUNCTION public.exchange_execute(_quote uuid, _pin text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare _pin_err jsonb; q record; wf uuid; wt uuid; _journal uuid; _ref text;
begin
  _pin_err := public._pin_gate(_pin);
  if _pin_err is not null then return _pin_err; end if;
  select * into q from quotes where id = _quote and user_id = auth.uid() for update;
  if q is null then raise exception 'Quote not found'; end if;
  if q.status = 'accepted' then
    select reference into _ref from transactions where journal_id =
      (select id from journals where idempotency_key = 'swap:' || q.id) limit 1;
    return jsonb_build_object('status', 'completed', 'reference', _ref, 'duplicate', true);
  end if;
  if q.status <> 'open' or q.expires_at < now() then
    update quotes set status = 'expired' where id = q.id and status = 'open';
    raise exception 'Quote expired. Get a new price.';
  end if;

  select id into wf from wallets where user_id = auth.uid() and asset_code = q.from_asset and status = 'active';
  select id into wt from wallets where user_id = auth.uid() and asset_code = q.to_asset and status = 'active';
  if wf is null or wt is null then raise exception 'Wallet unavailable'; end if;

  begin
    _journal := post_journal('swap:' || q.id, 'Swap ' || q.from_asset || ' to ' || q.to_asset, jsonb_build_array(
      jsonb_build_object('wallet_id', wf, 'asset', q.from_asset, 'amount', -q.amount_in),
      jsonb_build_object('system', 'liquidity', 'asset', q.from_asset, 'amount', q.amount_in),
      jsonb_build_object('wallet_id', wt, 'asset', q.to_asset, 'amount', q.amount_out),
      jsonb_build_object('system', 'fees', 'asset', q.to_asset, 'amount', q.fee),
      jsonb_build_object('system', 'liquidity', 'asset', q.to_asset, 'amount', -(q.amount_out + q.fee))));
  exception when check_violation then
    raise exception 'Insufficient % balance', q.from_asset;
  end;
  update quotes set status = 'accepted' where id = q.id;

  insert into transactions (user_id, journal_id, type, status, asset_code, amount, title, metadata)
  values (auth.uid(), _journal, 'conversion', 'completed', q.from_asset, -q.amount_in,
          case when q.to_asset = 'NGN' then 'Sold ' || q.from_asset else 'Swapped ' || q.from_asset || ' to ' || q.to_asset end,
          jsonb_build_object('quote_id', q.id, 'leg', 'out', 'pair', q.from_asset || '/' || q.to_asset, 'rate', q.rate))
  returning reference into _ref;
  insert into transactions (user_id, journal_id, type, status, asset_code, amount, fee, title, metadata)
  values (auth.uid(), _journal, 'conversion', 'completed', q.to_asset, q.amount_out, q.fee,
          case when q.from_asset = 'NGN' then 'Bought ' || q.to_asset else 'Received ' || q.to_asset end,
          jsonb_build_object('quote_id', q.id, 'leg', 'in', 'pair', q.from_asset || '/' || q.to_asset, 'rate', q.rate));
  return jsonb_build_object('status', 'completed', 'reference', _ref, 'amount_out', q.amount_out, 'to', q.to_asset);
end $function$;

-- card_set_pin
drop function if exists public.card_set_pin(uuid, text, text);
CREATE OR REPLACE FUNCTION public.card_set_pin(_card uuid, _card_pin text, _pin text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare _pin_err jsonb;
begin
  _pin_err := public._pin_gate(_pin);
  if _pin_err is not null then return _pin_err; end if;
  if _card_pin !~ '^[0-9]{4}$' then raise exception 'Card PIN must be 4 digits'; end if;
  update cards set pin_hash = crypt(_card_pin, gen_salt('bf')) where id = _card and user_id = auth.uid();
  if not found then raise exception 'Card not found'; end if;
  return jsonb_build_object('ok', true);
end $function$;
revoke all on function public.card_set_pin(uuid, text, text) from public, anon;
grant execute on function public.card_set_pin(uuid, text, text) to authenticated;

-- savings_deposit
drop function if exists public.savings_deposit(uuid, numeric, text, text);
CREATE OR REPLACE FUNCTION public.savings_deposit(_plan uuid, _amount numeric, _pin text, _key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare _pin_err jsonb;
begin
  _pin_err := public._pin_gate(_pin);
  if _pin_err is not null then return _pin_err; end if;
  if not exists (select 1 from savings_plans where id = _plan and user_id = auth.uid()) then
    raise exception 'Plan not found'; end if;
  if coalesce(_amount, 0) < 100 then raise exception 'Minimum deposit is ₦100'; end if;
  perform _savings_accrue(_plan);
  begin
    perform _savings_fund(_plan, round(_amount, 2), 'sav:' || auth.uid() || ':' || _key, false);
  exception when check_violation then raise exception 'Insufficient Naira balance';
  end;
  return jsonb_build_object('ok', true);
end $function$;
revoke all on function public.savings_deposit(uuid, numeric, text, text) from public, anon;
grant execute on function public.savings_deposit(uuid, numeric, text, text) to authenticated;

-- exchange_place_limit
drop function if exists public.exchange_place_limit(text, order_side, numeric, numeric, text);
CREATE OR REPLACE FUNCTION public.exchange_place_limit(_pair text, _side order_side, _price numeric, _amount numeric, _pin text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare _pin_err jsonb; p record; _lock_asset text; _lock numeric; _wallet uuid; _id uuid; _ngn numeric; _mkt numeric;
begin
  _pin_err := public._pin_gate(_pin);
  if _pin_err is not null then return _pin_err; end if;
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
  return jsonb_build_object('id', _id);
end $function$;
revoke all on function public.exchange_place_limit(text, order_side, numeric, numeric, text) from public, anon;
grant execute on function public.exchange_place_limit(text, order_side, numeric, numeric, text) to authenticated;

-- card_simulate_purchase: sandbox only
CREATE OR REPLACE FUNCTION public.card_simulate_purchase(_card uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c record; m jsonb; _amt numeric(38,2); _ngn numeric(38,2); _rate numeric; _journal uuid; _today numeric;
  _merchants jsonb := '[
    {"name":"Shoprite","cat":"Groceries","ngn":[3000,45000],"usd":[5,60]},
    {"name":"Chicken Republic","cat":"Food & Drinks","ngn":[2500,12000],"usd":[3,15]},
    {"name":"Netflix","cat":"Entertainment","ngn":[2900,7500],"usd":[7,15]},
    {"name":"Spotify","cat":"Entertainment","ngn":[1300,2600],"usd":[3,11]},
    {"name":"Bolt","cat":"Transport","ngn":[1500,9000],"usd":[3,20]},
    {"name":"Jumia","cat":"Shopping","ngn":[5000,80000],"usd":[10,90]},
    {"name":"Amazon","cat":"Shopping","ngn":[8000,90000],"usd":[10,120]},
    {"name":"Apple","cat":"Subscriptions","ngn":[1500,9000],"usd":[1,20]}
  ]';
begin
  if coalesce((select value #>> '{}' from app_settings where key = 'environment'), 'sandbox') <> 'sandbox' then
    raise exception 'Card simulator is only available in sandbox mode';
  end if;
  select * into c from cards where id = _card and user_id = auth.uid() for update;
  if c is null then raise exception 'Card not found'; end if;
  if c.status <> 'active' then raise exception 'Declined: card is frozen'; end if;
  if not c.online_enabled then raise exception 'Declined: online payments are off'; end if;
  m := _merchants -> floor(random() * jsonb_array_length(_merchants))::int;
  if c.currency = 'USD' then
    if m->>'name' in ('Shoprite', 'Chicken Republic', 'Jumia') then m := _merchants -> 6; end if;
    _amt := round((((m->'usd'->>0)::numeric) + random() * (((m->'usd'->>1)::numeric) - ((m->'usd'->>0)::numeric)))::numeric, 2);
    if not c.international_enabled then raise exception 'Declined: international payments are off'; end if;
    if _amt > c.balance then raise exception 'Declined: insufficient card balance ($%)', c.balance; end if;
    select coalesce(sum(-(metadata->>'usd')::numeric), 0) into _today from transactions
      where user_id = auth.uid() and type = 'card_payment' and metadata->>'card_id' = _card::text
        and created_at >= date_trunc('day', now());
    if _today + _amt > c.daily_limit then raise exception 'Declined: daily card limit reached'; end if;
    select ngn_price into _rate from rates where asset_code = 'USDT';
    update cards set balance = balance - _amt where id = _card;
    insert into transactions (user_id, type, status, asset_code, amount, title, category, metadata)
    values (auth.uid(), 'card_payment', 'completed', 'NGN', 0, m->>'name', m->>'cat',
            jsonb_build_object('card_id', _card, 'usd', -_amt, 'last4', c.last4, 'simulated', true,
                               'merchant_category', m->>'cat', 'ngn_equivalent', round(_amt * _rate, 2)));
    return jsonb_build_object('merchant', m->>'name', 'amount', _amt, 'currency', 'USD');
  end if;
  _ngn := round((((m->'ngn'->>0)::numeric) + random() * (((m->'ngn'->>1)::numeric) - ((m->'ngn'->>0)::numeric)))::numeric, -1);
  select coalesce(sum(-amount), 0) into _today from transactions
    where user_id = auth.uid() and type = 'card_payment' and metadata->>'card_id' = _card::text
      and created_at >= date_trunc('day', now());
  if _today + _ngn > c.daily_limit then raise exception 'Declined: daily card limit reached'; end if;
  begin
    _journal := post_journal('cpay:' || gen_random_uuid(), 'Card payment ' || (m->>'name'), jsonb_build_array(
      jsonb_build_object('wallet_id', _ngn_wallet(auth.uid()), 'asset', 'NGN', 'amount', -_ngn),
      jsonb_build_object('system', 'card_settlement', 'asset', 'NGN', 'amount', _ngn)));
  exception when check_violation then raise exception 'Declined: insufficient Naira balance';
  end;
  insert into transactions (user_id, journal_id, type, status, asset_code, amount, title, category, metadata)
  values (auth.uid(), _journal, 'card_payment', 'completed', 'NGN', -_ngn, m->>'name', m->>'cat',
          jsonb_build_object('card_id', _card, 'last4', c.last4, 'simulated', true, 'merchant_category', m->>'cat'));
  return jsonb_build_object('merchant', m->>'name', 'amount', _ngn, 'currency', 'NGN');
end $function$;
