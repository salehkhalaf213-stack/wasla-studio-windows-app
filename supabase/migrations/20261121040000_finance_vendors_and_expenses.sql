-- WASLA FINANCE: supplier directory, vendor bills, expense recognition and settlement.
-- Additive only: existing users, accounts, invoices, journals and legacy archive remain untouched.

create table public.finance_vendors (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 vendor_name text not null check(length(trim(vendor_name)) between 1 and 180),
 email text, phone text, tax_number text, address text,
 is_active boolean not null default true,
 created_by uuid not null default auth.uid() references auth.users(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,id)
);
create index finance_vendors_org_name_idx on public.finance_vendors(organization_id,vendor_name);

create table public.finance_vendor_bills (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 bill_number text not null,
 vendor_id uuid not null,
 vendor_invoice_number text,
 bill_date date not null default current_date,
 due_date date,
 currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 exchange_rate numeric(20,8) not null default 1 check(exchange_rate>0),
 rate_date date not null default current_date,
 payable_account_id uuid not null,
 total_original numeric(20,4) not null default 0 check(total_original>=0),
 total_base numeric(20,4) not null default 0 check(total_base>=0),
 paid_original numeric(20,4) not null default 0 check(paid_original>=0),
 status text not null default 'draft' check(status in ('draft','issued','paid')),
 issued_journal_id uuid,
 created_by uuid not null default auth.uid() references auth.users(id),
 issued_by uuid references auth.users(id),
 issued_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 constraint finance_vendor_bills_org_number_unique unique(organization_id,bill_number),
 constraint finance_vendor_bills_org_id_unique unique(organization_id,id),
 constraint finance_vendor_bills_vendor_fk foreign key(organization_id,vendor_id) references public.finance_vendors(organization_id,id) on delete restrict,
 constraint finance_vendor_bills_payable_fk foreign key(organization_id,payable_account_id) references public.finance_accounts(organization_id,id) on delete restrict,
 constraint finance_vendor_bills_journal_fk foreign key(organization_id,issued_journal_id) references public.finance_journals(organization_id,id) on delete restrict,
 constraint finance_vendor_bills_paid_lte_total check(paid_original<=total_original)
);
create index finance_vendor_bills_org_date_idx on public.finance_vendor_bills(organization_id,bill_date desc);

create table public.finance_vendor_bill_lines (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 bill_id uuid not null,
 description text not null,
 quantity numeric(20,4) not null check(quantity>0),
 unit_price numeric(20,4) not null check(unit_price>0),
 line_total numeric(20,4) not null check(line_total>0),
 expense_account_id uuid not null,
 project_ref text,
 created_by uuid not null default auth.uid() references auth.users(id),
 created_at timestamptz not null default now(),
 constraint finance_vendor_bill_lines_bill_fk foreign key(organization_id,bill_id) references public.finance_vendor_bills(organization_id,id) on delete restrict,
 constraint finance_vendor_bill_lines_expense_fk foreign key(organization_id,expense_account_id) references public.finance_accounts(organization_id,id) on delete restrict
);
create index finance_vendor_bill_lines_org_bill_idx on public.finance_vendor_bill_lines(organization_id,bill_id);

create table public.finance_vendor_bill_payments (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 bill_id uuid not null,
 payment_number text not null,
 payment_date date not null default current_date,
 amount_original numeric(20,4) not null check(amount_original>0),
 currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 exchange_rate numeric(20,8) not null check(exchange_rate>0),
 cash_account_id uuid not null,
 journal_id uuid not null,
 reference text,
 paid_by uuid not null default auth.uid() references auth.users(id),
 created_at timestamptz not null default now(),
 constraint finance_vendor_bill_payments_org_number_unique unique(organization_id,payment_number),
 constraint finance_vendor_bill_payments_bill_fk foreign key(organization_id,bill_id) references public.finance_vendor_bills(organization_id,id) on delete restrict,
 constraint finance_vendor_bill_payments_cash_fk foreign key(organization_id,cash_account_id) references public.finance_accounts(organization_id,id) on delete restrict,
 constraint finance_vendor_bill_payments_journal_fk foreign key(organization_id,journal_id) references public.finance_journals(organization_id,id) on delete restrict
);
create index finance_vendor_bill_payments_org_bill_idx on public.finance_vendor_bill_payments(organization_id,bill_id,payment_date desc);

alter table public.finance_vendors enable row level security;
alter table public.finance_vendor_bills enable row level security;
alter table public.finance_vendor_bill_lines enable row level security;
alter table public.finance_vendor_bill_payments enable row level security;

