-- Keep journal access behind authenticated RLS policies.
-- TRUNCATE bypasses row-level security and row triggers, so it must never
-- be granted to API roles on financial journal tables.
REVOKE ALL PRIVILEGES ON TABLE public.finance_journals, public.finance_journal_lines FROM PUBLIC;
REVOKE ALL PRIVILEGES ON TABLE public.finance_journals, public.finance_journal_lines FROM anon;

-- Authenticated users retain ordinary CRUD operations, which remain governed
-- by the existing tenant-scoped RLS policies and immutable-row triggers.
REVOKE TRUNCATE, TRIGGER, REFERENCES
  ON TABLE public.finance_journals, public.finance_journal_lines
  FROM authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE
  ON TABLE public.finance_journals, public.finance_journal_lines
  TO authenticated;
