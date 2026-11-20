-- Client projects are hidden from portal users until an organization owner/admin enables visibility.
alter table public.client_projects
  add column if not exists is_visible_to_client boolean not null default false;

drop policy if exists "Clients read only their mapped projects" on public.client_projects;

create policy "Clients read only their visible mapped projects"
on public.client_projects
for select
to authenticated
using (
  is_visible_to_client is true
  and exists (
    select 1
    from public.client_accounts ca
    where ca.auth_user_id = (select auth.uid())
      and ca.legacy_client_id = client_projects.legacy_client_id
  )
);
