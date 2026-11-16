-- =====================================================================
-- Phase 4: Naira banking helpers
-- =====================================================================

-- Look up a NOVA user by @username before sending (name only, no IDs leak).
create or replace function public.lookup_nova_user(_username text)
returns table (username text, full_name text)
language sql stable security definer set search_path = public as $$
  select p.username, p.full_name from profiles p
  where p.username = lower(trim(leading '@' from _username)) and p.status = 'active'
$$;
revoke all on function public.lookup_nova_user(text) from public, anon;
grant execute on function public.lookup_nova_user(text) to authenticated;

-- Total NGN-equivalent sent out today (used for KYC daily limits).
create or replace function public.daily_outflow_ngn(_user uuid)
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(sum(abs(t.amount) * coalesce(r.ngn_price, 1) + t.fee * coalesce(r.ngn_price, 1)), 0)
  from transactions t left join rates r on r.asset_code = t.asset_code
  where t.user_id = _user
    and t.type in ('transfer_out', 'withdrawal', 'bill_payment')
    and t.status in ('pending', 'processing', 'completed')
    and t.created_at >= date_trunc('day', now() at time zone 'Africa/Lagos') at time zone 'Africa/Lagos'
$$;
revoke all on function public.daily_outflow_ngn(uuid) from public, anon, authenticated;
grant execute on function public.daily_outflow_ngn(uuid) to service_role;

-- Fee schedule (editable by admin later).
insert into public.app_settings (key, value) values
  ('fees', '{
    "nova_transfer": 0,
    "bank_transfer": [{"up_to": 5000, "fee": 10}, {"up_to": 50000, "fee": 25}, {"up_to": null, "fee": 50}],
    "bill_payment": 0,
    "card_funding_pct": 0
  }')
on conflict (key) do update set value = excluded.value;

-- Bills catalogue (sandbox-simulated until a bills provider is connected).
insert into public.app_settings (key, value) values
  ('bill_billers', '{
    "airtime": ["MTN", "Airtel", "Glo", "9mobile"],
    "data": ["MTN", "Airtel", "Glo", "9mobile"],
    "electricity": ["Ikeja Electric", "Eko Electric", "Abuja Electric", "Ibadan Electric"],
    "cable": ["DStv", "GOtv", "Startimes"]
  }')
on conflict (key) do update set value = excluded.value;

create index if not exists idx_virtual_accounts_ref on public.virtual_accounts (provider_ref);