create policy finance_vendors_tenant_scope on public.finance_vendors as restrictive for all to authenticated
 using(organization_id=(select private.current_organization_id()))
 with check(organization_id=(select private.current_organization_id()));
create policy finance_vendors_read on public.finance_vendors for select to authenticated
 using(organization_id=(select private.current_organization_id()) and (private.has_organization_role(array['owner','admin']) or private.has_finance_role(array['accountant'])));
create policy finance_vendors_insert on public.finance_vendors for insert to authenticated
 with check(organization_id=(select private.current_organization_id()) and private.can_write_finance() and created_by=(select auth.uid()));
create policy finance_vendors_update on public.finance_vendors for update to authenticated
 using(organization_id=(select private.current_organization_id()) and private.can_write_finance())
 with check(organization_id=(select private.current_organization_id()) and private.can_write_finance());
create policy finance_vendors_delete on public.finance_vendors for delete to authenticated
 using(organization_id=(select private.current_organization_id()) and private.has_organization_role(array['owner','admin']));

create policy finance_vendor_bills_tenant_scope on public.finance_vendor_bills as restrictive for all to authenticated
 using(organization_id=(select private.current_organization_id()))
 with check(organization_id=(select private.current_organization_id()));
create policy finance_vendor_bills_read on public.finance_vendor_bills for select to authenticated
 using(organization_id=(select private.current_organization_id()) and (private.has_organization_role(array['owner','admin']) or private.has_finance_role(array['accountant'])));
create policy finance_vendor_bills_insert on public.finance_vendor_bills for insert to authenticated
 with check(organization_id=(select private.current_organization_id()) and private.can_write_finance() and created_by=(select auth.uid()) and status='draft');
create policy finance_vendor_bills_update_draft on public.finance_vendor_bills for update to authenticated
 using(organization_id=(select private.current_organization_id()) and private.can_write_finance() and status='draft')
 with check(organization_id=(select private.current_organization_id()) and private.can_write_finance() and status in ('draft','issued'));
create policy finance_vendor_bills_update_payment on public.finance_vendor_bills for update to authenticated
 using(organization_id=(select private.current_organization_id()) and private.has_organization_role(array['owner','admin']) and status='issued')
 with check(organization_id=(select private.current_organization_id()) and private.has_organization_role(array['owner','admin']) and status in ('issued','paid'));
create policy finance_vendor_bills_delete_draft on public.finance_vendor_bills for delete to authenticated
 using(organization_id=(select private.current_organization_id()) and private.has_organization_role(array['owner','admin']) and status='draft');

create policy finance_vendor_bill_lines_tenant_scope on public.finance_vendor_bill_lines as restrictive for all to authenticated
 using(organization_id=(select private.current_organization_id()))
 with check(organization_id=(select private.current_organization_id()));
create policy finance_vendor_bill_lines_read on public.finance_vendor_bill_lines for select to authenticated
 using(organization_id=(select private.current_organization_id()) and exists(select 1 from public.finance_vendor_bills b where b.organization_id=finance_vendor_bill_lines.organization_id and b.id=finance_vendor_bill_lines.bill_id));
create policy finance_vendor_bill_lines_insert_draft on public.finance_vendor_bill_lines for insert to authenticated
 with check(organization_id=(select private.current_organization_id()) and private.can_write_finance() and created_by=(select auth.uid()) and exists(select 1 from public.finance_vendor_bills b where b.organization_id=finance_vendor_bill_lines.organization_id and b.id=finance_vendor_bill_lines.bill_id and b.status='draft'));
create policy finance_vendor_bill_lines_update_draft on public.finance_vendor_bill_lines for update to authenticated
 using(organization_id=(select private.current_organization_id()) and private.can_write_finance() and exists(select 1 from public.finance_vendor_bills b where b.organization_id=finance_vendor_bill_lines.organization_id and b.id=finance_vendor_bill_lines.bill_id and b.status='draft'))
 with check(organization_id=(select private.current_organization_id()) and private.can_write_finance() and exists(select 1 from public.finance_vendor_bills b where b.organization_id=finance_vendor_bill_lines.organization_id and b.id=finance_vendor_bill_lines.bill_id and b.status='draft'));
create policy finance_vendor_bill_lines_delete_draft on public.finance_vendor_bill_lines for delete to authenticated
 using(organization_id=(select private.current_organization_id()) and private.can_write_finance() and exists(select 1 from public.finance_vendor_bills b where b.organization_id=finance_vendor_bill_lines.organization_id and b.id=finance_vendor_bill_lines.bill_id and b.status='draft'));

