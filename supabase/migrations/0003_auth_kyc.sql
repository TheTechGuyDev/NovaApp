-- =====================================================================
-- Phase 3: auth helpers, transaction PIN, KYC
-- =====================================================================

-- Capture phone from sign-up metadata too.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, phone, full_name)
  values (
    new.id,
    new.email,
    coalesce(new.phone, nullif(new.raw_user_meta_data->>'phone', '')),
    new.raw_user_meta_data->>'full_name'
  );
  insert into public.user_roles (user_id, role) values (new.id, 'user');
  insert into public.wallets (user_id, asset_code)
    select new.id, code from public.assets where enabled;
  return new;
end $$;
revoke all on function public.handle_new_user() from public, anon, authenticated;

-- Username availability check (callable before sign-in completes).
create or replace function public.username_available(_username text)
returns boolean language sql stable security definer set search_path = public as $$
  select not exists (select 1 from profiles where username = lower(_username))
$$;
revoke all on function public.username_available(text) from public;
grant execute on function public.username_available(text) to anon, authenticated;

-- Transaction PIN (4 digits), bcrypt-hashed. Never readable by clients.
revoke select on public.profiles from anon, authenticated;
grant select (id, full_name, username, phone, email, avatar_url, date_of_birth, kyc_level,
              status, referral_code, created_at, updated_at) on public.profiles to authenticated;

create or replace function public.set_transaction_pin(_pin text, _old_pin text default null)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
declare _hash text;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  if _pin !~ '^[0-9]{4}$' then raise exception 'PIN must be 4 digits'; end if;
  select transaction_pin_hash into _hash from profiles where id = auth.uid();
  if _hash is not null and (_old_pin is null or crypt(_old_pin, _hash) <> _hash) then
    raise exception 'Current PIN is incorrect';
  end if;
  update profiles set transaction_pin_hash = crypt(_pin, gen_salt('bf')) where id = auth.uid();
  insert into audit_logs (actor_id, action, entity, entity_id) values (auth.uid(), 'pin_set', 'profile', auth.uid()::text);
  return true;
end $$;
revoke all on function public.set_transaction_pin(text, text) from public, anon;
grant execute on function public.set_transaction_pin(text, text) to authenticated;

-- Used by Edge Functions (service role) before moving money.
create or replace function public.verify_transaction_pin(_user uuid, _pin text)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select coalesce((select transaction_pin_hash = crypt(_pin, transaction_pin_hash)
                   from profiles where id = _user), false)
$$;
revoke all on function public.verify_transaction_pin(uuid, text) from public, anon, authenticated;
grant execute on function public.verify_transaction_pin(uuid, text) to service_role;

-- Lightweight "my account" view for the app (no PIN hash exposed).
create or replace function public.my_profile()
returns table (
  id uuid, full_name text, username text, phone text, email text, avatar_url text,
  kyc_level smallint, status public.account_status, has_pin boolean, referral_code text
) language sql stable security definer set search_path = public as $$
  select p.id, p.full_name, p.username, p.phone, p.email, p.avatar_url,
         p.kyc_level, p.status, p.transaction_pin_hash is not null, p.referral_code
  from profiles p where p.id = auth.uid()
$$;
revoke all on function public.my_profile() from public, anon;
grant execute on function public.my_profile() to authenticated;

-- KYC tier limits referenced by the app.
insert into public.app_settings (key, value) values
  ('kyc_tiers', '[
    {"level":0,"name":"Starter","requires":"Sign up","daily_limit":50000},
    {"level":1,"name":"Basic","requires":"BVN","daily_limit":200000},
    {"level":2,"name":"Verified","requires":"BVN + NIN","daily_limit":5000000},
    {"level":3,"name":"Premium","requires":"Selfie + address","daily_limit":50000000}
  ]')
on conflict (key) do update set value = excluded.value;
