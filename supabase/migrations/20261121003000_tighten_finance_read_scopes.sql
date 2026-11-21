-- Tighten WASLA FINANCE visibility: project-scoped roles must not browse the full chart of accounts.
drop policy if exists finance_settings_tenant_read on public.finance_settings;
create policy finance_settings_tenant_read on public.finance_settings
for select to authenticated using (
  organization_id = (select private.current_organization_id())
  and private.can_read_finance()
);

drop policy if exists finance_accounts_read on public.finance_accounts;
create policy finance_accounts_read on public.finance_accounts
for select to authenticated using (
  organization_id = (select private.current_organization_id())
  and (
    private.has_organization_role(array['owner','admin'])
    or private.has_finance_role(array['accountant'])
  )
);

drop policy if exists finance_audit_log_read on public.finance_audit_log;
create policy finance_audit_log_read on public.finance_audit_log
for select to authenticated using (
  organization_id = (select private.current_organization_id())
  and (
    private.has_organization_role(array['owner','admin'])
    or (
      private.has_finance_role(array['accountant'])
      and actor_id = (select auth.uid())
    )
  )
);
