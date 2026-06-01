-- ============================================================
--  Migration: 253_create_provider_event_log_retention
--  Date:      2026-05-06
--  Author:    Sellton AI — LinkedIn V3 / P1-3
--  Plan ref:  /Ground Truth/LINKEDIN_V3_EXECUTION_PLAN.md §3 P1-3
--             /Ground Truth/LINKEDIN_V3_INTEGRATION_REVIEW.updated.md §7.3
-- ============================================================
--
--  Purpose
--  -------
--  `provider_event_log` is append-only and grows ~2,000 rows/day per
--  active org. Without a retention policy:
--    - Storage cost grows unbounded
--    - JSON-heavy `raw_payload` is the primary consumer of disk
--    - Supabase docs are explicit that disk doesn't shrink in place
--      after DELETE (https://supabase.com/docs/guides/troubleshooting/
--      disk-size-not-shrinking-after-deleting-data-135390)
--    - At 10 active orgs × 2k rows/day × 90 days, you're at 1.8M
--      rows of JSON-heavy data with no operational benefit beyond
--      ~7-day debug windows
--
--  Policy
--  ------
--    DAY  0–14 : full row retained (audit + debugging)
--    DAY 14–90 : raw_payload set to NULL; row metadata retained
--                (you can still see WHEN events landed + their dedup
--                 keys + processing_status, but not the body)
--    DAY  90+ : hard-deleted
--
--  Two pg_cron jobs, both running daily at low-traffic hours.
--  pg_cron is already enabled by migration 252 — this is just one more
--  schedule.
--
--  Idempotency: re-runnable. Drops + re-creates the schedules each apply.
--
--  Verify (after apply):
--    SELECT * FROM cron.job WHERE jobname IN (
--      'sellton-provider-event-log-anonymize',
--      'sellton-provider-event-log-purge'
--    );
--
--  Rollback:
--    SELECT cron.unschedule('sellton-provider-event-log-anonymize');
--    SELECT cron.unschedule('sellton-provider-event-log-purge');
-- ============================================================

-- Anonymizer: every day at 03:00 UTC, NULL the raw_payload on rows
-- older than 14 days. Bounded per run so a backlog doesn't blow the
-- 10-min job limit.
SELECT cron.unschedule('sellton-provider-event-log-anonymize')
 WHERE EXISTS (
   SELECT 1 FROM cron.job
    WHERE jobname = 'sellton-provider-event-log-anonymize'
 );

SELECT cron.schedule(
  'sellton-provider-event-log-anonymize',
  '0 3 * * *',  -- 03:00 UTC daily
  $cron$
  UPDATE public.provider_event_log
     SET raw_payload = NULL
   WHERE id IN (
     SELECT id
       FROM public.provider_event_log
      WHERE created_at < NOW() - INTERVAL '14 days'
        AND raw_payload IS NOT NULL
      LIMIT 50000  -- bounded; if backlog exists, next day's run continues
   );
  $cron$
);

-- Purger: every day at 03:30 UTC, hard-delete rows older than 90 days.
-- Independent schedule from the anonymizer so they don't compete for
-- the same lock window.
SELECT cron.unschedule('sellton-provider-event-log-purge')
 WHERE EXISTS (
   SELECT 1 FROM cron.job
    WHERE jobname = 'sellton-provider-event-log-purge'
 );

SELECT cron.schedule(
  'sellton-provider-event-log-purge',
  '30 3 * * *',  -- 03:30 UTC daily
  $cron$
  DELETE FROM public.provider_event_log
   WHERE id IN (
     SELECT id
       FROM public.provider_event_log
      WHERE created_at < NOW() - INTERVAL '90 days'
      LIMIT 50000  -- bounded
   );
  $cron$
);

COMMENT ON TABLE public.provider_event_log IS
  'V3 webhook ingress audit. Retention policy: raw_payload anonymized after 14 days, full row purged after 90 days. See migration 253. Disk does not shrink in place after delete (Supabase doc) — earlier retention = lower steady-state cost.';

NOTIFY pgrst, 'reload schema';
