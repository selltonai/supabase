-- ============================================================
-- Migration: 449_stage-cron-app-url
-- Date:      2026-11-21
-- Purpose:   Stage moved to the Hetzner web server (stage-ver.sellton.ai, 2026-11-07), but the stage pg_cron jobs
--            (sellton-linkedin-sequence-claim and the jobs of 270, 334, 336) still call the old Vercel stage app,
--            selltonai-stage.vercel.app: its log of 2026-11-21 05:50 to 06:15 UTC shows /api/internal/sequence/claim,
--            /api/internal/linkedin/auto-enroll and /api/internal/linkedin/connections-sync. That app serves an older
--            build, so stage work merged since then (the signals mini sequence, app #973) never runs from the cron.
--            The jobs read the address from sellton_internal.cron_config at each firing (265), so one row changes.
-- Scope:     The row changes ONLY when it holds the old Vercel stage address. On any other database (production's
--            app address) this migration changes nothing. The key row (internal_cron_api_key) is not touched.
-- Contract:  One row of sellton_internal.cron_config. No schema, job or function change. Idempotent.
-- Rollback:  rollback/449_stage-cron-app-url.rollback.sql (the address kept in public_app_url_before_449 back).
-- ============================================================

DO $$
DECLARE
  v_before TEXT;
  v_rows   INTEGER;
BEGIN
  SELECT value INTO v_before FROM sellton_internal.cron_config WHERE key = 'public_app_url';

  -- Keep the old address for the rollback, only when it is the Vercel stage one.
  IF v_before ILIKE '%selltonai-stage%.vercel.app%' THEN
    INSERT INTO sellton_internal.cron_config(key, value) VALUES ('public_app_url_before_449', v_before)
    ON CONFLICT (key) DO NOTHING;
  END IF;

  UPDATE sellton_internal.cron_config
     SET value = 'https://stage-ver.sellton.ai', updated_at = NOW()
   WHERE key = 'public_app_url'
     AND value ILIKE '%selltonai-stage%.vercel.app%';
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  RAISE NOTICE '449: public_app_url was % ; rows changed %', COALESCE(v_before, '(none)'), v_rows;
END $$;
