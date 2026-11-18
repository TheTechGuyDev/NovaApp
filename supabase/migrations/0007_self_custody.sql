-- Phase 6: PIN check for on-device actions (reveal phrase, sign transactions).
-- Locks after 5 wrong attempts in 15 minutes.
create or replace function public.check_my_pin(_pin text)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
declare _hash text; _fails int; _ok boolean;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  select count(*) into _fails from audit_logs
    where actor_id = auth.uid() and action = 'pin_failed' and created_at > now() - interval '15 minutes';
  if _fails >= 5 then raise exception 'Too many wrong PIN attempts. Try again in 15 minutes.'; end if;
  select transaction_pin_hash into _hash from profiles where id = auth.uid();
  _ok := _hash is not null and crypt(_pin, _hash) = _hash;
  if not _ok then
    insert into audit_logs (actor_id, action, entity, entity_id) values (auth.uid(), 'pin_failed', 'profile', auth.uid()::text);
  end if;
  return _ok;
end $$;
revoke all on function public.check_my_pin(text) from public, anon;
grant execute on function public.check_my_pin(text) to authenticated;

-- Public addresses of self-custody / connected wallets carry a network label.
alter table public.external_wallets add column if not exists wallet_group text;
