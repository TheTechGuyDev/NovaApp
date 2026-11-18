-- Funding your own USD card is a transfer, not spending: only its fee counts.
-- Card spend on USD cards uses its Naira equivalent. Both summaries share one rule.
create or replace function public._spend_value(t public.transactions)
returns numeric language sql immutable as $$
  select case
    when t.type = 'card_funding' then t.fee
    when t.type = 'card_payment' and t.metadata ? 'ngn_equivalent' then (t.metadata->>'ngn_equivalent')::numeric
    else abs(t.amount) + t.fee end
$$;

create or replace function public.spending_summary(_month date default null)
returns table (category text, total numeric, count bigint)
language sql stable security definer set search_path = public as $$
  select case when t.type = 'card_funding' then 'Fees & Cards' else t.category end, sum(public._spend_value(t)), count(*)
  from transactions t
  where t.user_id = auth.uid() and t.asset_code = 'NGN' and t.status = 'completed'
    and t.type in ('transfer_out', 'bill_payment', 'card_payment', 'withdrawal', 'card_funding')
    and t.created_at >= date_trunc('month', coalesce(_month, current_date))
    and t.created_at < date_trunc('month', coalesce(_month, current_date)) + interval '1 month'
  group by 1 having sum(public._spend_value(t)) > 0 order by 2 desc
$$;

create or replace function public.cashflow_summary(_month date default null)
returns table (money_in numeric, money_out numeric, saved numeric)
language sql stable security definer set search_path = public as $$
  select
    coalesce(sum(t.amount) filter (where t.type in ('deposit', 'transfer_in', 'interest')), 0),
    coalesce(sum(public._spend_value(t)) filter (where t.type in ('transfer_out', 'bill_payment', 'card_payment', 'withdrawal', 'card_funding')), 0),
    coalesce(-sum(t.amount) filter (where t.type in ('savings_deposit', 'savings_withdrawal')), 0)
  from transactions t
  where t.user_id = auth.uid() and t.asset_code = 'NGN' and t.status = 'completed'
    and t.created_at >= date_trunc('month', coalesce(_month, current_date))
    and t.created_at < date_trunc('month', coalesce(_month, current_date)) + interval '1 month'
$$;
