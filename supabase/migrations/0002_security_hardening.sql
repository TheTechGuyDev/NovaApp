-- Security advisor fixes
alter function public.set_updated_at() set search_path = public;
revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.has_role(public.app_role) from public, anon;
revoke all on function public.is_staff() from public, anon;
grant execute on function public.has_role(public.app_role) to authenticated;
grant execute on function public.is_staff() to authenticated;
