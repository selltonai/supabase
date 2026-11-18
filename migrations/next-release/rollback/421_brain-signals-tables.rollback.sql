-- Reverses 421. The enum value of 420 stays (it cannot be dropped). Deploy with BRAIN_SIGNALS_ENABLED=0 first: the poll
-- reads these tables and logs an error on each run while they are gone.
SET LOCAL lock_timeout = '10s';

DROP TABLE IF EXISTS public.brain_signal_cursor;
DROP TABLE IF EXISTS public.company_signal_contact_use;
DROP TABLE IF EXISTS public.company_signal_workspace;
DROP TABLE IF EXISTS public.company_signals;

DROP FUNCTION IF EXISTS public.signal_scope_companies(text, boolean);

DROP INDEX IF EXISTS public.idx_companies_domain_organization;

ALTER TABLE public.companies
  DROP COLUMN IF EXISTS signals_history_skipped_at,
  DROP COLUMN IF EXISTS signals_history_read_at,
  DROP COLUMN IF EXISTS brain_requested_at,
  DROP COLUMN IF EXISTS brain_company_id,
  DROP COLUMN IF EXISTS domain;
