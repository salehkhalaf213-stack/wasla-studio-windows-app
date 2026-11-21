-- VAT support for customer invoices. Existing invoices are explicitly kept tax-free.
alter table public.finance_invoices
  add column if not exists subtotal_original numeric(20,4) not null default 0,
  add column if not exists vat_rate numeric(7,4) not null default 0,
  add column if not exists vat_original numeric(20,4) not null default 0,
  add column if not exists subtotal_base numeric(20,4) not null default 0,
  add column if not exists vat_base numeric(20,4) not null default 0,
  add column if not exists vat_account_id uuid;

-- Historical invoices remain untouched by the immutable-invoice guard. PDF rendering falls back to total_original for legacy rows.

-- Add a dedicated output VAT liability account for each organization where one is not already configured.
insert into public.finance_accounts
  (organization_id, account_code, account_name, account_type, is_system, is_active)
select o.id,
       case when not exists (
         select 1 from public.finance_accounts a
         where a.organization_id=o.id and a.account_code='2200'
       ) then '2200' else 'VAT-OUTPUT' end,
       'ضريبة القيمة المضافة المستحقة',
       'liability', true, true
from public.organizations o
where not exists (
  select 1 from public.finance_accounts a
  where a.organization_id=o.id
    and a.account_type='liability'
    and (a.account_name ilike '%ضريبة القيمة المضافة%' or a.account_name ilike '%vat%')
)
on conflict (organization_id, account_code) do nothing;

create or replace function public.create_finance_invoice_draft(
 p_invoice_number text,p_customer_name text,p_customer_email text,p_invoice_date date,p_due_date date,
 p_currency_code text,p_exchange_rate numeric,p_receivable_account_id uuid,p_line_description text,
 p_quantity numeric,p_unit_price numeric,p_revenue_account_id uuid,p_project_ref text,
 p_vat_rate numeric,p_vat_account_id uuid
)
returns uuid language plpgsql security invoker set search_path='' as $$
declare
 v_org uuid := (select private.current_organization_id());
 v_invoice_id uuid;
 v_base_currency text;
 v_subtotal numeric(20,4);
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
 insert into public.finance_invoices(
  organization_id,invoice_number,customer_name,customer_email,invoice_date,due_date,
  currency_code,exchange_rate,rate_date,receivable_account_id,vat_rate,vat_account_id,
  subtotal_original,subtotal_base,vat_original,vat_base,total_original,total_base,created_by
 ) values (
  v_org,trim(p_invoice_number),trim(p_customer_name),nullif(trim(p_customer_email),''),
  p_invoice_date,p_due_date,p_currency_code,p_exchange_rate,p_invoice_date,p_receivable_account_id,
  p_vat_rate,case when p_vat_rate>0 then p_vat_account_id else null end,
  v_subtotal,round(v_subtotal*p_exchange_rate,4),
  round(v_subtotal*p_vat_rate/100,4),round(round(v_subtotal*p_vat_rate/100,4)*p_exchange_rate,4),
  round(v_subtotal+round(v_subtotal*p_vat_rate/100,4),4),
  round(round(v_subtotal+round(v_subtotal*p_vat_rate/100,4),4)*p_exchange_rate,4),
  (select auth.uid())
 ) returning id into v_invoice_id;
 insert into public.finance_invoice_lines(organization_id,invoice_id,description,quantity,unit_price,line_total,revenue_account_id,project_ref,created_by)
 values(v_org,v_invoice_id,trim(p_line_description),p_quantity,p_unit_price,v_subtotal,p_revenue_account_id,p_project_ref,(select auth.uid()));
 return v_invoice_id;
end $$;

revoke all on function public.create_finance_invoice_draft(text,text,text,date,date,text,numeric,uuid,text,numeric,numeric,uuid,text,numeric,uuid) from public,anon;
grant execute on function public.create_finance_invoice_draft(text,text,text,date,date,text,numeric,uuid,text,numeric,numeric,uuid,text,numeric,uuid) to authenticated;

create or replace function public.issue_finance_invoice(p_invoice_id uuid)
returns uuid language plpgsql security invoker set search_path='' as $$
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
 update public.finance_invoices set subtotal_original=v_subtotal,subtotal_base=v_subtotal_base,vat_original=v_vat,vat_base=v_vat_base,total_original=v_total,total_base=v_total_base,issued_journal_id=v_journal_id,issued_by=(select auth.uid()),issued_at=now(),status='issued',updated_at=now() where id=p_invoice_id and organization_id=v_org;
 return v_journal_id;
end $$;