create policy finance_vendor_bill_payments_tenant_scope on public.finance_vendor_bill_payments as restrictive for all to authenticated
 using(organization_id=(select private.current_organization_id()))
 with check(organization_id=(select private.current_organization_id()));
create policy finance_vendor_bill_payments_read on public.finance_vendor_bill_payments for select to authenticated
 using(organization_id=(select private.current_organization_id()) and (private.has_organization_role(array['owner','admin']) or private.has_finance_role(array['accountant'])));
create policy finance_vendor_bill_payments_insert on public.finance_vendor_bill_payments for insert to authenticated
 with check(organization_id=(select private.current_organization_id()) and private.has_organization_role(array['owner','admin']) and paid_by=(select auth.uid()));

create or replace function private.finance_vendor_bill_guard() returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='INSERT' then
  if new.organization_id is distinct from (select private.current_organization_id()) or not private.can_write_finance() then raise exception 'Not allowed to create vendor bill in this organization'; end if;
  return new;
 end if;
 if tg_op='DELETE' then
  if old.status<>'draft' or not private.has_organization_role(array['owner','admin']) then raise exception 'Only draft vendor bills may be deleted by an organization manager'; end if;
  return old;
 end if;
 if old.status='draft' then
  if new.status not in ('draft','issued') then raise exception 'Invalid vendor bill status transition'; end if;
  if new.status='issued' and not private.has_organization_role(array['owner','admin']) then raise exception 'Only an organization manager may issue a vendor bill'; end if;
  return new;
 end if;
 if old.status='issued' and new.status in ('issued','paid') and private.has_organization_role(array['owner','admin'])
  and (to_jsonb(new)-'status'-'paid_original'-'updated_at')=(to_jsonb(old)-'status'-'paid_original'-'updated_at')
  and new.paid_original>=old.paid_original and new.paid_original<=new.total_original then return new;
 end if;
 raise exception 'Issued and paid vendor bills are immutable';
end $$;

create or replace function private.finance_vendor_bill_line_guard() returns trigger language plpgsql set search_path='' as $$
declare v_status text; v_org uuid; v_bill uuid;
begin
 v_org:=case when tg_op='DELETE' then old.organization_id else new.organization_id end;
 v_bill:=case when tg_op='DELETE' then old.bill_id else new.bill_id end;
 select status into v_status from public.finance_vendor_bills where organization_id=v_org and id=v_bill;
 if v_status is distinct from 'draft' or not private.can_write_finance() then raise exception 'Vendor bill lines can only be changed while bill is draft'; end if;
 if tg_op='DELETE' then return old; end if;
 return new;
end $$;

create or replace function private.finance_vendor_payment_guard() returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op<>'INSERT' then raise exception 'Vendor payment records are immutable'; end if;
 if new.organization_id is distinct from (select private.current_organization_id()) or not private.has_organization_role(array['owner','admin']) then raise exception 'Only an organization manager may record vendor payments'; end if;
 return new;
end $$;

create trigger finance_vendor_bills_guard before insert or update or delete on public.finance_vendor_bills for each row execute function private.finance_vendor_bill_guard();
create trigger finance_vendor_bill_lines_guard before insert or update or delete on public.finance_vendor_bill_lines for each row execute function private.finance_vendor_bill_line_guard();
create trigger finance_vendor_bill_payments_guard before insert or update or delete on public.finance_vendor_bill_payments for each row execute function private.finance_vendor_payment_guard();
create trigger finance_vendors_audit after insert or update or delete on public.finance_vendors for each row execute function private.finance_audit_trigger();
create trigger finance_vendor_bills_audit after insert or update or delete on public.finance_vendor_bills for each row execute function private.finance_audit_trigger();
create trigger finance_vendor_bill_lines_audit after insert or update or delete on public.finance_vendor_bill_lines for each row execute function private.finance_audit_trigger();
create trigger finance_vendor_bill_payments_audit after insert or update or delete on public.finance_vendor_bill_payments for each row execute function private.finance_audit_trigger();

