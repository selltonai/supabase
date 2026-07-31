-- 335 — Connections-sync worker (network mapping): durable per-account ledger for
-- syncing the connected LinkedIn account's 1st-degree relations and stamping
-- contacts.linkedin_signals.network_distance = 1 onto matching CRM contacts.
--
-- Why: network_distance is the contact-level truth for "is this a connection?"
-- (powers the connection filter + the sequence engine's already_connected path).
-- Today it's only set for Sales Nav imports + on-demand refresh. This worker maps
-- the operator's actual network onto existing CRM contacts so it's accurate
-- platform-wide. It ENRICHES existing contacts only (matches by provider id /
-- linkedin_url) — it never creates contacts.
--
-- The drain cron (/api/internal/linkedin/connections-sync) self-enqueues active
-- accounts that are due for a re-sync, claims one job, pages Unipile relations
-- (bounded per tick, resuming from external_cursor), and marks matches.
--
-- Affected projects:
--   - selltonai: the connections-sync cron writes/reads this table.
-- Deploy together: this migration before the selltonai cron route + schedule (336).
--
-- Additive + non-breaking. Safe to drop while empty.

CREATE TABLE IF NOT EXISTS public.linkedin_network_sync_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  linkedin_account_id uuid NOT NULL REFERENCES public.linkedin_accounts(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'running', 'completed', 'failed', 'cancelled')),
  -- Resume token: the cron pages a large network across ticks. NULL once drained.
  external_cursor text,
  page_count integer NOT NULL DEFAULT 0 CHECK (page_count >= 0),
  fetched_count integer NOT NULL DEFAULT 0 CHECK (fetched_count >= 0),
  matched_count integer NOT NULL DEFAULT 0 CHECK (matched_count >= 0),
  last_error text,
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_network_sync_jobs_org_id ON public.linkedin_network_sync_jobs(organization_id);
CREATE INDEX IF NOT EXISTS idx_network_sync_jobs_account_id ON public.linkedin_network_sync_jobs(linkedin_account_id);
-- Cron claim: pick the oldest not-yet-finished job. Partial index keeps it tiny.
CREATE INDEX IF NOT EXISTS idx_network_sync_jobs_drainable
  ON public.linkedin_network_sync_jobs(created_at)
  WHERE status IN ('pending', 'running');
-- Concurrency guard: at most one active job per account, so the cron's
-- self-enqueue can't pile up duplicate runs for the same account.
CREATE UNIQUE INDEX IF NOT EXISTS uq_network_sync_jobs_one_active_per_account
  ON public.linkedin_network_sync_jobs(linkedin_account_id)
  WHERE status IN ('pending', 'running');

CREATE OR REPLACE FUNCTION public.update_network_sync_jobs_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS network_sync_jobs_updated_at ON public.linkedin_network_sync_jobs;
CREATE TRIGGER network_sync_jobs_updated_at
  BEFORE UPDATE ON public.linkedin_network_sync_jobs
  FOR EACH ROW
  EXECUTE FUNCTION public.update_network_sync_jobs_updated_at();

ALTER TABLE public.linkedin_network_sync_jobs ENABLE ROW LEVEL SECURITY;

-- Org-scoped policies (UI may show sync status). The cron uses service_role,
-- which bypasses RLS.
DROP POLICY IF EXISTS "Users can view network sync jobs for their organization" ON public.linkedin_network_sync_jobs;
CREATE POLICY "Users can view network sync jobs for their organization" ON public.linkedin_network_sync_jobs
  FOR SELECT USING (organization_id = current_setting('app.current_org_id', true));

DROP POLICY IF EXISTS "Users can insert network sync jobs for their organization" ON public.linkedin_network_sync_jobs;
CREATE POLICY "Users can insert network sync jobs for their organization" ON public.linkedin_network_sync_jobs
  FOR INSERT WITH CHECK (organization_id = current_setting('app.current_org_id', true));

DROP POLICY IF EXISTS "Users can update network sync jobs for their organization" ON public.linkedin_network_sync_jobs;
CREATE POLICY "Users can update network sync jobs for their organization" ON public.linkedin_network_sync_jobs
  FOR UPDATE USING (organization_id = current_setting('app.current_org_id', true));

DROP POLICY IF EXISTS "Users can delete network sync jobs for their organization" ON public.linkedin_network_sync_jobs;
CREATE POLICY "Users can delete network sync jobs for their organization" ON public.linkedin_network_sync_jobs
  FOR DELETE USING (organization_id = current_setting('app.current_org_id', true));

COMMENT ON TABLE public.linkedin_network_sync_jobs IS
  'Connections-sync worker: per-account ledger for mapping a LinkedIn account''s 1st-degree relations onto CRM contacts (sets linkedin_signals.network_distance=1). One job pages Unipile relations across cron ticks (external_cursor).';

-- Verify:
--   select column_name, data_type, column_default
--   from information_schema.columns
--   where table_name = 'linkedin_network_sync_jobs' order by ordinal_position;
