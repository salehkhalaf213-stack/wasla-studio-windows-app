-- WASLA FINANCE: additive VAT support for customer and supplier invoices.
-- Existing posted invoices, journals, payments, and balances are not rewritten.
-- New vendor input VAT is posted to a dedicated recoverable VAT asset account.

alter table public.finance_invoices
  add column if not exists subtotal_original numeric(20,4) not null default 0,
  add column if not exists subtotal_base numeric(20,4) not null default 0,
  add column if not exists vat_rate numeric(7,4) not null default 0,
  add column if not exists vat_original numeric(20,4) not null default 0,
  add column if not exists vat_base numeric(20,4) not null default 0,
  add column if not exists vat_account_id uuid;

alter table public.finance_vendor_bills
  add column if not exists subtotal_original numeric(20,4) not null default 0,
  add column if not exists subtotal_base numeric(20,4) not null default 0,
  add column if not exists vat_rate numeric(7,4) not null default 0,
  add column if not exists vat_original numeric(20,4) not null default 0,
  add column if not exists vat_base numeric(20,4) not null default 0,
  add column if not exists vat_account_id uuid;

do $$
begin
  if not exists (select 1 from pg_constraint where conname='finance_invoices_vat_rate_check' and conrelid='public.finance_invoices'::regclass) then
    alter table public.finance_invoices add constraint finance_invoices_vat_rate_check check (vat_rate between 0 and 100);
  end if;
  if not exists (select 1 from pg_constraint where conname='finance_invoices_vat_account_same_org_fk' and conrelid='public.finance_invoices'::regclass) then
    alter table public.finance_invoices add constraint finance_invoices_vat_account_same_org_fk
      foreign key (organization_id,vat_account_id) references public.finance_accounts(organization_id,id) on delete restrict;
  end if;
  if not exists (select 1 from pg_constraint where conname='finance_vendor_bills_vat_rate_check' and conrelid='public.finance_vendor_bills'::regclass) then
    alter table public.finance_vendor_bills add constraint finance_vendor_bills_vat_rate_check check (vat_rate between 0 and 100);
  end if;
  if not exists (select 1 from pg_constraint where conname='finance_vendor_bills_vat_account_same_org_fk' and conrelid='public.finance_vendor_bills'::regclass) then
    alter table public.finance_vendor_bills add constraint finance_vendor_bills_vat_account_same_org_fk
      foreign key (organization_id,vat_account_id) references public.finance_accounts(organization_id,id) on delete restrict;
  end if;
end $$;

create or replace function public.create_finance_invoice_draft(
  p_invoice_number text,p_customer_name text,p_customer_email text,p_invoice_date date,p_due_date date,
  p_currency_code text,p_exchange_rate numeric,p_receivable_account_id uuid,p_line_description text,
  p_quantity numeric,p_unit_price numeric,p_revenue_account_id uuid,p_project_ref text,
  p_vat_rate numeric,p_vat_account_id uuid
) returns uuid
language plpgsql security invoker set search_path='' as $$
declare
  v_org uuid := (select private.current_organization_id());
  v_invoice_id uuid;
  v_base_currency text;
  v_subtotal numeric(20,4);
  v_vat numeric(20,4);
  v_total numeric(20,4);
