create table public.finance_invoices (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 invoice_number text not null, customer_name text not null, customer_email text,
 customer_phone text, client_user_id uuid references auth.users(id) on delete set null,
 invoice_date date not null default current_date, due_date date,
 currency_code text not null, exchange_rate numeric(20,8) not null default 1 check(exchange_rate>0),
 rate_date date not null default current_date, receivable_account_id uuid not null,
 total_original numeric(20,4) not null default 0 check(total_original>=0),
 total_base numeric(20,4) not null default 0 check(total_base>=0),
 paid_original numeric(20,4) not null default 0 check(paid_original>=0),
 status text not null default 'draft' check(status in ('draft','issued','paid')),
 issued_journal_id uuid, created_by uuid not null default auth.uid() references auth.users(id),
 issued_by uuid references auth.users(id), issued_at timestamptz,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 constraint finance_invoices_org_number_unique unique(organization_id,invoice_number),
 constraint finance_invoices_org_id_unique unique(organization_id,id),
 constraint finance_invoices_receivable_same_org_fk foreign key(organization_id,receivable_account_id) references public.finance_accounts(organization_id,id) on delete restrict,
 constraint finance_invoices_journal_same_org_fk foreign key(organization_id,issued_journal_id) references public.finance_journals(organization_id,id) on delete restrict,
 constraint finance_invoices_currency_check check(currency_code ~ '^[A-Z]{3}$'),
 constraint finance_invoices_paid_lte_total check(paid_original<=total_original)
);
create table public.finance_invoice_lines (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 invoice_id uuid not null, description text not null, quantity numeric(20,4) not null check(quantity>0),
 unit_price numeric(20,4) not null check(unit_price>=0), line_total numeric(20,4) not null check(line_total>0),
 revenue_account_id uuid not null, project_ref text, created_by uuid not null default auth.uid() references auth.users(id),
 created_at timestamptz not null default now(),
 constraint finance_invoice_lines_invoice_same_org_fk foreign key(organization_id,invoice_id) references public.finance_invoices(organization_id,id) on delete restrict,
 constraint finance_invoice_lines_revenue_same_org_fk foreign key(organization_id,revenue_account_id) references public.finance_accounts(organization_id,id) on delete restrict
);
create table public.finance_invoice_payments (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 invoice_id uuid not null, payment_number text not null, payment_date date not null default current_date,
 amount_original numeric(20,4) not null check(amount_original>0), currency_code text not null,
 exchange_rate numeric(20,8) not null check(exchange_rate>0), cash_account_id uuid not null,
 journal_id uuid not null, reference text, received_by uuid not null default auth.uid() references auth.users(id),
 created_at timestamptz not null default now(),
 constraint finance_invoice_payments_org_number_unique unique(organization_id,payment_number),
 constraint finance_invoice_payments_invoice_same_org_fk foreign key(organization_id,invoice_id) references public.finance_invoices(organization_id,id) on delete restrict,
 constraint finance_invoice_payments_cash_same_org_fk foreign key(organization_id,cash_account_id) references public.finance_accounts(organization_id,id) on delete restrict,
 constraint finance_invoice_payments_journal_same_org_fk foreign key(organization_id,journal_id) references public.finance_journals(organization_id,id) on delete restrict,
 constraint finance_invoice_payments_currency_check check(currency_code ~ '^[A-Z]{3}$')
);
create index finance_invoices_org_date_idx on public.finance_invoices(organization_id,invoice_date desc);
create index finance_invoice_lines_org_invoice_idx on public.finance_invoice_lines(organization_id,invoice_id);
create index finance_invoice_payments_org_invoice_idx on public.finance_invoice_payments(organization_id,invoice_id,payment_date desc);
alter table public.finance_invoices enable row level security;
alter table public.finance_invoice_lines enable row level security;
alter table public.finance_invoice_payments enable row level security;
create policy finance_invoices_tenant_scope on public.finance_invoices as restrictive for all to authenticated using(organization_id=(select private.current_organization_id())) with check(organization_id=(select private.current_organization_id()));
create policy finance_invoices_read on public.finance_invoices for select to authenticated using(organization_id=(select private.current_organization_id()) and (private.has_organization_role(array['owner','admin']) or private.has_finance_role(array['accountant'])));
create policy finance_invoices_insert on public.finance_invoices for insert to authenticated with check(organization_id=(select private.current_organization_id()) and private.can_write_finance() and created_by=(select auth.uid()) and status='draft');
create policy finance_invoices_update_draft on public.finance_invoices for update to authenticated using(organization_id=(select private.current_organization_id()) and private.can_write_finance() and status='draft') with check(organization_id=(select private.current_organization_id()) and private.can_write_finance() and status in ('draft','issued','paid'));
create policy finance_invoices_delete_draft on public.finance_invoices for delete to authenticated using(organization_id=(select private.current_organization_id()) and private.has_organization_role(array['owner','admin']) and status='draft');
create policy finance_invoice_lines_tenant_scope on public.finance_invoice_lines as restrictive for all to authenticated using(organization_id=(select private.current_organization_id())) with check(organization_id=(select private.current_organization_id()));
create policy finance_invoice_lines_read on public.finance_invoice_lines for select to authenticated using(organization_id=(select private.current_organization_id()) and exists(select 1 from public.finance_invoices i where i.organization_id=finance_invoice_lines.organization_id and i.id=finance_invoice_lines.invoice_id));
create policy finance_invoice_lines_insert_draft on public.finance_invoice_lines for insert to authenticated with check(organization_id=(select private.current_organization_id()) and private.can_write_finance() and created_by=(select auth.uid()) and exists(select 1 from public.finance_invoices i where i.organization_id=finance_invoice_lines.organization_id and i.id=finance_invoice_lines.invoice_id and i.status='draft'));
create policy finance_invoice_lines_update_draft on public.finance_invoice_lines for update to authenticated using(organization_id=(select private.current_organization_id()) and private.can_write_finance() and exists(select 1 from public.finance_invoices i where i.organization_id=finance_invoice_lines.organization_id and i.id=finance_invoice_lines.invoice_id and i.status='draft')) with check(organization_id=(select private.current_organization_id()) and private.can_write_finance() and exists(select 1 from public.finance_invoices i where i.organization_id=finance_invoice_lines.organization_id and i.id=finance_invoice_lines.invoice_id and i.status='draft'));
create policy finance_invoice_lines_delete_draft on public.finance_invoice_lines for delete to authenticated using(organization_id=(select private.current_organization_id()) and private.can_write_finance() and exists(select 1 from public.finance_invoices i where i.organization_id=finance_invoice_lines.organization_id and i.id=finance_invoice_lines.invoice_id and i.status='draft'));
create policy finance_invoice_payments_tenant_scope on public.finance_invoice_payments as restrictive for all to authenticated using(organization_id=(select private.current_organization_id())) with check(organization_id=(select private.current_organization_id()));
create policy finance_invoice_payments_read on public.finance_invoice_payments for select to authenticated using(organization_id=(select private.current_organization_id()) and (private.has_organization_role(array['owner','admin']) or private.has_finance_role(array['accountant'])));
create policy finance_invoice_payments_insert on public.finance_invoice_payments for insert to authenticated with check(organization_id=(select private.current_organization_id()) and private.has_organization_role(array['owner','admin']) and received_by=(select auth.uid()));
create or replace function private.finance_invoice_guard() returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='INSERT' then if new.organization_id is distinct from (select private.current_organization_id()) or not private.can_write_finance() then raise exception 'Not allowed to create invoice in this organization'; end if; return new; end if;
 if tg_op='DELETE' then if old.status<>'draft' or not private.has_organization_role(array['owner','admin']) then raise exception 'Only draft invoices may be deleted by an organization manager'; end if; return old; end if;
 if old.status='draft' then if new.status not in ('draft','issued') then raise exception 'Invalid invoice status transition'; end if; if new.status='issued' and not private.has_organization_role(array['owner','admin']) then raise exception 'Only an organization manager may issue an invoice'; end if; return new; end if;
 if old.status='issued' and new.status in ('issued','paid') and private.has_organization_role(array['owner','admin']) and (to_jsonb(new)-'status'-'paid_original'-'updated_at')=(to_jsonb(old)-'status'-'paid_original'-'updated_at') and new.paid_original>=old.paid_original and new.paid_original<=new.total_original then return new; end if;
 raise exception 'Issued and paid invoices are immutable';
