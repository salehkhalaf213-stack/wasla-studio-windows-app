-- WASLA FINANCE foundation: tenant-scoped settings, permissions, chart of accounts,
-- journal entries, journal lines, project visibility grants, and immutable audit trail.
-- Legacy workspace_data.payload->finance is intentionally untouched.

create table public.finance_settings (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  base_currency text null check (base_currency is null or base_currency ~ '^[A-Z]{3}$'),
  fiscal_year_start_month smallint not null default 1 check (fiscal_year_start_month between 1 and 12),
  created_by uuid null references auth.users(id) on delete set null,
  updated_by uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.finance_member_roles (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  finance_role text not null check (finance_role in ('accountant','project_manager','finance_viewer')),
  granted_by uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (organization_id, user_id, finance_role)
);

create table public.finance_project_access (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  project_ref text not null,
  granted_by uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (organization_id, user_id, project_ref)
);

create table public.finance_accounts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  account_code text not null,
  account_name text not null,
  account_type text not null check (account_type in ('asset','liability','equity','revenue','expense')),
  parent_id uuid null,
  is_system boolean not null default false,
  is_active boolean not null default true,
  created_by uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, account_code),
  unique (organization_id, id),
  constraint finance_accounts_parent_same_org_fk
    foreign key (organization_id, parent_id)
    references public.finance_accounts(organization_id, id)
    on delete restrict
);

create table public.finance_journals (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  entry_number text not null,
  entry_date date not null,
  description text not null,
  status text not null default 'draft' check (status in ('draft','posted','reversed')),
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  exchange_rate numeric(20,8) not null default 1 check (exchange_rate > 0),
  rate_date date not null default current_date,
  project_ref text null,
  created_by uuid not null references auth.users(id),
  approved_by uuid null references auth.users(id),
  posted_at timestamptz null,
  reversal_of uuid null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, entry_number),
  unique (organization_id, id),
  constraint finance_journals_reversal_same_org_fk
    foreign key (organization_id, reversal_of)
    references public.finance_journals(organization_id, id)
    on delete restrict
);

create table public.finance_journal_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  journal_id uuid not null,
  account_id uuid not null,
  line_description text null,
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  exchange_rate numeric(20,8) not null check (exchange_rate > 0),
  debit_original numeric(20,4) not null default 0 check (debit_original >= 0),
  credit_original numeric(20,4) not null default 0 check (credit_original >= 0),
  debit_base numeric(20,4) not null default 0 check (debit_base >= 0),
  credit_base numeric(20,4) not null default 0 check (credit_base >= 0),
  project_ref text null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  constraint finance_journal_lines_one_side_check
    check ((debit_original > 0 and credit_original = 0) or (credit_original > 0 and debit_original = 0)),
  constraint finance_journal_lines_base_one_side_check
    check ((debit_base > 0 and credit_base = 0) or (credit_base > 0 and debit_base = 0)),
  constraint finance_journal_lines_journal_same_org_fk
    foreign key (organization_id, journal_id)
    references public.finance_journals(organization_id, id)
    on delete restrict,
  constraint finance_journal_lines_account_same_org_fk
    foreign key (organization_id, account_id)
    references public.finance_accounts(organization_id, id)
    on delete restrict
);

create table public.finance_audit_log (
  id bigint generated always as identity primary key,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  table_name text not null,
  record_id uuid null,
  action text not null check (action in ('INSERT','UPDATE','DELETE')),
  actor_id uuid null references auth.users(id) on delete set null,
  occurred_at timestamptz not null default now(),
  old_data jsonb null,
  new_data jsonb null
);

