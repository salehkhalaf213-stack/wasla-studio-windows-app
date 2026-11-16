-- Tenant isolation hardening: workspace partitioning, row ownership, storage gates and role enforcement.
-- Requires 20261116000000_saas_multitenant_foundation.sql.

do $$
declare t text;
begin
  foreach t in array array[
    'profiles','client_accounts','client_projects','client_project_milestones',
    'client_project_designs','client_project_comments','client_design_reviews',
    'employee_assignments','employee_updates','notifications','workspace_data',
    'organization_members'
  ] loop
    execute format('drop policy if exists tenant_scope_restrict on public.%I',t);
    execute format('create policy tenant_scope_restrict on public.%I as restrictive for all to authenticated using (organization_id = (select private.current_organization_id())) with check (organization_id = (select private.current_organization_id()))',t);
  end loop;
end $$;

alter table public.workspace_data drop constraint if exists workspace_data_pkey;
alter table public.workspace_data add constraint workspace_data_pkey primary key (organization_id,id);
alter table public.workspace_data alter column organization_id set not null;

create or replace function private.is_admin()
returns boolean language sql stable security definer set search_path=''
as $$ select private.has_organization_role(array['owner','admin']); $$;

create or replace function private.enforce_row_organization()
returns trigger language plpgsql security definer set search_path=''
as $$
declare org_id uuid; parent_org uuid;
begin
  if (select auth.uid()) is null then return new; end if;
  org_id := (select private.current_organization_id());
  if org_id is null then raise exception 'لا توجد عضوية مؤسسة نشطة'; end if;
  if tg_op='INSERT' then new.organization_id:=org_id;
  else
    if old.organization_id is distinct from org_id or new.organization_id is distinct from old.organization_id then
      raise exception 'لا يمكن نقل السجل بين المؤسسات';
    end if;
  end if;
  if tg_table_name in ('client_project_milestones','client_project_comments','client_project_designs') then
    select cp.organization_id into parent_org from public.client_projects cp where cp.legacy_project_id=new.legacy_project_id;
    if parent_org is distinct from org_id then raise exception 'المشروع غير تابع للمؤسسة الحالية'; end if;
  elsif tg_table_name='client_design_reviews' then
    select d.organization_id into parent_org from public.client_project_designs d where d.id=new.design_id;
    if parent_org is distinct from org_id then raise exception 'التصميم غير تابع للمؤسسة الحالية'; end if;
  elsif tg_table_name='employee_updates' then
    select a.organization_id into parent_org from public.employee_assignments a where a.id=new.assignment_id;
    if parent_org is distinct from org_id then raise exception 'التكليف غير تابع للمؤسسة الحالية'; end if;
    if new.employee_id<>(select auth.uid()) and not private.has_organization_role(array['owner','admin']) then
      raise exception 'لا يمكن إضافة تحديث نيابة عن موظف آخر';
    end if;
  elsif tg_table_name='employee_assignments' then
    if not exists(select 1 from public.organization_members om where om.user_id=new.assigned_to and om.organization_id=org_id and om.status='active' and om.role='employee') then
      raise exception 'الموظف المكلف ليس عضواً نشطاً في المؤسسة';
    end if;
  elsif tg_table_name='client_projects' then
    if not exists(select 1 from public.client_accounts ca where ca.legacy_client_id=new.legacy_client_id and ca.organization_id=org_id) then
      raise exception 'العميل غير تابع للمؤسسة الحالية';
    end if;
  end if;
  return new;
end;
$$;

do $$
declare t text;
begin
  foreach t in array array[
    'client_accounts','client_projects','client_project_milestones','client_project_designs',
    'client_project_comments','client_design_reviews','employee_assignments','employee_updates',
    'notifications','workspace_data'
  ] loop
    execute format('drop trigger if exists trg_enforce_row_organization on public.%I',t);
    execute format('create trigger trg_enforce_row_organization before insert or update on public.%I for each row execute function private.enforce_row_organization()',t);
  end loop;
end $$;

create or replace function private.guard_profile_tenant_fields()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  if (new.role is distinct from old.role
      or new.requested_role is distinct from old.requested_role
      or new.approval_status is distinct from old.approval_status
      or new.organization_id is distinct from old.organization_id)
     and (select auth.uid()) is not null
     and not private.has_organization_role(array['owner','admin']) then
    raise exception 'غير مصرح بتغيير صلاحيات الحساب أو المؤسسة';
  end if;
  return new;
