-- Enforce approved accounts-payable accounts for every vendor bill write.
-- Existing rows are not modified; the guard runs only on future INSERT/UPDATE events.

create or replace function private.finance_vendor_bill_guard()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  if tg_op='INSERT' then
    if new.organization_id is distinct from (select private.current_organization_id())
       or not private.can_write_finance() then
      raise exception 'Not allowed to create vendor bill in this organization';
    end if;

    if not exists (
      select 1
      from public.finance_accounts a
      where a.organization_id = new.organization_id
        and a.id = new.payable_account_id
        and a.is_active
        and a.account_type = 'liability'
        and (
          coalesce(a.account_code, '') = '2000'
          or a.account_name ~* '(الموردون والذمم الدائنة|ذمم دائنة|accounts payable|trade payables|suppliers)'
        )
    ) then
      raise exception 'Vendor bill must use an active approved accounts-payable account (2000 — الموردون والذمم الدائنة)';
    end if;

    return new;
  end if;

  if tg_op='DELETE' then
    if old.status<>'draft' or not private.has_organization_role(array['owner','admin']) then
      raise exception 'Only draft vendor bills may be deleted by an organization manager';
    end if;
    return old;
  end if;

  if old.status='draft' then
    if new.status not in ('draft','issued') then
      raise exception 'Invalid vendor bill status transition';
    end if;
    if new.status='issued' and not private.has_organization_role(array['owner','admin']) then
      raise exception 'Only an organization manager may issue a vendor bill';
    end if;

    if not exists (
      select 1
      from public.finance_accounts a
      where a.organization_id = new.organization_id
        and a.id = new.payable_account_id
        and a.is_active
        and a.account_type = 'liability'
        and (
          coalesce(a.account_code, '') = '2000'
          or a.account_name ~* '(الموردون والذمم الدائنة|ذمم دائنة|accounts payable|trade payables|suppliers)'
        )
    ) then
      raise exception 'Vendor bill must use an active approved accounts-payable account (2000 — الموردون والذمم الدائنة)';
    end if;

    return new;
  end if;

  if old.status='issued'
     and new.status in ('issued','paid')
     and private.has_organization_role(array['owner','admin'])
     and (to_jsonb(new)-'status'-'paid_original'-'updated_at')=(to_jsonb(old)-'status'-'paid_original'-'updated_at')
     and new.paid_original>=old.paid_original
     and new.paid_original<=new.total_original then
    return new;
  end if;

  raise exception 'Issued and paid vendor bills are immutable';
end
$function$;
