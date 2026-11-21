create or replace function public.create_finance_invoice_draft(p_invoice_number text,p_customer_name text,p_customer_email text,p_invoice_date date,p_due_date date,p_currency_code text,p_exchange_rate numeric,p_receivable_account_id uuid,p_line_description text,p_quantity numeric,p_unit_price numeric,p_revenue_account_id uuid,p_project_ref text default null)
returns uuid language plpgsql security invoker set search_path='' as $$
declare v_org uuid:=(select private.current_organization_id()); v_invoice_id uuid; v_base_currency text; v_total numeric(20,4);
begin
 if not private.can_write_finance() then raise exception 'Finance write permission required'; end if;
 if nullif(trim(p_invoice_number),'') is null or nullif(trim(p_customer_name),'') is null then raise exception 'Invoice number and customer name are required'; end if;
 if p_quantity is null or p_quantity<=0 or p_unit_price is null or p_unit_price<=0 then raise exception 'Quantity and unit price must be positive'; end if;
 if p_currency_code !~ '^[A-Z]{3}$' or p_exchange_rate is null or p_exchange_rate<=0 then raise exception 'Invalid currency or exchange rate'; end if;
 select base_currency into v_base_currency from public.finance_settings where organization_id=v_org;
 if v_base_currency is null then raise exception 'Set the organization base currency first'; end if;
 if p_currency_code=v_base_currency and p_exchange_rate<>1 then raise exception 'Exchange rate must be 1 for the base currency'; end if;
 if not exists(select 1 from public.finance_accounts where organization_id=v_org and id=p_receivable_account_id and account_type='asset' and is_active) then raise exception 'Select an active receivable asset account'; end if;
 if not exists(select 1 from public.finance_accounts where organization_id=v_org and id=p_revenue_account_id and account_type='revenue' and is_active) then raise exception 'Select an active revenue account'; end if;
 v_total:=round(p_quantity*p_unit_price,4); if v_total<=0 then raise exception 'Invoice line total must be positive'; end if;
 insert into public.finance_invoices(organization_id,invoice_number,customer_name,customer_email,invoice_date,due_date,currency_code,exchange_rate,rate_date,receivable_account_id,created_by)
 values(v_org,trim(p_invoice_number),trim(p_customer_name),nullif(trim(p_customer_email),''),p_invoice_date,p_due_date,p_currency_code,p_exchange_rate,p_invoice_date,p_receivable_account_id,(select auth.uid())) returning id into v_invoice_id;
 insert into public.finance_invoice_lines(organization_id,invoice_id,description,quantity,unit_price,line_total,revenue_account_id,project_ref,created_by)
 values(v_org,v_invoice_id,trim(p_line_description),p_quantity,p_unit_price,v_total,p_revenue_account_id,p_project_ref,(select auth.uid()));
 return v_invoice_id;
end $$;
revoke all on function public.create_finance_invoice_draft(text,text,text,date,date,text,numeric,uuid,text,numeric,numeric,uuid,text) from public,anon;
grant execute on function public.create_finance_invoice_draft(text,text,text,date,date,text,numeric,uuid,text,numeric,numeric,uuid,text) to authenticated;
