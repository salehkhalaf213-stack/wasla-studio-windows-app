drop policy if exists platform_admins_read_self on public.platform_admins;
drop policy if exists platform_admins_read_all on public.platform_admins;
create policy platform_admins_read_self_or_all
on public.platform_admins
for select to authenticated
using (
  user_id = (select auth.uid())
  or (select private.is_platform_admin())
);
