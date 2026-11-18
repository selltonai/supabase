-- Reverses 440: reopens analytics_usage_rollup (5 arguments) and billing_week_snapshot to authenticated exactly as
-- main's release_1.3.0/374 left them on production (and RLS off on billing_week_snapshot, as on both lines before).
-- _v2 and _v3 stay closed: 390 closed them before 440, so reopening them would not restore the earlier state.
-- Only to undo a broken deploy; it restores the hole.
SET LOCAL lock_timeout = '10s';

DO $$
BEGIN
  IF to_regprocedure('public.analytics_usage_rollup(text, timestamptz, timestamptz, text, text)') IS NOT NULL THEN
    GRANT EXECUTE ON FUNCTION public.analytics_usage_rollup(text, timestamptz, timestamptz, text, text) TO authenticated;
  END IF;
  IF to_regclass('public.billing_week_snapshot') IS NOT NULL THEN
    ALTER TABLE public.billing_week_snapshot DISABLE ROW LEVEL SECURITY;
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.billing_week_snapshot TO authenticated;
  END IF;
END;
$$;
