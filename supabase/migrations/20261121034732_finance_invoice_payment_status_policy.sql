create policy finance_invoices_update_issued_payment on public.finance_invoices for update to authenticated
using(organization_id=(select private.current_organization_id()) and private.has_organization_role(array['owner','admin']) and status='issued')
with check(organization_id=(select private.current_organization_id()) and private.has_organization_role(array['owner','admin']) and status in ('issued','paid'));