end;
$$;
drop trigger if exists trg_guard_profile_tenant_fields on public.profiles;
create trigger trg_guard_profile_tenant_fields before update on public.profiles
for each row execute function private.guard_profile_tenant_fields();

create or replace function public.guard_employee_assignment_updates()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  if private.has_organization_role(array['owner','admin']) then return new; end if;
  if not exists(select 1 from public.organization_members om where om.user_id=(select auth.uid())
      and om.organization_id=old.organization_id and om.role='employee' and om.status='active')
     or old.assigned_to<>(select auth.uid()) then
    raise exception 'غير مصرح بتعديل التكليف';
  end if;
  if new.id is distinct from old.id or new.project_ref is distinct from old.project_ref
     or new.project_name is distinct from old.project_name or new.client_label is distinct from old.client_label
     or new.due_date is distinct from old.due_date or new.instructions is distinct from old.instructions
     or new.assigned_to is distinct from old.assigned_to or new.assigned_by is distinct from old.assigned_by
     or new.organization_id is distinct from old.organization_id or new.created_at is distinct from old.created_at then
    raise exception 'يمكن للموظف تعديل حالة التكليف فقط';
  end if;
  if new.employee_status not in ('لم يبدأ','قيد التنفيذ','مكتمل') then raise exception 'حالة التكليف غير صالحة'; end if;
  return new;
end;
$$;

create or replace function private.guard_workspace_tenant()
returns trigger language plpgsql security invoker set search_path=''
as $$
begin
  if new.organization_id is distinct from old.organization_id then raise exception 'لا يمكن نقل مساحة العمل بين المؤسسات'; end if;
  if new.id<>1 then raise exception 'معرّف مساحة العمل غير صالح'; end if;
  return new;
end;
$$;
drop trigger if exists trg_guard_workspace_tenant on public.workspace_data;
create trigger trg_guard_workspace_tenant before update on public.workspace_data
for each row execute function private.guard_workspace_tenant();

drop policy if exists tenant_storage_select on storage.objects;
create policy tenant_storage_select on storage.objects as restrictive for select to authenticated
using (
  bucket_id<>'client-designs' or exists(
    select 1 from public.client_projects cp
    where cp.legacy_project_id::text=(storage.foldername(objects.name))[1]
      and cp.organization_id=(select private.current_organization_id())
      and (
        private.has_organization_role(array['owner','admin'])
        or exists(select 1 from public.organization_members om join public.employee_assignments ea on ea.organization_id=om.organization_id
          where om.user_id=(select auth.uid()) and om.organization_id=cp.organization_id and om.role='employee' and om.status='active'
            and ea.assigned_to=(select auth.uid()) and ea.project_ref=cp.legacy_project_id::text)
        or exists(select 1 from public.client_accounts ca join public.client_project_designs d on d.legacy_project_id=cp.legacy_project_id
          where ca.auth_user_id=(select auth.uid()) and ca.organization_id=cp.organization_id and ca.legacy_client_id=cp.legacy_client_id
            and d.organization_id=cp.organization_id and d.storage_path=objects.name and d.visible_to_client=true)
      )
  )
);

drop policy if exists tenant_storage_insert on storage.objects;
create policy tenant_storage_insert on storage.objects as restrictive for insert to authenticated
with check (
  bucket_id<>'client-designs' or ((storage.foldername(name))[1] is not null and exists(
    select 1 from public.client_projects cp
    where cp.legacy_project_id::text=(storage.foldername(name))[1]
      and cp.organization_id=(select private.current_organization_id())
      and (private.has_organization_role(array['owner','admin']) or exists(
        select 1 from public.organization_members om join public.employee_assignments ea on ea.organization_id=om.organization_id
        where om.user_id=(select auth.uid()) and om.organization_id=cp.organization_id and om.role='employee' and om.status='active'
          and ea.assigned_to=(select auth.uid()) and ea.project_ref=cp.legacy_project_id::text))
  ))
);

drop policy if exists tenant_storage_update on storage.objects;
create policy tenant_storage_update on storage.objects as restrictive for update to authenticated
using (bucket_id<>'client-designs' or exists(select 1 from public.client_projects cp
  where cp.legacy_project_id::text=(storage.foldername(name))[1] and cp.organization_id=(select private.current_organization_id())
    and (private.has_organization_role(array['owner','admin']) or exists(select 1 from public.employee_assignments ea
      where ea.organization_id=cp.organization_id and ea.assigned_to=(select auth.uid()) and ea.project_ref=cp.legacy_project_id::text))))