begin
  if not private.can_write_finance() then raise exception 'Finance write permission required'; end if;
  if nullif(trim(p_invoice_number),'') is null or nullif(trim(p_customer_name),'') is null then raise exception 'Invoice number and customer name are required'; end if;
  if p_quantity is null or p_quantity<=0 or p_unit_price is null or p_unit_price<=0 then raise exception 'Quantity and unit price must be positive'; end if;
  if p_currency_code !~ '^[A-Z]{3}$' or p_exchange_rate is null or p_exchange_rate<=0 then raise exception 'Invalid currency or exchange rate'; end if;
  if p_vat_rate is null or p_vat_rate<0 or p_vat_rate>100 then raise exception 'VAT rate must be between 0 and 100'; end if;
  select base_currency into v_base_currency from public.finance_settings where organization_id=v_org;
  if v_base_currency is null then raise exception 'Set the organization base currency first'; end if;
  if p_currency_code=v_base_currency and p_exchange_rate<>1 then raise exception 'Exchange rate must be 1 for the base currency'; end if;
  if not exists(select 1 from public.finance_accounts where organization_id=v_org and id=p_receivable_account_id and account_type='asset' and is_active) then raise exception 'Select an active receivable asset account'; end if;
  if not exists(select 1 from public.finance_accounts where organization_id=v_org and id=p_revenue_account_id and account_type='revenue' and is_active) then raise exception 'Select an active revenue account'; end if;
  if p_vat_rate>0 and not exists(select 1 from public.finance_accounts where organization_id=v_org and id=p_vat_account_id and account_type='liability' and is_active) then raise exception 'Select an active VAT liability account'; end if;
  v_subtotal:=round(p_quantity*p_unit_price,4);
  if v_subtotal<=0 then raise exception 'Invoice line total must be positive'; end if;
  v_vat:=round(v_subtotal*p_vat_rate/100,4);
  v_total:=round(v_subtotal+v_vat,4);
  insert into public.finance_invoices(
    organization_id,invoice_number,customer_name,customer_email,invoice_date,due_date,currency_code,
    exchange_rate,rate_date,receivable_account_id,vat_rate,vat_account_id,
    subtotal_original,subtotal_base,vat_original,vat_base,total_original,total_base,created_by
  ) values (
    v_org,trim(p_invoice_number),trim(p_customer_name),nullif(trim(p_customer_email),''),
    p_invoice_date,p_due_date,p_currency_code,p_exchange_rate,p_invoice_date,p_receivable_account_id,
    p_vat_rate,case when p_vat_rate>0 then p_vat_account_id else null end,
    v_subtotal,round(v_subtotal*p_exchange_rate,4),v_vat,round(v_vat*p_exchange_rate,4),
    v_total,round(v_total*p_exchange_rate,4),(select auth.uid())
  ) returning id into v_invoice_id;
  insert into public.finance_invoice_lines(organization_id,invoice_id,description,quantity,unit_price,line_total,revenue_account_id,project_ref,created_by)
  values(v_org,v_invoice_id,trim(p_line_description),p_quantity,p_unit_price,v_subtotal,p_revenue_account_id,p_project_ref,(select auth.uid()));
  return v_invoice_id;
end $$;

create or replace function public.issue_finance_invoice(p_invoice_id uuid) returns uuid
language plpgsql security invoker set search_path='' as $$
declare
  v_org uuid := (select private.current_organization_id());
  v_invoice public.finance_invoices%rowtype;
  v_line record;
  v_subtotal numeric(20,4):=0;
  v_vat numeric(20,4):=0;
  v_total numeric(20,4):=0;
  v_subtotal_base numeric(20,4):=0;
  v_vat_base numeric(20,4):=0;
  v_total_base numeric(20,4):=0;
  v_journal_id uuid;
  v_entry text;
  v_line_count integer:=0;
