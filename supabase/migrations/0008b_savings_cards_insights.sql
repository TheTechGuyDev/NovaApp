-- =====================================================================
-- Phase 8: savings, virtual cards (simulated), spending insights
-- All money still moves through post_journal(); these functions are the
-- only way clients can touch savings or card balances.
-- =====================================================================

-- ---------- Spending categories ----------
alter table public.transactions add column if not exists category text;
create index if not exists idx_txn_user_cat on public.transactions (user_id, category, created_at desc);

create or replace function public.txn_category(_type public.txn_type, _cp jsonb, _meta jsonb)
returns text language sql immutable as $$
  select case
    when _type = 'bill_payment' then case _cp->>'category'
        when 'airtime' then 'Airtime & Data' when 'data' then 'Airtime & Data'
        when 'electricity' then 'Utilities' when 'cable' then 'Entertainment' else 'Bills' end
    when _type = 'card_payment' then coalesce(_meta->>'merchant_category', 'Shopping')
    when _type in ('transfer_out', 'withdrawal') then 'Transfers'
    when _type in ('savings_deposit', 'savings_withdrawal') then 'Savings'
    when _type in ('trade', 'conversion') then 'Crypto'
    when _type in ('deposit', 'transfer_in', 'interest', 'reversal') then 'Income'
    when _type in ('fee', 'card_funding') then 'Fees & Cards'
    else 'Other' end
$$;

create or replace function public.set_txn_category()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.category is null then
    new.category := public.txn_category(new.type, coalesce(new.counterparty, '{}'), coalesce(new.metadata, '{}'));
  end if;
  return new;
end $$;
drop trigger if exists trg_txn_category on public.transactions;
create trigger trg_txn_category before insert on public.transactions
  for each row execute function public.set_txn_category();
update public.transactions set category = public.txn_category(type, coalesce(counterparty,'{}'), coalesce(metadata,'{}')) where category is null;

