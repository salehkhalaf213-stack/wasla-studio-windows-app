create or replace function public.finance_my_project_summaries()
returns table (
  project_ref text,
  base_currency text,
  revenue_base numeric,
  expense_base numeric,
  profit_base numeric
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    access.project_ref,
    settings.base_currency,
    coalesce(sum(case when account.account_type = 'revenue'
      then line.credit_base - line.debit_base else 0 end), 0)::numeric,
    coalesce(sum(case when account.account_type = 'expense'
      then line.debit_base - line.credit_base else 0 end), 0)::numeric,
    (
      coalesce(sum(case when account.account_type = 'revenue'
        then line.credit_base - line.debit_base else 0 end), 0)
      -
      coalesce(sum(case when account.account_type = 'expense'
        then line.debit_base - line.credit_base else 0 end), 0)
    )::numeric
  from public.finance_project_access access
  join public.finance_settings settings
    on settings.organization_id = access.organization_id
  left join public.finance_journals journal
    on journal.organization_id = access.organization_id
   and journal.status = 'posted'
   and journal.project_ref = access.project_ref
  left join public.finance_journal_lines line
    on line.organization_id = journal.organization_id
   and line.journal_id = journal.id
   and coalesce(line.project_ref, journal.project_ref) = access.project_ref
  left join public.finance_accounts account
    on account.organization_id = line.organization_id
   and account.id = line.account_id
  where access.organization_id = (select private.current_organization_id())
    and access.user_id = (select auth.uid())
    and private.has_finance_role(array['project_manager','finance_viewer'])
  group by access.project_ref, settings.base_currency
  order by access.project_ref;
$$;
