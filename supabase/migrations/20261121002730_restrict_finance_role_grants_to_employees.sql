-- Restrict financial role grants to active employee members only.
-- Preserve existing accounts and assignments; this migration changes authorization only.

drop policy if exists finance_member_roles_tenant_scope on public.finance_member_roles;
drop policy if exists finance_project_access_tenant_scope on public.finance_project_access;

create or replace function private.finance_validate_member_role_target()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member_role text;
  v_member_status text;
begin
  if (select auth.uid()) is null
     or not private.has_organization_role(array['owner','admin']) then
    raise exception 'Only an organization owner or manager may assign financial roles.';
  end if;

  select member.role, member.status
    into v_member_role, v_member_status
  from public.organization_members member
  where member.organization_id = new.organization_id
    and member.user_id = new.user_id;

  if not found
     or v_member_role <> 'employee'
     or v_member_status <> 'active' then
    raise exception 'Financial roles can only be assigned to active employee members of this organization.';
  end if;

  return new;
end;
$$;

drop trigger if exists finance_member_roles_target_guard on public.finance_member_roles;
create trigger finance_member_roles_target_guard
before insert or update on public.finance_member_roles
for each row execute function private.finance_validate_member_role_target();

create or replace function private.finance_validate_project_access_target()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member_role text;
  v_member_status text;
begin
  if (select auth.uid()) is null
     or not private.has_organization_role(array['owner','admin']) then
    raise exception 'Only an organization owner or manager may grant project finance access.';
  end if;

  select member.role, member.status
    into v_member_role, v_member_status
  from public.organization_members member
  where member.organization_id = new.organization_id
    and member.user_id = new.user_id;

  if not found
     or v_member_role <> 'employee'
     or v_member_status <> 'active' then
    raise exception 'Project finance access can only be granted to active employee members of this organization.';
  end if;

  if not exists (
    select 1
    from public.finance_member_roles role_grant
    where role_grant.organization_id = new.organization_id
      and role_grant.user_id = new.user_id
      and role_grant.finance_role in ('project_manager','finance_viewer')
  ) then
    raise exception 'The employee must first have the project manager or finance viewer role.';
  end if;

  return new;
end;
$$;

drop trigger if exists finance_project_access_target_guard on public.finance_project_access;
create trigger finance_project_access_target_guard
before insert or update on public.finance_project_access
for each row execute function private.finance_validate_project_access_target();

revoke all on function private.finance_validate_member_role_target() from public, anon, authenticated;
revoke all on function private.finance_validate_project_access_target() from public, anon, authenticated;