with check (bucket_id<>'client-designs' or exists(select 1 from public.client_projects cp
  where cp.legacy_project_id::text=(storage.foldername(name))[1] and cp.organization_id=(select private.current_organization_id())
    and (private.has_organization_role(array['owner','admin']) or exists(select 1 from public.employee_assignments ea
      where ea.organization_id=cp.organization_id and ea.assigned_to=(select auth.uid()) and ea.project_ref=cp.legacy_project_id::text))));

drop policy if exists tenant_storage_delete on storage.objects;
create policy tenant_storage_delete on storage.objects as restrictive for delete to authenticated
using (bucket_id<>'client-designs' or exists(select 1 from public.client_projects cp
  where cp.legacy_project_id::text=(storage.foldername(name))[1] and cp.organization_id=(select private.current_organization_id())
    and (private.has_organization_role(array['owner','admin']) or exists(select 1 from public.employee_assignments ea
      where ea.organization_id=cp.organization_id and ea.assigned_to=(select auth.uid()) and ea.project_ref=cp.legacy_project_id::text))));

drop policy if exists "Employees read assigned projects" on public.client_projects;
create policy "Employees read assigned projects" on public.client_projects for select to authenticated
using (exists(select 1 from public.employee_assignments ea where ea.organization_id=client_projects.organization_id
  and ea.assigned_to=(select auth.uid()) and ea.project_ref=client_projects.legacy_project_id::text));

-- Tenant owners/admins receive organization-scoped management access.
drop policy if exists "Tenant owners manage client accounts" on public.client_accounts;
create policy "Tenant owners manage client accounts" on public.client_accounts for all to authenticated
using (private.has_organization_role(array['owner','admin'])) with check (private.has_organization_role(array['owner','admin']));
drop policy if exists "Tenant owners manage client projects" on public.client_projects;
create policy "Tenant owners manage client projects" on public.client_projects for all to authenticated
using (private.has_organization_role(array['owner','admin'])) with check (private.has_organization_role(array['owner','admin']));
drop policy if exists "Tenant owners manage milestones" on public.client_project_milestones;
create policy "Tenant owners manage milestones" on public.client_project_milestones for all to authenticated
using (private.has_organization_role(array['owner','admin'])) with check (private.has_organization_role(array['owner','admin']));
drop policy if exists "Tenant owners manage designs" on public.client_project_designs;
create policy "Tenant owners manage designs" on public.client_project_designs for all to authenticated
using (private.has_organization_role(array['owner','admin'])) with check (private.has_organization_role(array['owner','admin']));
drop policy if exists "Tenant owners read reviews" on public.client_design_reviews;
create policy "Tenant owners read reviews" on public.client_design_reviews for select to authenticated
using (private.has_organization_role(array['owner','admin']));
drop policy if exists "Tenant owners read comments" on public.client_project_comments;
create policy "Tenant owners read comments" on public.client_project_comments for select to authenticated
using (private.has_organization_role(array['owner','admin']));
drop policy if exists "Tenant owners add comments" on public.client_project_comments;
create policy "Tenant owners add comments" on public.client_project_comments for insert to authenticated
with check (private.has_organization_role(array['owner','admin']));
drop policy if exists "Tenant owners manage assignments" on public.employee_assignments;
create policy "Tenant owners manage assignments" on public.employee_assignments for all to authenticated
using (private.has_organization_role(array['owner','admin'])) with check (private.has_organization_role(array['owner','admin']));
drop policy if exists "Tenant owners read employee updates" on public.employee_updates;
create policy "Tenant owners read employee updates" on public.employee_updates for select to authenticated
using (private.has_organization_role(array['owner','admin']));
drop policy if exists "Tenant owners add employee updates" on public.employee_updates;
create policy "Tenant owners add employee updates" on public.employee_updates for insert to authenticated
with check (private.has_organization_role(array['owner','admin']));
drop policy if exists "Tenant owners manage workspace" on public.workspace_data;
create policy "Tenant owners manage workspace" on public.workspace_data for all to authenticated
using (private.has_organization_role(array['owner','admin'])) with check (private.has_organization_role(array['owner','admin']));
