-- Keep all client-facing project resources behind the project visibility switch.
drop policy if exists "client milestones read own projects" on public.client_project_milestones;
create policy "client milestones read own visible projects" on public.client_project_milestones
for select to authenticated
using (
  exists (
    select 1 from public.client_projects cp
    join public.client_accounts ca on ca.legacy_client_id = cp.legacy_client_id
    where cp.legacy_project_id = client_project_milestones.legacy_project_id
      and cp.is_visible_to_client is true
      and ca.auth_user_id = (select auth.uid())
  )
  or exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = any(array['admin','owner']))
  or exists (select 1 from public.employee_assignments ea where ea.assigned_to = (select auth.uid()) and ea.project_ref = client_project_milestones.legacy_project_id::text)
);

drop policy if exists "clients and project staff read comments" on public.client_project_comments;
create policy "clients and project staff read comments" on public.client_project_comments
for select to authenticated
using (
  exists (
    select 1 from public.client_projects cp
    join public.client_accounts ca on ca.legacy_client_id = cp.legacy_client_id
    where cp.legacy_project_id = client_project_comments.legacy_project_id
      and cp.is_visible_to_client is true
      and ca.auth_user_id = (select auth.uid())
  )
  or exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = any(array['admin','owner']))
  or exists (select 1 from public.employee_assignments ea where ea.assigned_to = (select auth.uid()) and ea.project_ref = client_project_comments.legacy_project_id::text)
);

drop policy if exists "clients comment on own projects" on public.client_project_comments;
create policy "clients comment on own visible projects" on public.client_project_comments
for insert to authenticated
with check (
  author_id = (select auth.uid())
  and exists (
    select 1 from public.client_projects cp
    join public.client_accounts ca on ca.legacy_client_id = cp.legacy_client_id
    where cp.legacy_project_id = client_project_comments.legacy_project_id
      and cp.is_visible_to_client is true
      and ca.auth_user_id = (select auth.uid())
  )
);

drop policy if exists "clients and project staff read designs" on public.client_project_designs;
create policy "clients and project staff read designs" on public.client_project_designs
for select to authenticated
using (
  (
    visible_to_client is true
    and exists (
      select 1 from public.client_projects cp
      join public.client_accounts ca on ca.legacy_client_id = cp.legacy_client_id
      where cp.legacy_project_id = client_project_designs.legacy_project_id
        and cp.is_visible_to_client is true
        and ca.auth_user_id = (select auth.uid())
    )
  )
  or exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = any(array['admin','owner']))
  or exists (select 1 from public.employee_assignments ea where ea.assigned_to = (select auth.uid()) and ea.project_ref = client_project_designs.legacy_project_id::text)
);

drop policy if exists "clients and staff read design reviews" on public.client_design_reviews;
create policy "clients and staff read design reviews" on public.client_design_reviews
for select to authenticated
using (
  exists (
    select 1 from public.client_project_designs d
    join public.client_projects cp on cp.legacy_project_id = d.legacy_project_id
    join public.client_accounts ca on ca.legacy_client_id = cp.legacy_client_id
    where d.id = client_design_reviews.design_id
      and d.visible_to_client is true
      and cp.is_visible_to_client is true
      and ca.auth_user_id = (select auth.uid())
  )
  or exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = any(array['admin','owner']))
  or exists (
    select 1 from public.client_project_designs d
    join public.employee_assignments ea on ea.project_ref = d.legacy_project_id::text
    where d.id = client_design_reviews.design_id and ea.assigned_to = (select auth.uid())
  )
);

drop policy if exists "clients approve own visible designs" on public.client_design_reviews;
create policy "clients approve own visible designs" on public.client_design_reviews
for insert to authenticated
with check (
  reviewer_id = (select auth.uid())
  and exists (
    select 1 from public.client_project_designs d
    join public.client_projects cp on cp.legacy_project_id = d.legacy_project_id
    join public.client_accounts ca on ca.legacy_client_id = cp.legacy_client_id
    where d.id = client_design_reviews.design_id
      and d.visible_to_client is true
      and cp.is_visible_to_client is true
      and ca.auth_user_id = (select auth.uid())
  )
);

drop policy if exists "client design files read by project client or staff" on storage.objects;
create policy "client design files read by project client or staff" on storage.objects
for select to authenticated
using (
  bucket_id = 'client-designs'
  and (
    exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = any(array['admin','owner']))
    or exists (select 1 from public.employee_assignments ea where ea.assigned_to = (select auth.uid()) and ea.project_ref = (storage.foldername(objects.name))[1])
    or exists (
      select 1 from public.client_project_designs d
      join public.client_projects cp on cp.legacy_project_id = d.legacy_project_id
      join public.client_accounts ca on ca.legacy_client_id = cp.legacy_client_id
      where d.storage_path = objects.name
        and d.visible_to_client is true
        and cp.is_visible_to_client is true
        and ca.auth_user_id = (select auth.uid())
    )
  )
);