create index finance_member_roles_user_idx on public.finance_member_roles(organization_id,user_id);
create index finance_project_access_user_idx on public.finance_project_access(organization_id,user_id,project_ref);
create index finance_accounts_org_type_idx on public.finance_accounts(organization_id,account_type);
create index finance_journals_org_date_idx on public.finance_journals(organization_id,entry_date desc);
create index finance_journals_org_status_idx on public.finance_journals(organization_id,status);
create index finance_journals_org_project_idx on public.finance_journals(organization_id,project_ref);
create index finance_journal_lines_journal_idx on public.finance_journal_lines(organization_id,journal_id);
create index finance_audit_log_org_time_idx on public.finance_audit_log(organization_id,occurred_at desc);

create or replace function private.has_finance_role(p_roles text[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.finance_member_roles fmr
    where fmr.organization_id = (select private.current_organization_id())
      and fmr.user_id = (select auth.uid())
      and fmr.finance_role = any(p_roles)
  );
$$;

create or replace function private.can_read_finance()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_organization_role(array['owner','admin'])
      or private.has_finance_role(array['accountant','project_manager','finance_viewer']);
$$;

create or replace function private.can_write_finance()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_organization_role(array['owner','admin'])
      or private.has_finance_role(array['accountant']);
$$;

create or replace function private.finance_journal_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_debit numeric(20,4);
  v_credit numeric(20,4);
begin
  if tg_op = 'DELETE' then
    if old.status <> 'draft' then
      raise exception 'Posted or reversed journal entries cannot be deleted; create a reversal entry.';
    end if;
    return old;
  end if;

  if old.status in ('posted','reversed') then
    raise exception 'Posted or reversed journal entries are immutable.';
  end if;

  if new.status = 'posted' and old.status = 'draft' then
    if not private.has_organization_role(array['owner','admin']) then
      raise exception 'Only an organization owner or manager may approve and post journal entries.';
    end if;

    select coalesce(sum(debit_base),0), coalesce(sum(credit_base),0)
      into v_debit, v_credit
    from public.finance_journal_lines
    where organization_id = new.organization_id and journal_id = new.id;

    if v_debit <= 0 or v_debit <> v_credit then
      raise exception 'Journal entry is not balanced in the organization base currency.';
    end if;

    new.approved_by := (select auth.uid());
    new.posted_at := now();
  elsif new.status <> 'draft' then
    raise exception 'Invalid journal status transition.';
  end if;

  new.updated_at := now();
  return new;
end;
$$;

create or replace function private.finance_journal_line_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_status text;
  v_org uuid;
  v_journal uuid;
begin
  v_org := case when tg_op = 'DELETE' then old.organization_id else new.organization_id end;
  v_journal := case when tg_op = 'DELETE' then old.journal_id else new.journal_id end;
  select status into v_status from public.finance_journals
   where organization_id = v_org and id = v_journal;
  if v_status is distinct from 'draft' then
    raise exception 'Journal lines can only be changed while the journal is a draft.';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create or replace function private.finance_audit_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old jsonb;
  v_new jsonb;
  v_org uuid;
  v_record uuid;
begin
  if tg_op in ('UPDATE','DELETE') then v_old := to_jsonb(old); end if;
  if tg_op in ('INSERT','UPDATE') then v_new := to_jsonb(new); end if;
  v_org := coalesce((v_new->>'organization_id')::uuid,(v_old->>'organization_id')::uuid);
  v_record := coalesce((v_new->>'id')::uuid,(v_old->>'id')::uuid,(v_new->>'user_id')::uuid,(v_old->>'user_id')::uuid,v_org);
  insert into public.finance_audit_log(organization_id,table_name,record_id,action,actor_id,old_data,new_data)
  values (v_org, tg_table_name, v_record, tg_op, (select auth.uid()), v_old, v_new);
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create trigger finance_journals_immutable_guard
before update or delete on public.finance_journals
for each row execute function private.finance_journal_guard();

create trigger finance_journal_lines_draft_guard
before insert or update or delete on public.finance_journal_lines
for each row execute function private.finance_journal_line_guard();

do $$
declare t text;
begin
  foreach t in array array['finance_settings','finance_member_roles','finance_project_access','finance_accounts','finance_journals','finance_journal_lines'] loop
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function private.finance_audit_trigger()', t || '_audit', t);
  end loop;
end $$;

alter table public.finance_settings enable row level security;
alter table public.finance_member_roles enable row level security;
alter table public.finance_project_access enable row level security;
alter table public.finance_accounts enable row level security;
alter table public.finance_journals enable row level security;
alter table public.finance_journal_lines enable row level security;
alter table public.finance_audit_log enable row level security;

create policy finance_settings_tenant_read on public.finance_settings
for select to authenticated using (organization_id = (select private.current_organization_id()));
create policy finance_settings_manager_write on public.finance_settings
for all to authenticated using (
  organization_id = (select private.current_organization_id())
  and private.has_organization_role(array['owner','admin'])
) with check (
  organization_id = (select private.current_organization_id())
  and private.has_organization_role(array['owner','admin'])
);

create policy finance_member_roles_read on public.finance_member_roles
for select to authenticated using (
  organization_id = (select private.current_organization_id())
  and (user_id = (select auth.uid()) or private.has_organization_role(array['owner','admin']))
);
create policy finance_member_roles_manager_write on public.finance_member_roles
for all to authenticated using (
  organization_id = (select private.current_organization_id())
  and private.has_organization_role(array['owner','admin'])
) with check (
  organization_id = (select private.current_organization_id())
  and private.has_organization_role(array['owner','admin'])
);

create policy finance_project_access_read on public.finance_project_access
for select to authenticated using (
  organization_id = (select private.current_organization_id())
  and (user_id = (select auth.uid()) or private.has_organization_role(array['owner','admin']))
);
create policy finance_project_access_manager_write on public.finance_project_access
for all to authenticated using (
  organization_id = (select private.current_organization_id())
  and private.has_organization_role(array['owner','admin'])
) with check (
  organization_id = (select private.current_organization_id())
  and private.has_organization_role(array['owner','admin'])
);

create policy finance_accounts_read on public.finance_accounts
for select to authenticated using (
  organization_id = (select private.current_organization_id()) and private.can_read_finance()
);
create policy finance_accounts_write on public.finance_accounts
for insert to authenticated with check (
  organization_id = (select private.current_organization_id()) and private.can_write_finance()
);
create policy finance_accounts_update on public.finance_accounts
for update to authenticated using (
  organization_id = (select private.current_organization_id()) and private.can_write_finance()
) with check (
  organization_id = (select private.current_organization_id()) and private.can_write_finance()
);
create policy finance_accounts_delete_manager on public.finance_accounts
for delete to authenticated using (
  organization_id = (select private.current_organization_id())
  and private.has_organization_role(array['owner','admin'])
  and is_system = false
);

create policy finance_journals_read on public.finance_journals
for select to authenticated using (
  organization_id = (select private.current_organization_id())
  and (
    private.can_write_finance()
    or (
      private.has_finance_role(array['project_manager','finance_viewer'])
      and project_ref is not null
      and exists (
        select 1 from public.finance_project_access fpa
        where fpa.organization_id = finance_journals.organization_id
          and fpa.user_id = (select auth.uid())
          and fpa.project_ref = finance_journals.project_ref
      )
    )
  )
);
create policy finance_journals_insert on public.finance_journals
for insert to authenticated with check (
  organization_id = (select private.current_organization_id())
  and private.can_write_finance()
  and created_by = (select auth.uid())
  and status = 'draft'
);
create policy finance_journals_update_draft on public.finance_journals
for update to authenticated using (
  organization_id = (select private.current_organization_id())
  and private.can_write_finance()
  and status = 'draft'
) with check (
  organization_id = (select private.current_organization_id())
  and private.can_write_finance()
  and status in ('draft','posted')
);
create policy finance_journals_delete_draft_manager on public.finance_journals
for delete to authenticated using (
  organization_id = (select private.current_organization_id())
  and private.has_organization_role(array['owner','admin'])
  and status = 'draft'
);

create policy finance_journal_lines_read on public.finance_journal_lines
for select to authenticated using (
  organization_id = (select private.current_organization_id())
  and exists (
    select 1 from public.finance_journals j
    where j.organization_id = finance_journal_lines.organization_id
      and j.id = finance_journal_lines.journal_id
  )
);
create policy finance_journal_lines_insert_draft on public.finance_journal_lines
for insert to authenticated with check (
  organization_id = (select private.current_organization_id())
  and private.can_write_finance()
  and created_by = (select auth.uid())
  and exists (
    select 1 from public.finance_journals j
    where j.organization_id = finance_journal_lines.organization_id
      and j.id = finance_journal_lines.journal_id and j.status = 'draft'
  )
);
create policy finance_journal_lines_update_draft on public.finance_journal_lines
for update to authenticated using (
  organization_id = (select private.current_organization_id())
  and private.can_write_finance()
  and exists (
    select 1 from public.finance_journals j
    where j.organization_id = finance_journal_lines.organization_id
      and j.id = finance_journal_lines.journal_id and j.status = 'draft'
  )
) with check (
  organization_id = (select private.current_organization_id())
  and private.can_write_finance()
  and exists (
    select 1 from public.finance_journals j
    where j.organization_id = finance_journal_lines.organization_id
      and j.id = finance_journal_lines.journal_id and j.status = 'draft'
  )
);
create policy finance_journal_lines_delete_draft on public.finance_journal_lines
for delete to authenticated using (
  organization_id = (select private.current_organization_id())
  and private.can_write_finance()
  and exists (
    select 1 from public.finance_journals j
    where j.organization_id = finance_journal_lines.organization_id
      and j.id = finance_journal_lines.journal_id and j.status = 'draft'
  )
);

create policy finance_audit_log_read on public.finance_audit_log
for select to authenticated using (
  organization_id = (select private.current_organization_id())
  and private.has_organization_role(array['owner','admin'])
);
create policy finance_audit_log_insert_internal on public.finance_audit_log
for insert to authenticated with check (false);

create policy finance_settings_tenant_scope on public.finance_settings
as restrictive for all to authenticated using (
  organization_id = (select private.current_organization_id())
) with check (organization_id = (select private.current_organization_id()));
create policy finance_member_roles_tenant_scope on public.finance_member_roles
as restrictive for all to authenticated using (
  organization_id = (select private.current_organization_id())
) with check (organization_id = (select private.current_organization_id()));
create policy finance_project_access_tenant_scope on public.finance_project_access
as restrictive for all to authenticated using (
  organization_id = (select private.current_organization_id())
) with check (organization_id = (select private.current_organization_id()));
create policy finance_accounts_tenant_scope on public.finance_accounts
as restrictive for all to authenticated using (
  organization_id = (select private.current_organization_id())
) with check (organization_id = (select private.current_organization_id()));
create policy finance_journals_tenant_scope on public.finance_journals
as restrictive for all to authenticated using (
  organization_id = (select private.current_organization_id())
) with check (organization_id = (select private.current_organization_id()));
create policy finance_journal_lines_tenant_scope on public.finance_journal_lines
as restrictive for all to authenticated using (
  organization_id = (select private.current_organization_id())
) with check (organization_id = (select private.current_organization_id()));
create policy finance_audit_log_tenant_scope on public.finance_audit_log
as restrictive for all to authenticated using (
  organization_id = (select private.current_organization_id())
) with check (organization_id = (select private.current_organization_id()));

grant select, insert, update, delete on
  public.finance_settings, public.finance_member_roles, public.finance_project_access,
  public.finance_accounts, public.finance_journals, public.finance_journal_lines,
  public.finance_audit_log to authenticated;
grant usage, select on sequence public.finance_audit_log_id_seq to authenticated;
revoke all on function private.finance_audit_trigger() from public, anon, authenticated;
