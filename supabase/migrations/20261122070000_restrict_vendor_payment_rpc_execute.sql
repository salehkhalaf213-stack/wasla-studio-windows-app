-- Restrict the vendor payment RPC to authenticated callers.
-- Authorization remains enforced inside the function and by the payment trigger.
REVOKE EXECUTE ON FUNCTION public.record_finance_vendor_bill_payment(uuid, numeric, uuid, date, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.record_finance_vendor_bill_payment(uuid, numeric, uuid, date, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.record_finance_vendor_bill_payment(uuid, numeric, uuid, date, text) TO authenticated, service_role;
