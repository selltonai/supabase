-- 336 — Connections-sync worker: schedule the network-sync drain cron.
--
-- Mirrors 334_schedule_linkedin_salesnav_import_cron.sql / 270: pg_cron fires
-- net.http_post against the internal BFF endpoint, authenticating with the shared
-- secret from sellton_internal.cron_config (key 'internal_cron_api_key') and the
-- base URL from key 'public_app_url'.
--
-- The route self-enqueues active LinkedIn accounts that are due for a re-sync,
-- claims ONE linkedin_network_sync_jobs row, pages a bounded number of relation
-- pages, marks matching CRM contacts, and persists the next cursor.
--
-- Prereqs (already established by 264/265/270): pg_cron + pg_net, and the
-- cron_config rows 'public_app_url' + 'internal_cron_api_key'.
--
-- Idempotent: unschedule any prior job of the same name before re-scheduling.

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'sellton-linkedin-connections-sync') THEN
    PERFORM cron.unschedule('sellton-linkedin-connections-sync');
  END IF;
END $$;

SELECT cron.schedule(
  'sellton-linkedin-connections-sync',
  '*/10 * * * *',  -- every 10 minutes (network changes slowly; one bounded job per tick)
  $cron$
  SELECT net.http_post(
    url := (SELECT value FROM sellton_internal.cron_config WHERE key = 'public_app_url')
           || '/api/internal/linkedin/connections-sync',
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
--   select jobname, schedule, active from cron.job where jobname = 'sellton-linkedin-connections-sync';
-- Unschedule (rollback):
--   select cron.unschedule('sellton-linkedin-connections-sync');
