-- =====================================================================
-- Phase 7: Exchange (instant swaps with 30s quotes + limit orders)
-- NOVA acts as the liquidity provider in the sandbox: the `liquidity`
-- system account takes the other side of every trade.
-- =====================================================================

create extension if not exists pg_net;

create table if not exists public.price_history_cache (
  key text primary key,
  points jsonb not null,
  fetched_at timestamptz not null default now()
);
alter table public.price_history_cache enable row level security;

alter table public.quotes add column if not exists fee_pct numeric(6,4);
alter table public.quotes add column if not exists from_ngn_price numeric(38,18);
alter table public.quotes add column if not exists to_ngn_price numeric(38,18);

-- Funds reserved by open limit orders sit in escrow (wallet -> order_escrow).
alter table public.orders add column if not exists locked_asset text references public.assets(code);
alter table public.orders add column if not exists locked_amount numeric(38,18) not null default 0;
alter table public.orders add column if not exists filled_at timestamptz;

create or replace function public._asset_round(_asset text, _v numeric)
returns numeric language sql stable set search_path = public as $$
  select round(_v, least((select decimals from assets where code = _asset), 8))
$$;

create or replace function public._trade_fee_pct(_a text, _b text)
returns numeric language sql stable set search_path = public as $$
  select coalesce(
    (select fee_pct from trading_pairs where enabled and
       ((base_asset = _a and quote_asset = _b) or (base_asset = _b and quote_asset = _a)) limit 1),
    0.75)
$$;

create or replace function public._kyc_trade_cap(_user uuid)
returns numeric language sql stable security definer set search_path = public as $$
  select case kyc_level when 1 then 200000 when 2 then 5000000 when 3 then 50000000 else 0 end
  from profiles where id = _user
