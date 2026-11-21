create or replace function private.finance_invoice_guard() returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='INSERT' then if new.organization_id is distinct from (select private.current_organization_id()) or not private.can_write_finance() then raise exception 'Not allowed to create invoice in this organization'; end if; return new; end if;
 if tg_op='DELETE' then if old.status<>'draft' or not private.has_organization_role(array['owner','admin']) then raise exception 'Only draft invoices may be deleted by an organization manager'; end if; return old; end if;
 if old.status='draft' then if new.status not in ('draft','issued') then raise exception 'Invalid invoice status transition'; end if; if new.status='issued' and not private.has_organization_role(array['owner','admin']) then raise exception 'Only an organization manager may issue an invoice'; end if; return new; end if;
 if old.status='issued' and new.status in ('issued','paid') and private.has_organization_role(array['owner','admin']) and (to_jsonb(new)-'status'-'paid_original'-'updated_at')=(to_jsonb(old)-'status'-'paid_original'-'updated_at') and new.paid_original>=old.paid_original and new.paid_original<=new.total_original then return new; end if;
 raise exception 'Issued and paid invoices are immutable';
end $$;
create or replace function public.issue_finance_invoice(p_invoice_id uuid) returns uuid language plpgsql security invoker set search_path='' as $$
declare v_org uuid:=(select private.current_organization_id()); v_invoice public.finance_invoices%rowtype; v_line record; v_total numeric(20,4):=0; v_total_base numeric(20,4):=0; v_journal_id uuid; v_entry text; v_line_count integer:=0;
begin
 if not private.has_organization_role(array['owner','admin']) then raise exception 'Only organization managers may issue invoices'; end if;
 select * into v_invoice from public.finance_invoices where id=p_invoice_id and organization_id=v_org for update;
 if not found or v_invoice.status<>'draft' then raise exception 'Invoice not found or not draft'; end if;
 if length(trim(v_invoice.customer_name))=0 then raise exception 'Customer name is required'; end if;
 if not exists(select 1 from public.finance_accounts a where a.organization_id=v_org and a.id=v_invoice.receivable_account_id and a.account_type='asset' and a.is_active) then raise exception 'Select an active accounts-receivable asset account'; end if;
 for v_line in select l.*,a.account_type,a.is_active from public.finance_invoice_lines l join public.finance_accounts a on a.organization_id=l.organization_id and a.id=l.revenue_account_id where l.organization_id=v_org and l.invoice_id=p_invoice_id loop
  if v_line.account_type<>'revenue' or not v_line.is_active then raise exception 'Every invoice line must use an active revenue account'; end if;
  if round(v_line.quantity*v_line.unit_price,4)<>v_line.line_total then raise exception 'Invoice line total does not match quantity times unit price'; end if;
  v_total:=v_total+v_line.line_total; v_total_base:=v_total_base+round(v_line.line_total*v_invoice.exchange_rate,4); v_line_count:=v_line_count+1;
 end loop;
 if v_line_count=0 or v_total<=0 then raise exception 'Invoice must contain at least one positive line'; end if;
 v_total:=round(v_total,4); v_total_base:=round(v_total_base,4);
 v_entry:='INV-'||to_char(clock_timestamp(),'YYMMDDHH24MISSMS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,4));
 insert into public.finance_journals(organization_id,entry_number,entry_date,description,status,currency_code,exchange_rate,rate_date,created_by) values(v_org,v_entry,v_invoice.invoice_date,'إثبات فاتورة عميل '||v_invoice.invoice_number,'draft',v_invoice.currency_code,v_invoice.exchange_rate,v_invoice.rate_date,(select auth.uid())) returning id into v_journal_id;
 insert into public.finance_journal_lines(organization_id,journal_id,account_id,line_description,currency_code,exchange_rate,debit_original,credit_original,debit_base,credit_base,created_by) values(v_org,v_journal_id,v_invoice.receivable_account_id,'ذمم مدينة — '||v_invoice.customer_name,v_invoice.currency_code,v_invoice.exchange_rate,v_total,0,v_total_base,0,(select auth.uid()));
 for v_line in select * from public.finance_invoice_lines where organization_id=v_org and invoice_id=p_invoice_id loop
  insert into public.finance_journal_lines(organization_id,journal_id,account_id,line_description,currency_code,exchange_rate,debit_original,credit_original,debit_base,credit_base,project_ref,created_by) values(v_org,v_journal_id,v_line.revenue_account_id,v_line.description,v_invoice.currency_code,v_invoice.exchange_rate,0,v_line.line_total,0,round(v_line.line_total*v_invoice.exchange_rate,4),v_line.project_ref,(select auth.uid()));
 end loop;
 update public.finance_journals set status='posted' where id=v_journal_id and organization_id=v_org;
 update public.finance_invoices set status='issued',total_original=v_total,total_base=v_total_base,issued_journal_id=v_journal_id,issued_by=(select auth.uid()),issued_at=now(),updated_at=now() where id=p_invoice_id and organization_id=v_org;
 return v_journal_id;
end $$;

create or replace function public.record_finance_invoice_payment(p_invoice_id uuid,p_amount numeric,p_cash_account_id uuid,p_payment_date date default current_date,p_reference text default null)
returns uuid language plpgsql security invoker set search_path='' as $$
declare v_org uuid:=(select private.current_organization_id()); v_invoice public.finance_invoices%rowtype; v_paid numeric(20,4); v_remaining numeric(20,4); v_journal_id uuid; v_payment_id uuid; v_entry text;
begin
 if not private.has_organization_role(array['owner','admin']) then raise exception 'Only organization managers may record invoice payments'; end if;
 if p_amount is null or p_amount<=0 then raise exception 'Payment amount must be positive'; end if;
 select * into v_invoice from public.finance_invoices where id=p_invoice_id and organization_id=v_org for update;
 if not found or v_invoice.status not in ('issued','paid') then raise exception 'Invoice is not available for payment'; end if;
 select coalesce(sum(amount_original),0) into v_paid from public.finance_invoice_payments where organization_id=v_org and invoice_id=p_invoice_id;
 v_remaining:=round(v_invoice.total_original-v_paid,4);
 if p_amount>v_remaining then raise exception 'Payment exceeds outstanding invoice balance'; end if;
 if not exists(select 1 from public.finance_accounts a where a.organization_id=v_org and a.id=p_cash_account_id and a.account_type='asset' and a.is_active) then raise exception 'Select an active cash or bank asset account'; end if;
 v_entry:='REC-'||to_char(clock_timestamp(),'YYMMDDHH24MISSMS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,4));
 insert into public.finance_journals(organization_id,entry_number,entry_date,description,status,currency_code,exchange_rate,rate_date,created_by)
 values(v_org,v_entry,p_payment_date,'تحصيل فاتورة عميل '||v_invoice.invoice_number,'draft',v_invoice.currency_code,v_invoice.exchange_rate,p_payment_date,(select auth.uid())) returning id into v_journal_id;
 insert into public.finance_journal_lines(organization_id,journal_id,account_id,line_description,currency_code,exchange_rate,debit_original,credit_original,debit_base,credit_base,created_by)
 values(v_org,v_journal_id,p_cash_account_id,'تحصيل من العميل — '||v_invoice.customer_name,v_invoice.currency_code,v_invoice.exchange_rate,p_amount,0,round(p_amount*v_invoice.exchange_rate,4),0,(select auth.uid()));
 insert into public.finance_journal_lines(organization_id,journal_id,account_id,line_description,currency_code,exchange_rate,debit_original,credit_original,debit_base,credit_base,created_by)
 values(v_org,v_journal_id,v_invoice.receivable_account_id,'تخفيض ذمم فاتورة '||v_invoice.invoice_number,v_invoice.currency_code,v_invoice.exchange_rate,0,p_amount,0,round(p_amount*v_invoice.exchange_rate,4),(select auth.uid()));
 update public.finance_journals set status='posted' where id=v_journal_id and organization_id=v_org;
 insert into public.finance_invoice_payments(organization_id,invoice_id,payment_number,payment_date,amount_original,currency_code,exchange_rate,cash_account_id,journal_id,reference,received_by)
 values(v_org,p_invoice_id,v_entry,p_payment_date,p_amount,v_invoice.currency_code,v_invoice.exchange_rate,p_cash_account_id,v_journal_id,p_reference,(select auth.uid())) returning id into v_payment_id;
 update public.finance_invoices set paid_original=round(v_paid+p_amount,4),status=case when round(v_paid+p_amount,4)>=total_original then 'paid' else 'issued' end,updated_at=now() where id=p_invoice_id and organization_id=v_org;
 return v_payment_id;
end $$;
revoke all on function public.issue_finance_invoice(uuid) from public,anon;
revoke all on function public.record_finance_invoice_payment(uuid,numeric,uuid,date,text) from public,anon;
grant execute on function public.issue_finance_invoice(uuid) to authenticated;
grant execute on function public.record_finance_invoice_payment(uuid,numeric,uuid,date,text) to authenticated;
