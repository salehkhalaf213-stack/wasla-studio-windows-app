-- WASLA STUDIO SaaS foundation (applied to Supabase project oqkmesadspiibllyjwmj)
-- Existing single-company records are retained under one legacy organization.
begin;
create table if not exists public.organizations (
 id uuid primary key default gen_random_uuid(), name text not null, slug text not null unique,
 status text not null default 'active' check(status in ('active','suspended','closed')),
 created_at timestamptz not null default now(), created_by uuid references auth.users(id) on delete set null
);
create table if not exists public.organization_members (
 organization_id uuid not null references public.organizations(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 role text not null check(role in ('owner','admin','employee','client')),
 status text not null default 'active' check(status in ('invited','active','suspended')),
 created_at timestamptz not null default now(), primary key(organization_id,user_id)
);
create table if not exists public.subscription_plans (
 id text primary key, name text not null, billing_interval text not null check(billing_interval in ('monthly','yearly')),
 price_minor bigint not null check(price_minor>=0), currency text not null default 'USD',
 employee_limit integer, client_limit integer, project_limit integer, is_active boolean not null default true
);
create table if not exists public.organization_subscriptions (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 plan_id text references public.subscription_plans(id),
 status text not null default 'pending' check(status in ('pending','trialing','active','past_due','cancelled','expired')),
 billing_provider text, provider_customer_id text, provider_subscription_id text unique,
 current_period_start timestamptz, current_period_end timestamptz,
 cancel_at_period_end boolean not null default false, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
alter table public.profiles add column if not exists organization_id uuid references public.organizations(id);
alter table public.client_accounts add column if not exists organization_id uuid references public.organizations(id);
alter table public.client_projects add column if not exists organization_id uuid references public.organizations(id);
alter table public.client_project_milestones add column if not exists organization_id uuid references public.organizations(id);
alter table public.client_project_designs add column if not exists organization_id uuid references public.organizations(id);
alter table public.client_project_comments add column if not exists organization_id uuid references public.organizations(id);
alter table public.client_design_reviews add column if not exists organization_id uuid references public.organizations(id);
alter table public.employee_assignments add column if not exists organization_id uuid references public.organizations(id);
alter table public.employee_updates add column if not exists organization_id uuid references public.organizations(id);
alter table public.notifications add column if not exists organization_id uuid references public.organizations(id);
alter table public.workspace_data add column if not exists organization_id uuid references public.organizations(id);
insert into public.organizations(id,name,slug,status,created_by)
values('9f23d2a4-2c52-4f71-93b4-7e2e9b61a001','WASLA STUDIO','wasla-studio-legacy','active','3faa9e5a-ca45-47ca-8c02-a03e399ca60a')
on conflict(id) do nothing;
alter table public.employee_assignments disable trigger trg_guard_employee_assignment_updates;
update public.profiles set organization_id='9f23d2a4-2c52-4f71-93b4-7e2e9b61a001' where organization_id is null;
update public.client_accounts set organization_id='9f23d2a4-2c52-4f71-93b4-7e2e9b61a001' where organization_id is null;
update public.client_projects set organization_id='9f23d2a4-2c52-4f71-93b4-7e2e9b61a001' where organization_id is null;
update public.client_project_milestones set organization_id='9f23d2a4-2c52-4f71-93b4-7e2e9b61a001' where organization_id is null;
update public.client_project_designs set organization_id='9f23d2a4-2c52-4f71-93b4-7e2e9b61a001' where organization_id is null;
update public.client_project_comments set organization_id='9f23d2a4-2c52-4f71-93b4-7e2e9b61a001' where organization_id is null;
update public.client_design_reviews set organization_id='9f23d2a4-2c52-4f71-93b4-7e2e9b61a001' where organization_id is null;
update public.employee_assignments set organization_id='9f23d2a4-2c52-4f71-93b4-7e2e9b61a001' where organization_id is null;
alter table public.employee_assignments enable trigger trg_guard_employee_assignment_updates;
update public.employee_updates set organization_id='9f23d2a4-2c52-4f71-93b4-7e2e9b61a001' where organization_id is null;
update public.notifications set organization_id='9f23d2a4-2c52-4f71-93b4-7e2e9b61a001' where organization_id is null;
update public.workspace_data set organization_id='9f23d2a4-2c52-4f71-93b4-7e2e9b61a001' where organization_id is null;
insert into public.organization_members(organization_id,user_id,role,status)
select '9f23d2a4-2c52-4f71-93b4-7e2e9b61a001',id,
case when role in ('owner','admin') then 'owner' when role='employee' then 'employee' else 'client' end,'active'
from public.profiles where organization_id='9f23d2a4-2c52-4f71-93b4-7e2e9b61a001'
on conflict(organization_id,user_id) do nothing;
create index if not exists idx_org_members_user on public.organization_members(user_id,status);
create index if not exists idx_org_subscriptions_org on public.organization_subscriptions(organization_id,status);
create index if not exists idx_profiles_org on public.profiles(organization_id);
create index if not exists idx_client_projects_org on public.client_projects(organization_id);
create index if not exists idx_employee_assignments_org on public.employee_assignments(organization_id);
create or replace function private.current_organization_id() returns uuid language sql stable security definer set search_path='' as $$
 select om.organization_id from public.organization_members om join public.organizations o on o.id=om.organization_id and o.status='active'
 where om.user_id=(select auth.uid()) and om.status='active'
 order by case om.role when 'owner' then 0 when 'admin' then 1 else 2 end limit 1
$$;
create or replace function private.has_organization_role(p_roles text[]) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organization_members om join public.organizations o on o.id=om.organization_id and o.status='active'
 where om.user_id=(select auth.uid()) and om.status='active' and om.role=any(p_roles))
$$;
alter table public.organizations enable row level security;
alter table public.organization_members enable row level security;
alter table public.subscription_plans enable row level security;
alter table public.organization_subscriptions enable row level security;
drop policy if exists "Members read their organizations" on public.organizations;
create policy "Members read their organizations" on public.organizations for select to authenticated using(exists(select 1 from public.organization_members om where om.organization_id=organizations.id and om.user_id=(select auth.uid()) and om.status='active'));
drop policy if exists "Members read own organization memberships" on public.organization_members;
create policy "Members read own organization memberships" on public.organization_members for select to authenticated using(user_id=(select auth.uid()) or private.has_organization_role(array['owner','admin']));
drop policy if exists "Authenticated read active subscription plans" on public.subscription_plans;
create policy "Authenticated read active subscription plans" on public.subscription_plans for select to authenticated using(is_active=true);
drop policy if exists "Members read own organization subscriptions" on public.organization_subscriptions;
create policy "Members read own organization subscriptions" on public.organization_subscriptions for select to authenticated using(exists(select 1 from public.organization_members om where om.organization_id=organization_subscriptions.organization_id and om.user_id=(select auth.uid()) and om.status='active'));
grant select on public.organizations,public.organization_members,public.subscription_plans,public.organization_subscriptions to authenticated;
commit;