create or replace function public.create_finance_vendor_bill_draft(
 p_bill_number text,p_vendor_id uuid,p_vendor_invoice_number text,p_bill_date date,p_due_date date,
 p_currency_code text,p_exchange_rate numeric,p_payable_account_id uuid,
 p_line_description text,p_quantity numeric,p_unit_price numeric,p_expense_account_id uuid,p_project_ref text default null
) returns uuid language plpgsql security invoker set search_path='' as $$
declare v_org uuid; v_id uuid; v_base text; v_total numeric(20,4);
begin
 v_org:=(select private.current_organization_id());
 if v_org is null or not private.can_write_finance() then raise exception 'Not authorized to create vendor bill'; end if;
 if length(trim(coalesce(p_bill_number,'')))<1 or length(trim(coalesce(p_line_description,'')))<1 then raise exception 'Bill number and description are required'; end if;
 if p_quantity<=0 or p_unit_price<=0 or p_exchange_rate<=0 or p_currency_code !~ '^[A-Z]{3}$' then raise exception 'Invalid bill amount, currency or exchange rate'; end if;
 select base_currency into v_base from public.finance_settings where organization_id=v_org;
 if v_base is null then raise exception 'Set organization base currency first'; end if;
 if p_currency_code=v_base and p_exchange_rate<>1 then raise exception 'Exchange rate must be 1 for base currency'; end if;
 if not exists(select 1 from public.finance_vendors where organization_id=v_org and id=p_vendor_id and is_active) then raise exception 'Active vendor not found'; end if;
 if not exists(select 1 from public.finance_accounts where organization_id=v_org and id=p_payable_account_id and is_active and account_type='liability') then raise exception 'Select an active accounts payable liability account'; end if;
 if not exists(select 1 from public.finance_accounts where organization_id=v_org and id=p_expense_account_id and is_active and account_type='expense') then raise exception 'Select an active expense account'; end if;
 v_total:=round(p_quantity*p_unit_price,4);
 insert into public.finance_vendor_bills(organization_id,bill_number,vendor_id,vendor_invoice_number,bill_date,due_date,currency_code,exchange_rate,rate_date,payable_account_id,total_original,total_base,created_by)
 values(v_org,trim(p_bill_number),p_vendor_id,nullif(trim(coalesce(p_vendor_invoice_number,'')),''),coalesce(p_bill_date,current_date),p_due_date,p_currency_code,p_exchange_rate,coalesce(p_bill_date,current_date),p_payable_account_id,v_total,round(v_total*p_exchange_rate,4),(select auth.uid()))
 returning id into v_id;
 insert into public.finance_vendor_bill_lines(organization_id,bill_id,description,quantity,unit_price,line_total,expense_account_id,project_ref,created_by)
 values(v_org,v_id,trim(p_line_description),p_quantity,p_unit_price,v_total,p_expense_account_id,nullif(trim(coalesce(p_project_ref,'')),''),(select auth.uid()));
 return v_id;
end $$;