end $$;
create or replace function private.finance_invoice_line_guard() returns trigger language plpgsql set search_path='' as $$
declare v_status text; v_org uuid;
begin v_org:=case when tg_op='DELETE' then old.organization_id else new.organization_id end;
 select status into v_status from public.finance_invoices where organization_id=v_org and id=case when tg_op='DELETE' then old.invoice_id else new.invoice_id end;
 if v_status is distinct from 'draft' or not private.can_write_finance() then raise exception 'Invoice lines can only be changed while invoice is draft'; end if;
 if tg_op='DELETE' then return old; end if; return new; end $$;
create or replace function private.finance_invoice_payment_guard() returns trigger language plpgsql set search_path='' as $$
begin if tg_op<>'INSERT' then raise exception 'Invoice payment records are immutable'; end if;
 if new.organization_id is distinct from (select private.current_organization_id()) or not private.has_organization_role(array['owner','admin']) then raise exception 'Only an organization manager may record invoice payments'; end if; return new; end $$;
create trigger finance_invoices_guard before insert or update or delete on public.finance_invoices for each row execute function private.finance_invoice_guard();
create trigger finance_invoice_lines_guard before insert or update or delete on public.finance_invoice_lines for each row execute function private.finance_invoice_line_guard();
create trigger finance_invoice_payments_guard before insert or update or delete on public.finance_invoice_payments for each row execute function private.finance_invoice_payment_guard();
create trigger finance_invoices_audit after insert or update or delete on public.finance_invoices for each row execute function private.finance_audit_trigger();
create trigger finance_invoice_lines_audit after insert or update or delete on public.finance_invoice_lines for each row execute function private.finance_audit_trigger();
create trigger finance_invoice_payments_audit after insert or update or delete on public.finance_invoice_payments for each row execute function private.finance_audit_trigger();

grant select,insert,update,delete on public.finance_invoices,public.finance_invoice_lines to authenticated;
grant select,insert on public.finance_invoice_payments to authenticated;
