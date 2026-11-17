-- Platform admins may inspect tenant membership/profile records across organizations.
-- Writes remain tenant-scoped because WITH CHECK still requires current_organization_id().
drop policy if exists tenant_scope_restrict on public.organization_members;
create policy tenant_scope_restrict
on public.organization_members
as restrictive
for all to authenticated
using (
  organization_id = (select private.current_organization_id())
  or (select private.is_platform_admin())
)
with check (
  organization_id = (select private.current_organization_id())
);

drop policy if exists tenant_scope_restrict on public.profiles;
create policy tenant_scope_restrict
on public.profiles
as restrictive
for all to authenticated
using (
  organization_id = (select private.current_organization_id())
  or (select private.is_platform_admin())
)
with check (
  organization_id = (select private.current_organization_id())
);
