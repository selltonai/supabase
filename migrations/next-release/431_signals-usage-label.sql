-- ============================================================
-- Migration: 431_signals-usage-label
-- Date:      2026-11-11
-- Purpose:   Signals billing (Borce 2026-11-11): the web app's Brain signal charges carry the label "Signals", as the
--            phone's do since 396. Two rows in action_label_map, same form as 396's mobile_signals row (any provider,
--            any model, priority 1):
--              brain_signals        the poll's charge per new signal (provider brain, model brain-signals-web)
--              brain_signal_router  the grading and routing model calls
--            The Modal PR of the same change puts both services on the invoice line "Signals" (BillingService.ACTION_MAP)
--            and prices a web signal at cost x 3.
-- Projects:  selltonai-database/supabase (owner); reader of action_label_map: analytics_usage_rollup (249).
--            The projection-based rollups (v3, v4, v5) take their label from the CASE in
--            usage_analytics_projection_contribution (345, 396 lines 98 to 111) and do not read this table: see the PR
--            body for what that means on the usage page.
-- Contract:  New rows only. No table, column, function or trigger change. Idempotent (ON CONFLICT DO UPDATE).
--            Merge order: this PR, then the Modal PR (fix/signals-billing-label-price), then the app PR
--            (fix/signals-price-words); none depends on another at runtime.
-- Depends:   public.action_label_map (249), rows of 396.
-- Rollback:  rollback/431_signals-usage-label.rollback.sql (deletes exactly these two rows).
-- ============================================================

INSERT INTO public.action_label_map (provider, service_name, model_name_pattern, requires_grounding, task_key, display_label, priority) VALUES
  ('', 'brain_signals', '', false, 'signals', 'Signals', 1),
  ('', 'brain_signal_router', '', false, 'signals', 'Signals', 1)
ON CONFLICT (provider, service_name, model_name_pattern, requires_grounding, task_key) DO UPDATE SET display_label = EXCLUDED.display_label, priority = EXCLUDED.priority;

-- Verify (read-only):
--   SELECT service_name, task_key, display_label, priority FROM public.action_label_map
--   WHERE service_name IN ('brain_signals', 'brain_signal_router', 'mobile_signals') ORDER BY service_name;  -- 3 rows, all Signals
