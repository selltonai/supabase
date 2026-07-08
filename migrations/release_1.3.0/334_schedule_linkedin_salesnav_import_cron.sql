-- 334 — Phase 2: schedule the LinkedIn Sales Navigator import drain cron.
--
-- Mirrors 270_schedule_linkedin_auto_enroll_cron.sql exactly: pg_cron fires
-- net.http_post against the internal BFF endpoint, authenticating with the
-- shared secret read from sellton_internal.cron_config (key 'internal_cron_api_key')
-- and the base URL from key 'public_app_url'.
--
-- The drain route claims ONE pending/running linkedin_salesnav_import_jobs row,
-- pages the Unipile search a bounded number of pages, feeds the CRM CSV sink,
-- and persists the next cursor — so each tick is short and the job resumes.
--
-- Prereqs (already established by migrations 264/265/270):
--   - pg_cron + pg_net extensions enabled
--   - sellton_internal.cron_config rows: 'public_app_url', 'internal_cron_api_key'
--   - Vercel env INTERNAL_CRON_API_KEY matches cron_config.internal_cron_api_key
--
-- Idempotent: unschedule any prior job of the same name before re-scheduling.

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'sellton-linkedin-salesnav-import') THEN
    PERFORM cron.unschedule('sellton-linkedin-salesnav-import');
  END IF;
END $$;

SELECT cron.schedule(
  'sellton-linkedin-salesnav-import',
  '*/2 * * * *',  -- every 2 minutes (network-bound; one bounded job per tick)
  $cron$
  SELECT net.http_post(
    url := (SELECT value FROM sellton_internal.cron_config WHERE key = 'public_app_url')
           || '/api/internal/linkedin/salesnav-import',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'X-Internal-API-Key', (SELECT value FROM sellton_internal.cron_config WHERE key = 'internal_cron_api_key')
    ),
    body := jsonb_build_object('source', 'pg_cron'),
    timeout_milliseconds := 30000
  );
  $cron$
);

-- Verify:
--   select jobname, schedule, active from cron.job where jobname = 'sellton-linkedin-salesnav-import';
-- Unschedule (rollback):
--   select cron.unschedule('sellton-linkedin-salesnav-import');