create or replace function public.issue_finance_vendor_bill(p_bill_id uuid) returns uuid
language plpgsql security invoker set search_path='' as $$
declare v_org uuid; v_bill public.finance_vendor_bills%rowtype; v_journal uuid; v_number text; v_total numeric(20,4); v_base numeric(20,4); v_line record;
begin
 v_org:=(select private.current_organization_id());
 if v_org is null or not private.has_organization_role(array['owner','admin']) then raise exception 'Only organization managers may issue vendor bills'; end if;
 select * into v_bill from public.finance_vendor_bills where organization_id=v_org and id=p_bill_id for update;
 if not found or v_bill.status<>'draft' then raise exception 'Draft vendor bill not found'; end if;
 select coalesce(sum(line_total),0) into v_total from public.finance_vendor_bill_lines where organization_id=v_org and bill_id=p_bill_id;
 if v_total<=0 then raise exception 'Vendor bill has no valid lines'; end if;
 v_base:=round(v_total*v_bill.exchange_rate,4);
 v_number:='VB-'||to_char(clock_timestamp(),'YYMMDDHH24MISSMS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,4));
 insert into public.finance_journals(organization_id,entry_number,entry_date,description,status,currency_code,exchange_rate,rate_date,created_by)
 values(v_org,v_number,v_bill.bill_date,'إثبات فاتورة مورد '||v_bill.bill_number,'draft',v_bill.currency_code,v_bill.exchange_rate,v_bill.rate_date,(select auth.uid())) returning id into v_journal;
 for v_line in select * from public.finance_vendor_bill_lines where organization_id=v_org and bill_id=p_bill_id loop
  insert into public.finance_journal_lines(organization_id,journal_id,account_id,line_description,currency_code,exchange_rate,debit_original,credit_original,debit_base,credit_base,project_ref,created_by)
  values(v_org,v_journal,v_line.expense_account_id,v_line.description,v_bill.currency_code,v_bill.exchange_rate,v_line.line_total,0,round(v_line.line_total*v_bill.exchange_rate,4),0,v_line.project_ref,(select auth.uid()));
 end loop;
 insert into public.finance_journal_lines(organization_id,journal_id,account_id,line_description,currency_code,exchange_rate,debit_original,credit_original,debit_base,credit_base,created_by)
 values(v_org,v_journal,v_bill.payable_account_id,'مستحق للمورد '||v_bill.vendor_id,v_bill.currency_code,v_bill.exchange_rate,0,v_total,0,v_base,(select auth.uid()));
 update public.finance_journals set status='posted' where organization_id=v_org and id=v_journal;
 update public.finance_vendor_bills set total_original=v_total,total_base=v_base,status='issued',issued_journal_id=v_journal,issued_by=(select auth.uid()),issued_at=now(),updated_at=now()
 where organization_id=v_org and id=p_bill_id;
 return v_journal;
end $$;

create or replace function public.record_finance_vendor_bill_payment(
 p_bill_id uuid,p_amount numeric,p_cash_account_id uuid,p_payment_date date default current_date,p_reference text default null
) returns text language plpgsql security invoker set search_path='' as $$
declare v_org uuid; v_bill public.finance_vendor_bills%rowtype; v_remaining numeric(20,4); v_base_amount numeric(20,4); v_journal uuid; v_number text;
begin
 v_org:=(select private.current_organization_id());
 if v_org is null or not private.has_organization_role(array['owner','admin']) then raise exception 'Only organization managers may pay vendor bills'; end if;
 select * into v_bill from public.finance_vendor_bills where organization_id=v_org and id=p_bill_id for update;
 if not found or v_bill.status not in ('issued','paid') then raise exception 'Issued vendor bill not found'; end if;
 v_remaining:=v_bill.total_original-v_bill.paid_original;
 if p_amount is null or p_amount<=0 or p_amount>v_remaining then raise exception 'Payment amount exceeds remaining balance'; end if;
 if not exists(select 1 from public.finance_accounts where organization_id=v_org and id=p_cash_account_id and is_active and account_type='asset' and (account_name ilike '%صندوق%' or account_name ilike '%بنك%' or account_name ilike '%cash%' or account_name ilike '%bank%')) then raise exception 'Select an active cash or bank account'; end if;
 v_base_amount:=round(p_amount*v_bill.exchange_rate,4);
 v_number:='VBP-'||to_char(clock_timestamp(),'YYMMDDHH24MISSMS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,4));
 insert into public.finance_journals(organization_id,entry_number,entry_date,description,status,currency_code,exchange_rate,rate_date,created_by)
 values(v_org,v_number,coalesce(p_payment_date,current_date),'سداد فاتورة مورد '||v_bill.bill_number,'draft',v_bill.currency_code,v_bill.exchange_rate,coalesce(p_payment_date,current_date),(select auth.uid())) returning id into v_journal;
 insert into public.finance_journal_lines(organization_id,journal_id,account_id,line_description,currency_code,exchange_rate,debit_original,credit_original,debit_base,credit_base,created_by)
 values(v_org,v_journal,v_bill.payable_account_id,'تخفيض مستحقات المورد',v_bill.currency_code,v_bill.exchange_rate,p_amount,0,v_base_amount,0,(select auth.uid())),
       (v_org,v_journal,p_cash_account_id,'سداد من الصندوق أو البنك',v_bill.currency_code,v_bill.exchange_rate,0,p_amount,0,v_base_amount,(select auth.uid()));
 update public.finance_journals set status='posted' where organization_id=v_org and id=v_journal;
 insert into public.finance_vendor_bill_payments(organization_id,bill_id,payment_number,payment_date,amount_original,currency_code,exchange_rate,cash_account_id,journal_id,reference,paid_by)
 values(v_org,p_bill_id,v_number,coalesce(p_payment_date,current_date),p_amount,v_bill.currency_code,v_bill.exchange_rate,p_cash_account_id,v_journal,nullif(trim(coalesce(p_reference,'')),''),(select auth.uid()));
 update public.finance_vendor_bills set paid_original=paid_original+p_amount,status=case when paid_original+p_amount>=total_original then 'paid' else 'issued' end,updated_at=now()
 where organization_id=v_org and id=p_bill_id;
 return v_number;
end $$;

grant select,insert,update,delete on public.finance_vendors,public.finance_vendor_bills,public.finance_vendor_bill_lines to authenticated;
grant select,insert on public.finance_vendor_bill_payments to authenticated;
grant execute on function public.create_finance_vendor_bill_draft(text,uuid,text,date,date,text,numeric,uuid,text,numeric,numeric,uuid,text) to authenticated;
grant execute on function public.issue_finance_vendor_bill(uuid) to authenticated;
grant execute on function public.record_finance_vendor_bill_payment(uuid,numeric,uuid,date,text) to authenticated;
