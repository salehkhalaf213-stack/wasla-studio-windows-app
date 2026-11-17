-- Platform-level ownership is separate from tenant-level owner/admin roles.
create table if not exists public.platform_admins (
  user_id uuid primary key references auth.users(id) on delete restrict,
  status text not null default 'active' check (status in ('active','suspended')),
  created_at timestamptz not null default now()
);

alter table public.platform_admins enable row level security;
revoke all on public.platform_admins from anon, authenticated;
grant select on public.platform_admins to authenticated;

drop policy if exists platform_admins_read_self on public.platform_admins;
create policy platform_admins_read_self
on public.platform_admins
for select to authenticated
using (user_id = (select auth.uid()));

create or replace function private.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.platform_admins pa
    where pa.user_id = (select auth.uid())
      and pa.status = 'active'
  );
$$;

revoke all on function private.is_platform_admin() from public, anon;
grant usage on schema private to authenticated;
grant execute on function private.is_platform_admin() to authenticated;

drop policy if exists platform_admins_read_all on public.platform_admins;
create policy platform_admins_read_all
on public.platform_admins
for select to authenticated
using ((select private.is_platform_admin()));

drop policy if exists platform_admin_read_all_organizations on public.organizations;
create policy platform_admin_read_all_organizations
on public.organizations
for select to authenticated
using ((select private.is_platform_admin()));

drop policy if exists platform_admin_read_all_memberships on public.organization_members;
create policy platform_admin_read_all_memberships
on public.organization_members
for select to authenticated
using ((select private.is_platform_admin()));

drop policy if exists platform_admin_read_all_profiles on public.profiles;
create policy platform_admin_read_all_profiles
on public.profiles
for select to authenticated
using ((select private.is_platform_admin()));

drop policy if exists platform_admin_read_all_subscriptions on public.organization_subscriptions;
create policy platform_admin_read_all_subscriptions
on public.organization_subscriptions
for select to authenticated
using ((select private.is_platform_admin()));

-- Promote the existing, verified WASLA STUDIO owner account to platform owner.
insert into public.platform_admins (user_id)
values ('3faa9e5a-ca45-47ca-8c02-a03e399ca60a'::uuid)
on conflict (user_id) do update set status = 'active';
