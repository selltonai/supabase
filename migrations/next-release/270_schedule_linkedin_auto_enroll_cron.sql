-- ============================================================
--  Migration: 257_schedule_linkedin_auto_enroll_cron
--  Date:      2026-05-06
--  V3 P0-J — schedules the LinkedIn auto-enrol cron.
--
--  Pairs with /api/internal/linkedin/auto-enroll. Every 5 minutes,
--  the cron fires that endpoint with the same INTERNAL_CRON_API_KEY
--  the sequence-claim cron uses (read at fire time from
--  sellton_internal.cron_config — see migration 252).
--
--  Why 5 minutes vs the claim cron's 1-minute cadence:
--    Contact discovery (Modal /campaign/v2/company/process) takes
--    seconds-to-minutes per company. Polling every minute would burn
--    DB queries with no new candidates 80% of the time. 5 minutes is
--    the sweet spot — fast enough that "campaign launched → first
--    LinkedIn invite drafted" stays inside a coffee-break window,
--    cheap enough to scan all active LinkedIn campaigns each pass.
--
--  Storage shape:
--    sellton_internal.cron_config is a (key, value) key-value table.
--    Required rows BEFORE running this migration (same rows 252b
--    needs — there's only one set of keys):
--
--      INSERT INTO sellton_internal.cron_config (key, value, description) VALUES
--        ('public_app_url',        'https://your-vercel-deploy.vercel.app',
--         'Base URL for cron-fired BFF endpoints'),
--        ('internal_cron_api_key', '<matches Vercel INTERNAL_CRON_API_KEY env>',
--         'Shared secret for cron-only API endpoints')
--      ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW();
--
--    The cron body reads these via subquery at FIRING time, so
--    rotation is just an UPDATE — no need to re-run this migration.
--
--  Idempotent: cron.unschedule before cron.schedule, so re-running is
--  safe.
--
--  Verify (after apply):
--    SELECT jobid, jobname, schedule, active
--      FROM cron.job
--     WHERE jobname = 'sellton-linkedin-auto-enroll';
--    -- 1 row, every 5 min, active=true
-- ============================================================

-- Sanity check: the user populated the config rows before running
-- this. If they didn't, RAISE with the exact INSERT they need.
DO $$
DECLARE
  v_app_url TEXT;
  v_api_key TEXT;
BEGIN
  SELECT value INTO v_app_url FROM sellton_internal.cron_config WHERE key = 'public_app_url';
  SELECT value INTO v_api_key FROM sellton_internal.cron_config WHERE key = 'internal_cron_api_key';

  IF v_app_url IS NULL OR v_app_url = '' THEN
    RAISE EXCEPTION
      'V3 P0-J — sellton_internal.cron_config row missing key=public_app_url. Run the INSERT documented in this migration''s header comment, then re-run this migration.';
  END IF;
  IF v_api_key IS NULL OR v_api_key = '' THEN
    RAISE EXCEPTION
      'V3 P0-J — sellton_internal.cron_config row missing key=internal_cron_api_key. Run the INSERT documented in this migration''s header comment, then re-run this migration.';
  END IF;
END $$;

-- Drop any prior schedule for this job so the migration is idempotent.
SELECT cron.unschedule('sellton-linkedin-auto-enroll')
 WHERE EXISTS (
   SELECT 1 FROM cron.job
    WHERE jobname = 'sellton-linkedin-auto-enroll'
 );

-- Schedule: every 5 minutes. The cron body reads URL + key from
-- sellton_internal.cron_config at FIRING time, mirroring 252b's
-- pattern so secret rotation doesn't require unscheduling.
SELECT cron.schedule(
  'sellton-linkedin-auto-enroll',
  '*/5 * * * *',  -- every 5 minutes
  $cron$
  SELECT net.http_post(
    url := (SELECT value FROM sellton_internal.cron_config WHERE key = 'public_app_url')
           || '/api/internal/linkedin/auto-enroll',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'X-Internal-API-Key', (SELECT value FROM sellton_internal.cron_config WHERE key = 'internal_cron_api_key')
    ),
    body := jsonb_build_object('source', 'pg_cron'),
    timeout_milliseconds := 30000
  );
  $cron$
);

NOTIFY pgrst, 'reload schema';