-- ---------- Helpers ----------
create or replace function public._require_pin(_pin text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  if not public.check_my_pin(_pin) then raise exception 'Incorrect PIN'; end if;
end $$;
revoke all on function public._require_pin(text) from public, anon, authenticated;

create or replace function public._ngn_wallet(_user uuid)
returns uuid language sql stable security definer set search_path = public as $$
  select id from wallets where user_id = _user and asset_code = 'NGN'
$$;
revoke all on function public._ngn_wallet(uuid) from public, anon, authenticated;

-- =====================================================================
-- SAVINGS
-- =====================================================================
create table public.savings_plans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('flexible', 'fixed', 'goal')),
  name text not null,
  icon text,
  target_amount numeric(38,2),
  target_date date,
  interest_rate numeric(6,3) not null,            -- % per year
  balance numeric(38,2) not null default 0 check (balance >= 0),
  principal numeric(38,2) not null default 0,
  interest_earned numeric(38,2) not null default 0,
  locked_until timestamptz,
  auto_amount numeric(38,2),
  auto_frequency text check (auto_frequency in ('daily', 'weekly', 'monthly')),
  next_auto_at timestamptz,
  last_accrued_at timestamptz not null default now(),
  status text not null default 'active' check (status in ('active', 'completed', 'closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on public.savings_plans (user_id);
create trigger trg_savings_updated before update on public.savings_plans
  for each row execute function public.set_updated_at();
alter table public.savings_plans enable row level security;
create policy "own savings" on public.savings_plans for select to authenticated
  using (user_id = auth.uid() or public.is_staff());

insert into public.app_settings (key, value) values ('savings_rates', '{
  "flexible": 10, "goal": 12,
  "fixed": [{"days": 30, "rate": 14}, {"days": 90, "rate": 16}, {"days": 180, "rate": 18}, {"days": 365, "rate": 20}],
  "fixed_break_penalty": "forfeit_interest"
}') on conflict (key) do update set value = excluded.value;

-- Daily-compounded interest accrued lazily (and nightly by cron).
create or replace function public._savings_accrue(_plan uuid)
returns void language plpgsql security definer set search_path = public as $$
declare p record; _days numeric; _interest numeric(38,2);
begin
  select * into p from savings_plans where id = _plan for update;
  if p is null or p.status <> 'active' or p.balance <= 0 then
    update savings_plans set last_accrued_at = now() where id = _plan; return;
  end if;
  _days := floor(extract(epoch from (now() - p.last_accrued_at)) / 86400);
  if _days < 1 then return; end if;
  _interest := round(p.balance * (power(1 + p.interest_rate / 100 / 365, _days) - 1), 2);
  if _interest > 0 then
    perform post_journal('int:' || _plan || ':' || to_char(p.last_accrued_at + make_interval(days => _days::int), 'YYYYMMDD'),
      'Savings interest',
      jsonb_build_array(
        jsonb_build_object('system', 'savings_pool', 'asset', 'NGN', 'amount', _interest),
        jsonb_build_object('system', 'interest_expense', 'asset', 'NGN', 'amount', -_interest)));
    insert into transactions (user_id, type, status, asset_code, amount, title, metadata)
    values (p.user_id, 'interest', 'completed', 'NGN', _interest, 'Interest · ' || p.name,
            jsonb_build_object('plan_id', _plan, 'days', _days));
  end if;
  update savings_plans
     set balance = balance + _interest, interest_earned = interest_earned + _interest,
         last_accrued_at = last_accrued_at + make_interval(days => _days::int)
   where id = _plan;
end $$;
revoke all on function public._savings_accrue(uuid) from public, anon, authenticated;

create or replace function public.savings_create(
  _kind text, _name text, _target numeric default null, _target_date date default null,
  _lock_days int default null, _auto_amount numeric default null, _auto_frequency text default null,
  _icon text default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare _rate numeric; _id uuid; _rates jsonb;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  if coalesce(trim(_name), '') = '' then raise exception 'Give your plan a name'; end if;
  select value into _rates from app_settings where key = 'savings_rates';
  if _kind = 'flexible' then _rate := (_rates->>'flexible')::numeric;
  elsif _kind = 'goal' then
    if coalesce(_target, 0) <= 0 then raise exception 'Set a target amount'; end if;
    _rate := (_rates->>'goal')::numeric;
  elsif _kind = 'fixed' then
    select (r->>'rate')::numeric into _rate from jsonb_array_elements(_rates->'fixed') r
     where (r->>'days')::int = _lock_days;
    if _rate is null then raise exception 'Choose 30, 90, 180 or 365 days'; end if;
  else raise exception 'Unknown plan type'; end if;
  if _auto_frequency is not null and coalesce(_auto_amount, 0) < 100 then
    raise exception 'Auto-save amount must be at least ₦100';
  end if;

  insert into savings_plans (user_id, kind, name, icon, target_amount, target_date, interest_rate,
                             locked_until, auto_amount, auto_frequency, next_auto_at)
  values (auth.uid(), _kind, trim(_name), _icon, _target, _target_date, _rate,
          case when _kind = 'fixed' then now() + make_interval(days => _lock_days) end,
          case when _auto_frequency is not null then _auto_amount end, _auto_frequency,
          case _auto_frequency when 'daily' then now() + interval '1 day'
                               when 'weekly' then now() + interval '7 days'
                               when 'monthly' then now() + interval '1 month' end)
  returning id into _id;
  return _id;
end $$;
revoke all on function public.savings_create(text, text, numeric, date, int, numeric, text, text) from public, anon;
grant execute on function public.savings_create(text, text, numeric, date, int, numeric, text, text) to authenticated;

-- Internal: move NGN from wallet into a plan (used by deposit + auto-save).
create or replace function public._savings_fund(_plan uuid, _amount numeric, _key text, _auto boolean)
returns void language plpgsql security definer set search_path = public as $$
declare p record; _wallet uuid; _journal uuid;
begin
  select * into p from savings_plans where id = _plan for update;
  if p.status <> 'active' then raise exception 'This plan is closed'; end if;
  if p.kind = 'fixed' and p.principal > 0 then raise exception 'Fixed savings take one deposit. Create a new plan to lock more.'; end if;
  _wallet := _ngn_wallet(p.user_id);
  _journal := post_journal(_key, 'Savings deposit · ' || p.name, jsonb_build_array(
    jsonb_build_object('wallet_id', _wallet, 'asset', 'NGN', 'amount', -_amount),
    jsonb_build_object('system', 'savings_pool', 'asset', 'NGN', 'amount', _amount)));
  if exists (select 1 from transactions where journal_id = _journal) then return; end if;
  update savings_plans set balance = balance + _amount, principal = principal + _amount,
    status = case when kind = 'goal' and balance + _amount >= target_amount then 'active' else status end
   where id = _plan;
  insert into transactions (user_id, journal_id, type, status, asset_code, amount, title, metadata)
  values (p.user_id, _journal, 'savings_deposit', 'completed', 'NGN', -_amount,
          case when _auto then 'Auto-save · ' else 'Saved to ' end || p.name,
          jsonb_build_object('plan_id', _plan, 'auto', _auto));
end $$;
revoke all on function public._savings_fund(uuid, numeric, text, boolean) from public, anon, authenticated;

create or replace function public.savings_deposit(_plan uuid, _amount numeric, _pin text, _key text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform _require_pin(_pin);
  if not exists (select 1 from savings_plans where id = _plan and user_id = auth.uid()) then
    raise exception 'Plan not found'; end if;
  if coalesce(_amount, 0) < 100 then raise exception 'Minimum deposit is ₦100'; end if;
  perform _savings_accrue(_plan);
  begin
    perform _savings_fund(_plan, round(_amount, 2), 'sav:' || auth.uid() || ':' || _key, false);
  exception when check_violation then raise exception 'Insufficient Naira balance';
  end;
end $$;
revoke all on function public.savings_deposit(uuid, numeric, text, text) from public, anon;
grant execute on function public.savings_deposit(uuid, numeric, text, text) to authenticated;

-- Withdraw to Naira wallet. Fixed plans before maturity: interest is forfeited.
create or replace function public.savings_withdraw(_plan uuid, _amount numeric, _pin text, _key text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare p record; _wallet uuid; _journal uuid; _amt numeric(38,2); _forfeit numeric(38,2) := 0; _all boolean;
begin
  perform _require_pin(_pin);
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
end $$;
revoke all on function public.savings_withdraw(uuid, numeric, text, text) from public, anon;
grant execute on function public.savings_withdraw(uuid, numeric, text, text) to authenticated;

create or replace function public.savings_update_auto(_plan uuid, _amount numeric, _frequency text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if _frequency is not null and coalesce(_amount, 0) < 100 then raise exception 'Minimum auto-save is ₦100'; end if;
  update savings_plans set auto_amount = case when _frequency is null then null else _amount end,
    auto_frequency = _frequency,
    next_auto_at = case _frequency when 'daily' then now() + interval '1 day'
                                   when 'weekly' then now() + interval '7 days'
                                   when 'monthly' then now() + interval '1 month' end
   where id = _plan and user_id = auth.uid() and kind <> 'fixed';
  if not found then raise exception 'Plan not found'; end if;
end $$;
revoke all on function public.savings_update_auto(uuid, numeric, text) from public, anon;
grant execute on function public.savings_update_auto(uuid, numeric, text) to authenticated;

-- Accrue all of my plans, then return them.
create or replace function public.my_savings()
returns setof public.savings_plans language plpgsql security definer set search_path = public as $$
declare r record;
begin
  for r in select id from savings_plans where user_id = auth.uid() and status = 'active' loop
    perform _savings_accrue(r.id);
  end loop;
  return query select * from savings_plans where user_id = auth.uid() order by status, created_at desc;
end $$;
revoke all on function public.my_savings() from public, anon;
grant execute on function public.my_savings() to authenticated;

-- Cron: run due auto-saves and accrue interest nightly.
create or replace function public.savings_run_scheduled()
returns int language plpgsql security definer set search_path = public as $$
declare r record; _n int := 0;
begin
  for r in select * from savings_plans where status = 'active' loop
    perform _savings_accrue(r.id);
  end loop;
  for r in select * from savings_plans
            where status = 'active' and auto_frequency is not null and next_auto_at <= now() loop
    begin
      perform _savings_fund(r.id, r.auto_amount, 'auto:' || r.id || ':' || to_char(r.next_auto_at, 'YYYYMMDDHH24'), true);
      _n := _n + 1;
    exception when others then
      insert into notifications (user_id, title, body, category)
      values (r.user_id, 'Auto-save skipped', 'Not enough Naira for your ' || r.name || ' auto-save.', 'savings');
    end;
    update savings_plans set next_auto_at = next_auto_at + case auto_frequency
      when 'daily' then interval '1 day' when 'weekly' then interval '7 days' else interval '1 month' end
     where id = r.id;
  end loop;
  return _n;
end $$;
revoke all on function public.savings_run_scheduled() from public, anon, authenticated;

-- =====================================================================
-- VIRTUAL CARDS (simulated until a card issuer is connected)
-- =====================================================================
create table public.cards (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  label text not null default 'Virtual Card',
  brand text not null check (brand in ('Verve', 'Visa', 'Mastercard')),
  currency text not null check (currency in ('NGN', 'USD')),
  pan text not null,
  cvv text not null,
  last4 text not null,
  expiry_month int not null,
  expiry_year int not null,
  balance numeric(38,2) not null default 0 check (balance >= 0),   -- USD cards only
  status text not null default 'active' check (status in ('active', 'frozen', 'terminated')),
  daily_limit numeric(38,2) not null default 200000,
  online_enabled boolean not null default true,
  international_enabled boolean not null default false,
  pin_hash text,
  color text not null default 'green',
  created_at timestamptz not null default now()
);
create index on public.cards (user_id);
alter table public.cards enable row level security;
create policy "own cards" on public.cards for select to authenticated using (user_id = auth.uid() or public.is_staff());
-- Card number, CVV and PIN hash are never selectable; reveal goes through card_reveal().
revoke select on public.cards from anon, authenticated;
grant select (id, user_id, label, brand, currency, last4, expiry_month, expiry_year, balance, status,
              daily_limit, online_enabled, international_enabled, color, created_at) on public.cards to authenticated;

create or replace function public._luhn_pan(_prefix text)
returns text language plpgsql as $$
declare body text := _prefix; s int := 0; d int; i int; dbl boolean := true;
begin
  while length(body) < 15 loop body := body || floor(random() * 10)::int::text; end loop;
  for i in reverse length(body)..1 loop
    d := substr(body, i, 1)::int;
    if dbl then d := d * 2; if d > 9 then d := d - 9; end if; end if;
    s := s + d; dbl := not dbl;
  end loop;
  return body || ((10 - s % 10) % 10)::text;
end $$;

create or replace function public.card_create(_currency text, _label text default null, _color text default 'green')
returns uuid language plpgsql security definer set search_path = public as $$
declare _brand text; _pan text; _id uuid; _lvl int;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  select kyc_level into _lvl from profiles where id = auth.uid();
  if _lvl < 1 then raise exception 'Verify your BVN to get a card'; end if;
  if (select count(*) from cards where user_id = auth.uid() and status <> 'terminated') >= 5 then
    raise exception 'You can have up to 5 active cards'; end if;
  if _currency = 'NGN' then _brand := 'Verve'; _pan := _luhn_pan('506099');
  elsif _currency = 'USD' then _brand := 'Visa'; _pan := _luhn_pan('4' || lpad(floor(random()*100000)::text, 5, '0'));
  else raise exception 'Choose NGN or USD'; end if;
  insert into cards (user_id, label, brand, currency, pan, cvv, last4, expiry_month, expiry_year,
                     daily_limit, international_enabled, color)
  values (auth.uid(), coalesce(nullif(trim(_label), ''), _currency || ' Virtual Card'), _brand, _currency, _pan,
          lpad(floor(random() * 1000)::text, 3, '0'), right(_pan, 4),
          extract(month from now())::int, extract(year from now())::int + 3,
          case when _currency = 'USD' then 1000 else 200000 end, _currency = 'USD', coalesce(_color, 'green'))
  returning id into _id;
  insert into notifications (user_id, title, body, category)
  values (auth.uid(), 'Card created', 'Your ' || _currency || ' virtual card is ready to use.', 'card');
  return _id;
end $$;
revoke all on function public.card_create(text, text, text) from public, anon;
grant execute on function public.card_create(text, text, text) to authenticated;

create or replace function public.card_reveal(_card uuid, _pin text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c record;
begin
  perform _require_pin(_pin);
  select * into c from cards where id = _card and user_id = auth.uid() and status <> 'terminated';
  if c is null then raise exception 'Card not found'; end if;
  insert into audit_logs (actor_id, action, entity, entity_id) values (auth.uid(), 'card_reveal', 'card', _card::text);
  return jsonb_build_object('pan', c.pan, 'cvv', c.cvv,
    'expiry', lpad(c.expiry_month::text, 2, '0') || '/' || right(c.expiry_year::text, 2));
end $$;
revoke all on function public.card_reveal(uuid, text) from public, anon;
grant execute on function public.card_reveal(uuid, text) to authenticated;

create or replace function public.card_update(
  _card uuid, _status text default null, _daily_limit numeric default null,
  _online boolean default null, _international boolean default null, _label text default null
) returns void language plpgsql security definer set search_path = public as $$
begin
  if _status is not null and _status not in ('active', 'frozen') then raise exception 'Invalid status'; end if;
  if _daily_limit is not null and _daily_limit <= 0 then raise exception 'Invalid limit'; end if;
  update cards set status = coalesce(_status, status), daily_limit = coalesce(_daily_limit, daily_limit),
    online_enabled = coalesce(_online, online_enabled),
    international_enabled = coalesce(_international, international_enabled),
    label = coalesce(nullif(trim(_label), ''), label)
   where id = _card and user_id = auth.uid() and status <> 'terminated';
  if not found then raise exception 'Card not found'; end if;
end $$;
revoke all on function public.card_update(uuid, text, numeric, boolean, boolean, text) from public, anon;
grant execute on function public.card_update(uuid, text, numeric, boolean, boolean, text) to authenticated;

create or replace function public.card_set_pin(_card uuid, _card_pin text, _pin text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  perform _require_pin(_pin);
  if _card_pin !~ '^[0-9]{4}$' then raise exception 'Card PIN must be 4 digits'; end if;
  update cards set pin_hash = crypt(_card_pin, gen_salt('bf')) where id = _card and user_id = auth.uid();
  if not found then raise exception 'Card not found'; end if;
end $$;
revoke all on function public.card_set_pin(uuid, text, text) from public, anon;
grant execute on function public.card_set_pin(uuid, text, text) to authenticated;

-- Fund a USD card from the Naira wallet (rate = USDT/NGN, 1% fee).
create or replace function public.card_fund(_card uuid, _usd numeric, _pin text, _key text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c record; _rate numeric; _ngn numeric(38,2); _fee numeric(38,2); _journal uuid;
begin
  perform _require_pin(_pin);
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
end $$;
revoke all on function public.card_fund(uuid, numeric, text, text) from public, anon;
grant execute on function public.card_fund(uuid, numeric, text, text) to authenticated;

-- Simulated card purchase (stands in for issuer authorisation webhooks).
create or replace function public.card_simulate_purchase(_card uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
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
end $$;
revoke all on function public.card_simulate_purchase(uuid) from public, anon;
grant execute on function public.card_simulate_purchase(uuid) to authenticated;

create or replace function public.card_terminate(_card uuid, _pin text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c record; _rate numeric; _ngn numeric(38,2) := 0; _journal uuid;
begin
  perform _require_pin(_pin);
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
end $$;
revoke all on function public.card_terminate(uuid, text) from public, anon;
grant execute on function public.card_terminate(uuid, text) to authenticated;

-- =====================================================================
-- BUDGETS & INSIGHTS
-- =====================================================================
create table public.budgets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  category text not null,
  monthly_limit numeric(38,2) not null check (monthly_limit > 0),
  alerted_month text,
  created_at timestamptz not null default now(),
  unique (user_id, category)
);
alter table public.budgets enable row level security;
create policy "manage budgets" on public.budgets for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Monthly NGN spending by category (card USD spend counted at its Naira value).
create or replace function public.spending_summary(_month date default null)
returns table (category text, total numeric, count bigint)
language sql stable security definer set search_path = public as $$
  select t.category,
         sum(case when t.type = 'card_payment' and t.metadata ? 'ngn_equivalent'
                  then (t.metadata->>'ngn_equivalent')::numeric else abs(t.amount) + t.fee end) total,
         count(*)
  from transactions t
  where t.user_id = auth.uid() and t.asset_code = 'NGN' and t.status = 'completed'
    and t.type in ('transfer_out', 'bill_payment', 'card_payment', 'withdrawal', 'card_funding')
    and t.created_at >= date_trunc('month', coalesce(_month, current_date))
    and t.created_at < date_trunc('month', coalesce(_month, current_date)) + interval '1 month'
  group by t.category order by 2 desc
$$;
revoke all on function public.spending_summary(date) from public, anon;
grant execute on function public.spending_summary(date) to authenticated;

create or replace function public.cashflow_summary(_month date default null)
returns table (money_in numeric, money_out numeric, saved numeric)
language sql stable security definer set search_path = public as $$
  select
    coalesce(sum(t.amount) filter (where t.type in ('deposit', 'transfer_in', 'interest', 'reversal')), 0),
    coalesce(sum(abs(t.amount) + t.fee) filter (where t.type in ('transfer_out', 'bill_payment', 'card_payment', 'withdrawal', 'card_funding')), 0),
    coalesce(-sum(t.amount) filter (where t.type in ('savings_deposit', 'savings_withdrawal')), 0)
  from transactions t
  where t.user_id = auth.uid() and t.asset_code = 'NGN' and t.status = 'completed'
    and t.created_at >= date_trunc('month', coalesce(_month, current_date))
    and t.created_at < date_trunc('month', coalesce(_month, current_date)) + interval '1 month'
$$;
revoke all on function public.cashflow_summary(date) from public, anon;
grant execute on function public.cashflow_summary(date) to authenticated;

-- Budget alert at 80% and 100% of a category limit.
create or replace function public.check_budget()
returns trigger language plpgsql security definer set search_path = public as $$
declare b record; _spent numeric; _month text := to_char(now(), 'YYYY-MM');
begin
  if new.category is null or new.asset_code <> 'NGN' or new.amount >= 0 and new.type <> 'card_payment' then return new; end if;
  select * into b from budgets where user_id = new.user_id and category = new.category;
  if b is null then return new; end if;
  select coalesce(sum(case when type = 'card_payment' and metadata ? 'ngn_equivalent'
                            then (metadata->>'ngn_equivalent')::numeric else abs(amount) end), 0) into _spent
    from transactions where user_id = new.user_id and category = new.category and asset_code = 'NGN'
     and amount <= 0 and created_at >= date_trunc('month', now());
  if _spent >= b.monthly_limit * 0.8 and coalesce(b.alerted_month, '') <> _month then
    insert into notifications (user_id, title, body, category)
    values (new.user_id, 'Budget alert: ' || b.category,
            'You have used ' || round(_spent / b.monthly_limit * 100) || '% of your ' || b.category || ' budget this month.', 'budget');
    update budgets set alerted_month = _month where id = b.id;
  end if;
  return new;
end $$;
drop trigger if exists trg_budget_alert on public.transactions;
create trigger trg_budget_alert after insert on public.transactions
  for each row execute function public.check_budget();

alter publication supabase_realtime add table public.savings_plans, public.cards;

-- Nightly savings job (02:00 Lagos = 01:00 UTC) and hourly auto-save check.
create extension if not exists pg_cron;
select cron.schedule('nova-savings', '5 * * * *', $$select public.savings_run_scheduled()$$);
