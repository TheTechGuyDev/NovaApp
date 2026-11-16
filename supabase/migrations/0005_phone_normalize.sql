-- Normalise Nigerian phone numbers to +234 and expose an availability check.
create or replace function public.normalize_ng_phone(_p text)
returns text language sql immutable set search_path = public as $$
  select case
    when _p is null or btrim(_p) = '' then null
    when regexp_replace(_p, '\s', '', 'g') ~ '^0[789][01]\d{8}$'
      then '+234' || substr(regexp_replace(_p, '\s', '', 'g'), 2)
    when regexp_replace(_p, '\s', '', 'g') ~ '^234[789][01]\d{8}$'
      then '+' || regexp_replace(_p, '\s', '', 'g')
    else regexp_replace(_p, '\s', '', 'g')
  end
$$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, phone, full_name)
  values (
    new.id,
    new.email,
    public.normalize_ng_phone(coalesce(new.phone, new.raw_user_meta_data->>'phone')),
    new.raw_user_meta_data->>'full_name'
  );
  insert into public.user_roles (user_id, role) values (new.id, 'user');
  insert into public.wallets (user_id, asset_code)
    select new.id, code from public.assets where enabled;
  return new;
end $$;
revoke all on function public.handle_new_user() from public, anon, authenticated;

create or replace function public.phone_available(_phone text)
returns boolean language sql stable security definer set search_path = public as $$
  select not exists (select 1 from profiles where phone = public.normalize_ng_phone(_phone))
$$;
revoke all on function public.phone_available(text) from public;
grant execute on function public.phone_available(text) to anon, authenticated;

update public.profiles set phone = public.normalize_ng_phone(phone) where phone is not null;
