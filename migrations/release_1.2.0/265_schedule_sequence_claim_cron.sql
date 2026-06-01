-- ============================================================
--  Migration: 252b_schedule_sequence_claim_cron
--  Date:      2026-05-06
--  Author:    Sellton AI — LinkedIn V3 / P1-1
--  Plan ref:  /Ground Truth/LINKEDIN_V3_EXECUTION_PLAN.md §3 P1-1
-- ============================================================
--
--  Purpose
--  -------
--  Phase 2 of 2 for the LinkedIn-sequence cron scheduler. Reads the
--  config rows the user INSERTed into sellton_internal.cron_config
--  and registers the every-minute pg_cron job that fires the BFF
--  claimer endpoint.
--
--  Prerequisites
--  -------------
--  Migration 252 must have been applied (creates the schema + table).
--  Two config rows must be present in sellton_internal.cron_config:
--    - public_app_url        (e.g. 'https://app.sellton.com')
--    - internal_cron_api_key (matches Vercel INTERNAL_CRON_API_KEY env)
--
--  If the rows are missing, this migration RAISEs cleanly with the
--  exact INSERT statements you need to run. The cron job is NOT
--  scheduled in that case (the table from 252 stays intact).
--
--  Idempotency: re-runnable. cron.unschedule + cron.schedule each apply.
--
--  Verify (after apply):
--    SELECT jobid, jobname, schedule, active
--      FROM cron.job
--     WHERE jobname = 'sellton-linkedin-sequence-claim';
--    -- 1 row, active=true
--
--    -- Wait 60s, then check it ran:
--    SELECT runid, status, return_message, start_time
--      FROM cron.job_run_details
--     WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'sellton-linkedin-sequence-claim')
--     ORDER BY start_time DESC LIMIT 5;
--
--  Rollback:
--    SELECT cron.unschedule('sellton-linkedin-sequence-claim');
--
--  Rotate the secret later:
--    UPDATE sellton_internal.cron_config
--       SET value = '<new-hex-secret>', updated_at = NOW()
--     WHERE key = 'internal_cron_api_key';
--    -- No schedule re-create needed; the cron body re-reads the
--    -- table on every firing.
-- ============================================================

-- Sanity check: the user populated the config table BEFORE this
-- migration ran. Without this, the cron would fire but fail every
-- minute trying to dereference NULL.
DO $$
DECLARE
  v_app_url TEXT;
  v_api_key TEXT;
BEGIN
  SELECT value INTO v_app_url FROM sellton_internal.cron_config WHERE key = 'public_app_url';
  SELECT value INTO v_api_key FROM sellton_internal.cron_config WHERE key = 'internal_cron_api_key';

  IF v_app_url IS NULL OR v_app_url = '' THEN
    RAISE EXCEPTION
      'sellton_internal.cron_config has no row for ''public_app_url''. Run this first (then re-run migration 252b):
       INSERT INTO sellton_internal.cron_config(key, value)
         VALUES (''public_app_url'', ''https://YOUR-VERCEL-DOMAIN'')
         ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW();';
  END IF;
  IF v_api_key IS NULL OR v_api_key = '' THEN
    RAISE EXCEPTION
      'sellton_internal.cron_config has no row for ''internal_cron_api_key''. Run this first (then re-run migration 252b):
       INSERT INTO sellton_internal.cron_config(key, value)
         VALUES (''internal_cron_api_key'', ''YOUR-HEX-SECRET'')
         ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW();';
  END IF;
END $$;

-- Drop any prior schedule for this job so the migration is idempotent.
SELECT cron.unschedule('sellton-linkedin-sequence-claim')
 WHERE EXISTS (
   SELECT 1 FROM cron.job
    WHERE jobname = 'sellton-linkedin-sequence-claim'
 );

-- Schedule: every minute. The cron body reads URL + key from
-- sellton_internal.cron_config at FIRING time, so secret rotation
-- doesn't require unscheduling/rescheduling — just UPDATE the row.
SELECT cron.schedule(
  'sellton-linkedin-sequence-claim',
  '* * * * *',  -- every minute
  $cron$
  SELECT net.http_post(
    url := (SELECT value FROM sellton_internal.cron_config WHERE key = 'public_app_url')
           || '/api/internal/sequence/claim',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'X-Internal-API-Key', (SELECT value FROM sellton_internal.cron_config WHERE key = 'internal_cron_api_key')
    ),
    body := jsonb_build_object('source', 'pg_cron'),
    timeout_milliseconds := 30000
  );
  $cron$
);

COMMENT ON EXTENSION pg_cron IS
  'V3 P1-1 sequence scheduler. Job: sellton-linkedin-sequence-claim. Config: sellton_internal.cron_config. See migrations 252 + 252b.';

NOTIFY pgrst, 'reload schema';