$$;
revoke all on function public._kyc_trade_cap(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------- quotes
create or replace function public.exchange_quote(_from text, _to text, _amount_in numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare rf record; rt record; _fee_pct numeric; _gross numeric; _fee numeric; _out numeric;
        _ngn_value numeric; _q record; _cap numeric;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
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
revoke all on function public.exchange_quote(text, text, numeric) from public, anon;
grant execute on function public.exchange_quote(text, text, numeric) to authenticated;

create or replace function public.exchange_execute(_quote uuid, _pin text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare q record; wf uuid; wt uuid; _journal uuid; _ref text;
begin
  perform _require_pin(_pin);
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
end $$;
revoke all on function public.exchange_execute(uuid, text) from public, anon;
grant execute on function public.exchange_execute(uuid, text) to authenticated;

-- ---------------------------------------------------------- limit orders
-- price is in quote currency per 1 base (e.g. BTC_NGN: Naira per BTC).
create or replace function public.exchange_place_limit(_pair text, _side public.order_side, _price numeric,
                                                       _amount numeric, _pin text)
returns uuid language plpgsql security definer set search_path = public as $$
declare p record; _lock_asset text; _lock numeric; _wallet uuid; _id uuid; _ngn numeric; _mkt numeric;
begin
  perform _require_pin(_pin);
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
revoke all on function public.exchange_place_limit(text, public.order_side, numeric, numeric, text) from public, anon;
grant execute on function public.exchange_place_limit(text, public.order_side, numeric, numeric, text) to authenticated;

create or replace function public.exchange_cancel(_order uuid)
returns void language plpgsql security definer set search_path = public as $$
declare o record; _wallet uuid;
begin
  select * into o from orders where id = _order and user_id = auth.uid() for update;
  if o is null then raise exception 'Order not found'; end if;
  if o.status not in ('open', 'partially_filled') then raise exception 'Order is already %', o.status; end if;
  select id into _wallet from wallets where user_id = o.user_id and asset_code = o.locked_asset;
  perform post_journal('ordc:' || o.id, 'Limit order cancelled', jsonb_build_array(
    jsonb_build_object('system', 'order_escrow', 'asset', o.locked_asset, 'amount', -o.locked_amount),
    jsonb_build_object('wallet_id', _wallet, 'asset', o.locked_asset, 'amount', o.locked_amount)));
  update wallets set locked = greatest(locked - o.locked_amount, 0) where id = _wallet;
  update orders set status = 'cancelled', locked_amount = 0 where id = o.id;
end $$;
revoke all on function public.exchange_cancel(uuid) from public, anon;
grant execute on function public.exchange_cancel(uuid) to authenticated;

-- Called after every price refresh: fills limit orders the market has reached.
create or replace function public.exchange_match_limits()
returns int language plpgsql security definer set search_path = public as $$
declare o record; p record; _mkt numeric; _base_w uuid; _quote_w uuid; _fee_pct numeric;
        _recv numeric; _fee numeric; _journal uuid; _n int := 0; _cost numeric;
begin
  for o in select * from orders where status = 'open' and type = 'limit' order by created_at for update skip locked loop
    select * into p from trading_pairs where symbol = o.pair;
    _mkt := (select ngn_price from rates where asset_code = p.base_asset) / (select ngn_price from rates where asset_code = p.quote_asset);
    if not ((o.side = 'buy' and _mkt <= o.price) or (o.side = 'sell' and _mkt >= o.price)) then continue; end if;

    _fee_pct := p.fee_pct;
    select id into _base_w from wallets where user_id = o.user_id and asset_code = p.base_asset;
    select id into _quote_w from wallets where user_id = o.user_id and asset_code = p.quote_asset;

    if o.side = 'buy' then
      _cost := o.locked_amount;                                   -- quote spent at limit price
      _fee := _asset_round(p.base_asset, o.amount * _fee_pct / 100);
      _recv := o.amount - _fee;
      _journal := post_journal('fill:' || o.id, 'Limit buy filled ' || o.pair, jsonb_build_array(
        jsonb_build_object('system', 'order_escrow', 'asset', p.quote_asset, 'amount', -_cost),
        jsonb_build_object('system', 'liquidity', 'asset', p.quote_asset, 'amount', _cost),
        jsonb_build_object('wallet_id', _base_w, 'asset', p.base_asset, 'amount', _recv),
        jsonb_build_object('system', 'fees', 'asset', p.base_asset, 'amount', _fee),
        jsonb_build_object('system', 'liquidity', 'asset', p.base_asset, 'amount', -o.amount)));
      update wallets set locked = greatest(locked - _cost, 0) where id = _quote_w;
      insert into transactions (user_id, journal_id, type, status, asset_code, amount, title, metadata) values
        (o.user_id, _journal, 'trade', 'completed', p.quote_asset, -_cost, 'Limit buy ' || p.base_asset,
         jsonb_build_object('order_id', o.id, 'leg', 'out', 'price', o.price)),
        (o.user_id, _journal, 'trade', 'completed', p.base_asset, _recv, 'Bought ' || p.base_asset || ' (limit)',
         jsonb_build_object('order_id', o.id, 'leg', 'in', 'price', o.price, 'fee', _fee));
    else
      _cost := o.locked_amount;                                   -- base sold
      _recv := _asset_round(p.quote_asset, o.amount * o.price);
      _fee := _asset_round(p.quote_asset, _recv * _fee_pct / 100);
      _journal := post_journal('fill:' || o.id, 'Limit sell filled ' || o.pair, jsonb_build_array(
        jsonb_build_object('system', 'order_escrow', 'asset', p.base_asset, 'amount', -_cost),
        jsonb_build_object('system', 'liquidity', 'asset', p.base_asset, 'amount', _cost),
        jsonb_build_object('wallet_id', _quote_w, 'asset', p.quote_asset, 'amount', _recv - _fee),
        jsonb_build_object('system', 'fees', 'asset', p.quote_asset, 'amount', _fee),
        jsonb_build_object('system', 'liquidity', 'asset', p.quote_asset, 'amount', -_recv)));
      update wallets set locked = greatest(locked - _cost, 0) where id = _base_w;
      insert into transactions (user_id, journal_id, type, status, asset_code, amount, title, metadata) values
        (o.user_id, _journal, 'trade', 'completed', p.base_asset, -_cost, 'Limit sell ' || p.base_asset,
         jsonb_build_object('order_id', o.id, 'leg', 'out', 'price', o.price)),
        (o.user_id, _journal, 'trade', 'completed', p.quote_asset, _recv - _fee, 'Sold ' || p.base_asset || ' (limit)',
         jsonb_build_object('order_id', o.id, 'leg', 'in', 'price', o.price, 'fee', _fee));
    end if;

    update orders set status = 'filled', filled = amount, avg_price = o.price, fee = _fee,
                      locked_amount = 0, filled_at = now() where id = o.id;
    insert into trades (pair, taker_order_id, price, amount, taker_side) values (o.pair, o.id, o.price, o.amount, o.side);
    insert into notifications (user_id, title, body, category)
    values (o.user_id, 'Limit order filled',
            initcap(o.side::text) || ' ' || o.amount || ' ' || p.base_asset || ' at ' || o.price || ' ' || p.quote_asset, 'trade');
    _n := _n + 1;
  end loop;
  return _n;
end $$;
revoke all on function public.exchange_match_limits() from public, anon, authenticated;
grant execute on function public.exchange_match_limits() to service_role;

-- Aggregated open-order depth for a pair (no user data exposed).
create or replace function public.exchange_depth(_pair text)
returns table (side public.order_side, price numeric, amount numeric, orders bigint)
language sql stable security definer set search_path = public as $$
  select side, price, sum(amount - filled), count(*) from orders
  where pair = _pair and status in ('open', 'partially_filled')
  group by side, price order by side, price desc limit 40
$$;
revoke all on function public.exchange_depth(text) from public, anon;
grant execute on function public.exchange_depth(text) to authenticated;

-- 24h volume per pair from fills and swaps.
create or replace function public.exchange_stats()
returns table (pair text, volume_24h numeric, trades_24h bigint)
language sql stable security definer set search_path = public as $$
  select t.pair, sum(t.amount), count(*) from trades t where t.created_at > now() - interval '24 hours' group by t.pair
$$;
revoke all on function public.exchange_stats() from public, anon;
grant execute on function public.exchange_stats() to authenticated;

alter publication supabase_realtime add table public.orders;