begin
  if not private.has_organization_role(array['owner','admin']) then raise exception 'Only organization managers may issue invoices'; end if;
  select * into v_invoice from public.finance_invoices where id=p_invoice_id and organization_id=v_org for update;
  if not found or v_invoice.status<>'draft' then raise exception 'Invoice not found or not draft'; end if;
  if length(trim(v_invoice.customer_name))=0 then raise exception 'Customer name is required'; end if;
  if not exists(select 1 from public.finance_accounts a where a.organization_id=v_org and a.id=v_invoice.receivable_account_id and a.account_type='asset' and a.is_active) then raise exception 'Select an active accounts-receivable asset account'; end if;
  if coalesce(v_invoice.vat_rate,0)<0 or coalesce(v_invoice.vat_rate,0)>100 then raise exception 'Invalid invoice VAT rate'; end if;
  if coalesce(v_invoice.vat_rate,0)>0 and not exists(select 1 from public.finance_accounts a where a.organization_id=v_org and a.id=v_invoice.vat_account_id and a.account_type='liability' and a.is_active) then raise exception 'Select an active VAT liability account'; end if;
  for v_line in
    select l.*,a.account_type,a.is_active from public.finance_invoice_lines l
    join public.finance_accounts a on a.organization_id=l.organization_id and a.id=l.revenue_account_id
    where l.organization_id=v_org and l.invoice_id=p_invoice_id
  loop
    if v_line.account_type<>'revenue' or not v_line.is_active then raise exception 'Every invoice line must use an active revenue account'; end if;
    if round(v_line.quantity*v_line.unit_price,4)<>v_line.line_total then raise exception 'Invoice line total does not match quantity times unit price'; end if;
    v_subtotal:=v_subtotal+v_line.line_total;
    v_line_count:=v_line_count+1;
  end loop;
  if v_line_count=0 or v_subtotal<=0 then raise exception 'Invoice must contain at least one positive line'; end if;
  v_subtotal:=round(v_subtotal,4);
  v_vat:=round(v_subtotal*coalesce(v_invoice.vat_rate,0)/100,4);
  v_total:=round(v_subtotal+v_vat,4);
  v_subtotal_base:=round(v_subtotal*v_invoice.exchange_rate,4);
  v_vat_base:=round(v_vat*v_invoice.exchange_rate,4);
  v_total_base:=round(v_subtotal_base+v_vat_base,4);
  v_entry:='INV-'||to_char(clock_timestamp(),'YYMMDDHH24MISSMS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,4));
  insert into public.finance_journals(organization_id,entry_number,entry_date,description,status,currency_code,exchange_rate,rate_date,created_by)
  values(v_org,v_entry,v_invoice.invoice_date,'إثبات فاتورة عميل '||v_invoice.invoice_number,'draft',v_invoice.currency_code,v_invoice.exchange_rate,v_invoice.rate_date,(select auth.uid()))
  returning id into v_journal_id;
  insert into public.finance_journal_lines(organization_id,journal_id,account_id,line_description,currency_code,exchange_rate,debit_original,credit_original,debit_base,credit_base,created_by)
  values(v_org,v_journal_id,v_invoice.receivable_account_id,'ذمم مدينة — '||v_invoice.customer_name,v_invoice.currency_code,v_invoice.exchange_rate,v_total,0,v_total_base,0,(select auth.uid()));
  for v_line in select * from public.finance_invoice_lines where organization_id=v_org and invoice_id=p_invoice_id loop
    insert into public.finance_journal_lines(organization_id,journal_id,account_id,line_description,currency_code,exchange_rate,debit_original,credit_original,debit_base,credit_base,project_ref,created_by)
    values(v_org,v_journal_id,v_line.revenue_account_id,v_line.description,v_invoice.currency_code,v_invoice.exchange_rate,0,v_line.line_total,0,round(v_line.line_total*v_invoice.exchange_rate,4),v_line.project_ref,(select auth.uid()));
  end loop;
  if v_vat>0 then
    insert into public.finance_journal_lines(organization_id,journal_id,account_id,line_description,currency_code,exchange_rate,debit_original,credit_original,debit_base,credit_base,created_by)
    values(v_org,v_journal_id,v_invoice.vat_account_id,'ضريبة قيمة مضافة مستحقة — '||v_invoice.invoice_number,v_invoice.currency_code,v_invoice.exchange_rate,0,v_vat,0,v_vat_base,(select auth.uid()));
  end if;
  update public.finance_journals set status='posted' where id=v_journal_id and organization_id=v_org;
  update public.finance_invoices set subtotal_original=v_subtotal,subtotal_base=v_subtotal_base,vat_original=v_vat,vat_base=v_vat_base,total_original=v_total,total_base=v_total_base,issued_journal_id=v_journal_id,issued_by=(select auth.uid()),issued_at=now(),status='issued',updated_at=now()
  where id=p_invoice_id and organization_id=v_org;
  return v_journal_id;
end $$;

create or replace function public.create_finance_vendor_bill_draft(
  p_bill_number text,p_vendor_id uuid,p_vendor_invoice_number text,p_bill_date date,p_due_date date,
  p_currency_code text,p_exchange_rate numeric,p_payable_account_id uuid,p_line_description text,
  p_quantity numeric,p_unit_price numeric,p_expense_account_id uuid,p_project_ref text,
  p_vat_rate numeric,p_vat_account_id uuid
) returns uuid
language plpgsql security invoker set search_path='' as $$
declare
  v_org uuid;
  v_id uuid;
  v_base text;
  v_subtotal numeric(20,4);
  v_vat numeric(20,4);
  v_total numeric(20,4);
begin
  v_org:=(select private.current_organization_id());
  if v_org is null or not private.can_write_finance() then raise exception 'Not authorized to create vendor bill'; end if;
  if length(trim(coalesce(p_bill_number,'')))<1 or length(trim(coalesce(p_line_description,'')))<1 then raise exception 'Bill number and description are required'; end if;
  if p_quantity is null or p_quantity<=0 or p_unit_price is null or p_unit_price<=0 or p_exchange_rate is null or p_exchange_rate<=0 or p_currency_code !~ '^[A-Z]{3}$' then raise exception 'Invalid bill amount, currency or exchange rate'; end if;
  if p_vat_rate is null or p_vat_rate<0 or p_vat_rate>100 then raise exception 'VAT rate must be between 0 and 100'; end if;
  select base_currency into v_base from public.finance_settings where organization_id=v_org;
  if v_base is null then raise exception 'Set organization base currency first'; end if;
  if p_currency_code=v_base and p_exchange_rate<>1 then raise exception 'Exchange rate must be 1 for base currency'; end if;
  if not exists(select 1 from public.finance_vendors where organization_id=v_org and id=p_vendor_id and is_active) then raise exception 'Active vendor not found'; end if;
  if not exists(select 1 from public.finance_accounts where organization_id=v_org and id=p_payable_account_id and is_active and account_type='liability') then raise exception 'Select an active accounts payable liability account'; end if;
  if not exists(select 1 from public.finance_accounts where organization_id=v_org and id=p_expense_account_id and is_active and account_type='expense') then raise exception 'Select an active expense account'; end if;
  if p_vat_rate>0 and not exists(select 1 from public.finance_accounts where organization_id=v_org and id=p_vat_account_id and is_active and account_type='asset') then raise exception 'Select an active recoverable input VAT asset account'; end if;
  v_subtotal:=round(p_quantity*p_unit_price,4);
  if v_subtotal<=0 then raise exception 'Vendor bill line total must be positive'; end if;
  v_vat:=round(v_subtotal*p_vat_rate/100,4);
  v_total:=round(v_subtotal+v_vat,4);
  insert into public.finance_vendor_bills(
    organization_id,bill_number,vendor_id,vendor_invoice_number,bill_date,due_date,currency_code,
    exchange_rate,rate_date,payable_account_id,subtotal_original,subtotal_base,vat_rate,vat_account_id,
    vat_original,vat_base,total_original,total_base,created_by
  ) values (
    v_org,trim(p_bill_number),p_vendor_id,nullif(trim(coalesce(p_vendor_invoice_number,'')),''),coalesce(p_bill_date,current_date),
    p_due_date,p_currency_code,p_exchange_rate,coalesce(p_bill_date,current_date),p_payable_account_id,
    v_subtotal,round(v_subtotal*p_exchange_rate,4),p_vat_rate,case when p_vat_rate>0 then p_vat_account_id else null end,
    v_vat,round(v_vat*p_exchange_rate,4),v_total,round(v_total*p_exchange_rate,4),(select auth.uid())
  ) returning id into v_id;
  insert into public.finance_vendor_bill_lines(organization_id,bill_id,description,quantity,unit_price,line_total,expense_account_id,project_ref,created_by)
  values(v_org,v_id,trim(p_line_description),p_quantity,p_unit_price,v_subtotal,p_expense_account_id,nullif(trim(coalesce(p_project_ref,'')),''),(select auth.uid()));
  return v_id;
end $$;

create or replace function public.issue_finance_vendor_bill(p_bill_id uuid) returns uuid
language plpgsql security invoker set search_path='' as $$
declare
  v_org uuid;
  v_bill public.finance_vendor_bills%rowtype;
  v_journal uuid;
  v_number text;
  v_subtotal numeric(20,4):=0;
  v_vat numeric(20,4):=0;
  v_total numeric(20,4):=0;
  v_subtotal_base numeric(20,4):=0;
  v_vat_base numeric(20,4):=0;
  v_total_base numeric(20,4):=0;
  v_line record;
  v_line_count integer:=0;
begin
  v_org:=(select private.current_organization_id());
  if v_org is null or not private.has_organization_role(array['owner','admin']) then raise exception 'Only organization managers may issue vendor bills'; end if;
  select * into v_bill from public.finance_vendor_bills where organization_id=v_org and id=p_bill_id for update;
  if not found or v_bill.status<>'draft' then raise exception 'Draft vendor bill not found'; end if;
  if coalesce(v_bill.vat_rate,0)<0 or coalesce(v_bill.vat_rate,0)>100 then raise exception 'Invalid vendor bill VAT rate'; end if;
  if coalesce(v_bill.vat_rate,0)>0 and not exists(select 1 from public.finance_accounts where organization_id=v_org and id=v_bill.vat_account_id and is_active and account_type='asset') then raise exception 'Select an active recoverable input VAT asset account'; end if;
  for v_line in
    select l.*,a.account_type,a.is_active from public.finance_vendor_bill_lines l
    join public.finance_accounts a on a.organization_id=l.organization_id and a.id=l.expense_account_id
    where l.organization_id=v_org and l.bill_id=p_bill_id
  loop
    if v_line.account_type<>'expense' or not v_line.is_active then raise exception 'Every vendor bill line must use an active expense account'; end if;
    if round(v_line.quantity*v_line.unit_price,4)<>v_line.line_total then raise exception 'Vendor bill line total does not match quantity times unit price'; end if;
    v_subtotal:=v_subtotal+v_line.line_total;
    v_line_count:=v_line_count+1;
  end loop;
  if v_line_count=0 or v_subtotal<=0 then raise exception 'Vendor bill has no valid lines'; end if;
  v_subtotal:=round(v_subtotal,4);
  v_vat:=round(v_subtotal*coalesce(v_bill.vat_rate,0)/100,4);
  v_total:=round(v_subtotal+v_vat,4);
  v_subtotal_base:=round(v_subtotal*v_bill.exchange_rate,4);
  v_vat_base:=round(v_vat*v_bill.exchange_rate,4);
  v_total_base:=round(v_subtotal_base+v_vat_base,4);
  v_number:='VB-'||to_char(clock_timestamp(),'YYMMDDHH24MISSMS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,4));
  insert into public.finance_journals(organization_id,entry_number,entry_date,description,status,currency_code,exchange_rate,rate_date,created_by)
  values(v_org,v_number,v_bill.bill_date,'إثبات فاتورة مورد '||v_bill.bill_number,'draft',v_bill.currency_code,v_bill.exchange_rate,v_bill.rate_date,(select auth.uid()))
  returning id into v_journal;
  for v_line in select * from public.finance_vendor_bill_lines where organization_id=v_org and bill_id=p_bill_id loop
    insert into public.finance_journal_lines(organization_id,journal_id,account_id,line_description,currency_code,exchange_rate,debit_original,credit_original,debit_base,credit_base,project_ref,created_by)
    values(v_org,v_journal,v_line.expense_account_id,v_line.description,v_bill.currency_code,v_bill.exchange_rate,v_line.line_total,0,round(v_line.line_total*v_bill.exchange_rate,4),0,v_line.project_ref,(select auth.uid()));
  end loop;
  if v_vat>0 then
    insert into public.finance_journal_lines(organization_id,journal_id,account_id,line_description,currency_code,exchange_rate,debit_original,credit_original,debit_base,credit_base,created_by)
    values(v_org,v_journal,v_bill.vat_account_id,'ضريبة قيمة مضافة مدخلات قابلة للاسترداد — '||v_bill.bill_number,v_bill.currency_code,v_bill.exchange_rate,v_vat,0,v_vat_base,0,(select auth.uid()));
  end if;
  insert into public.finance_journal_lines(organization_id,journal_id,account_id,line_description,currency_code,exchange_rate,debit_original,credit_original,debit_base,credit_base,created_by)
  values(v_org,v_journal,v_bill.payable_account_id,'مستحق للمورد '||v_bill.vendor_id,v_bill.currency_code,v_bill.exchange_rate,0,v_total,0,v_total_base,(select auth.uid()));
  update public.finance_journals set status='posted' where organization_id=v_org and id=v_journal;
  update public.finance_vendor_bills set subtotal_original=v_subtotal,subtotal_base=v_subtotal_base,vat_original=v_vat,vat_base=v_vat_base,
    total_original=v_total,total_base=v_total_base,status='issued',issued_journal_id=v_journal,issued_by=(select auth.uid()),issued_at=now(),updated_at=now()
  where organization_id=v_org and id=p_bill_id;
  return v_journal;
end $$;

revoke all on function public.create_finance_invoice_draft(text,text,text,date,date,text,numeric,uuid,text,numeric,numeric,uuid,text,numeric,uuid) from public,anon;
grant execute on function public.create_finance_invoice_draft(text,text,text,date,date,text,numeric,uuid,text,numeric,numeric,uuid,text,numeric,uuid) to authenticated;
revoke all on function public.issue_finance_invoice(uuid) from public,anon;
grant execute on function public.issue_finance_invoice(uuid) to authenticated;
-- Keep the legacy no-VAT overload available to signed-in users only; it was previously executable by anon.
revoke all on function public.create_finance_vendor_bill_draft(text,uuid,text,date,date,text,numeric,uuid,text,numeric,numeric,uuid,text) from public,anon;
grant execute on function public.create_finance_vendor_bill_draft(text,uuid,text,date,date,text,numeric,uuid,text,numeric,numeric,uuid,text) to authenticated;
revoke all on function public.create_finance_vendor_bill_draft(text,uuid,text,date,date,text,numeric,uuid,text,numeric,numeric,uuid,text,numeric,uuid) from public,anon;
grant execute on function public.create_finance_vendor_bill_draft(text,uuid,text,date,date,text,numeric,uuid,text,numeric,numeric,uuid,text,numeric,uuid) to authenticated;
revoke all on function public.issue_finance_vendor_bill(uuid) from public,anon;
grant execute on function public.issue_finance_vendor_bill(uuid) to authenticated;

comment on column public.finance_vendor_bills.vat_account_id is 'Recoverable input VAT asset account; populated only when vat_rate is greater than zero.';
comment on column public.finance_invoices.vat_account_id is 'Output VAT liability account; populated only when vat_rate is greater than zero.';
