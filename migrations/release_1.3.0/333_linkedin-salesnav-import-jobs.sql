-- 333 — Phase 2 (LinkedIn Sales Navigator ingestion): durable fetch ledger for
-- importing a Sales Navigator people-search / lead-list into a CRM list.
--
-- Unipile has no "lead-list-by-id" endpoint; a Sales Nav list is read via the
-- search endpoint (POST /api/v1/linkedin/search, api=sales_navigator) with the
-- operator's pasted Sales Nav URL passed through. A bounded-batch BFF cron pages
-- that search across ticks (resume by cursor), normalizes each result, and feeds
-- the existing CRM CSV sink (CRMService.import_csv_to_list) — which creates its
-- OWN crm_import_jobs row per page batch for the contact-extraction phase.
--
-- This table is the FETCH ledger (the "pull from Unipile" half) and is kept
-- separate from crm_import_jobs (the "extract contacts" half) precisely because
-- import_csv_to_list already owns crm_import_jobs and lacks a cursor/source/url.
--
-- Affected projects:
--   - selltonai: enqueue route (POST /api/linkedin/salesnav/import) writes a job;
--     internal cron (POST /api/internal/linkedin/salesnav-import) drains it.
-- Deploy together: this migration before the selltonai routes + schedule (334).
--
-- Additive + non-breaking. Safe to drop while empty.

-- Operator-saved Sales Nav URL for the list (display + re-import convenience).
ALTER TABLE public.crm_lists
  ADD COLUMN IF NOT EXISTS salesnav_search_url text;

COMMENT ON COLUMN public.crm_lists.salesnav_search_url IS
  'Operator-pasted Sales Navigator people-search / lead-list URL last imported into this list (Phase 2 ingestion).';

CREATE TABLE IF NOT EXISTS public.linkedin_salesnav_import_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  list_id uuid NOT NULL REFERENCES public.crm_lists(id) ON DELETE CASCADE,
  -- The LinkedIn account (must hold a Sales Navigator seat) whose Unipile
  -- connection runs the search. unipile_account_id is resolved at drain time.
  linkedin_account_id uuid NOT NULL REFERENCES public.linkedin_accounts(id) ON DELETE CASCADE,
  search_url text NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'running', 'completed', 'failed', 'cancelled')),
  -- Resume token: the cron pages a large list across ticks, persisting the next
  -- Unipile cursor here. NULL once the list is fully drained.
  external_cursor text,
  page_count integer NOT NULL DEFAULT 0 CHECK (page_count >= 0),
  fetched_count integer NOT NULL DEFAULT 0 CHECK (fetched_count >= 0),
  imported_count integer NOT NULL DEFAULT 0 CHECK (imported_count >= 0),
  last_error text,
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_salesnav_import_jobs_org_id ON public.linkedin_salesnav_import_jobs(organization_id);
CREATE INDEX IF NOT EXISTS idx_salesnav_import_jobs_list_id ON public.linkedin_salesnav_import_jobs(list_id);
CREATE INDEX IF NOT EXISTS idx_salesnav_import_jobs_status ON public.linkedin_salesnav_import_jobs(status);
-- Cron claim: pick the oldest not-yet-finished job. Partial index keeps it tiny.
CREATE INDEX IF NOT EXISTS idx_salesnav_import_jobs_drainable
  ON public.linkedin_salesnav_import_jobs(created_at)
  WHERE status IN ('pending', 'running');

CREATE OR REPLACE FUNCTION public.update_salesnav_import_jobs_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS salesnav_import_jobs_updated_at ON public.linkedin_salesnav_import_jobs;
CREATE TRIGGER salesnav_import_jobs_updated_at
  BEFORE UPDATE ON public.linkedin_salesnav_import_jobs
  FOR EACH ROW
  EXECUTE FUNCTION public.update_salesnav_import_jobs_updated_at();

ALTER TABLE public.linkedin_salesnav_import_jobs ENABLE ROW LEVEL SECURITY;

-- Org-scoped policies mirror crm_import_jobs so the UI can show job status.
-- The drain cron uses the service_role key, which bypasses RLS.
DROP POLICY IF EXISTS "Users can view salesnav import jobs for their organization" ON public.linkedin_salesnav_import_jobs;
CREATE POLICY "Users can view salesnav import jobs for their organization" ON public.linkedin_salesnav_import_jobs
  FOR SELECT USING (organization_id = current_setting('app.current_org_id', true));

DROP POLICY IF EXISTS "Users can insert salesnav import jobs for their organization" ON public.linkedin_salesnav_import_jobs;
CREATE POLICY "Users can insert salesnav import jobs for their organization" ON public.linkedin_salesnav_import_jobs
  FOR INSERT WITH CHECK (organization_id = current_setting('app.current_org_id', true));

DROP POLICY IF EXISTS "Users can update salesnav import jobs for their organization" ON public.linkedin_salesnav_import_jobs;
CREATE POLICY "Users can update salesnav import jobs for their organization" ON public.linkedin_salesnav_import_jobs
  FOR UPDATE USING (organization_id = current_setting('app.current_org_id', true));

DROP POLICY IF EXISTS "Users can delete salesnav import jobs for their organization" ON public.linkedin_salesnav_import_jobs;
CREATE POLICY "Users can delete salesnav import jobs for their organization" ON public.linkedin_salesnav_import_jobs
  FOR DELETE USING (organization_id = current_setting('app.current_org_id', true));

COMMENT ON TABLE public.linkedin_salesnav_import_jobs IS
  'Phase 2: durable fetch-ledger for ingesting a Sales Navigator search/lead-list into a CRM list. One job pages the Unipile search across cron ticks (external_cursor), feeding the CRM CSV sink.';

-- Verify:
--   select column_name, data_type, column_default
--   from information_schema.columns
--   where table_name = 'linkedin_salesnav_import_jobs' order by ordinal_position;
