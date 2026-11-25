-- ============================================================
-- Migration: 452_deal-hold-and-aged-close
-- Date:      2026-11-25
-- Purpose:   PLAN_PLAYS_DEALS_AND_NURTURE_2026_11_24 (Borce 2026-11-25 "Build on defaults"), D4, D6, D9.
--              1. Index idx_deals_company_closed_at (organization_id, company_id, closed_at) for the deal hold read.
--              2. deal_activities_type_check gains 'aged_close' (D6: a deal quiet for 365 days is set LOST by the
--                 nurture cron) and 'call_connected' (D9: a connected call logged on a signal call task).
--              3. Function deal_hold_companies(p_organization_id, p_company_ids, p_now): the companies held from new
--                 plays by a deal, with the deal named. Held = an open deal (closed_at null), or a deal closed within
--                 the last 365 days. A deal closed by age (an 'aged_close' activity at its close) frees its company at
--                 once (Q2 default). One definition for the app and Modal.
-- Projects:  selltonai-database/supabase (owner); selltonai-modal (deal_hold.py, deal_nurture_service.py) and selltonai
--            (src/lib/play-availability.ts) call the function and fall back to plain selects when it is missing.
-- Contract:  Additive. One index, one widened check (every existing value kept), one new function. No data change,
--            no trigger, no column. Merge order: this, then Modal, then the app.
-- Depends:   public.deals, public.deal_activities (349, 384).
-- Rollback:  rollback/452_deal-hold-and-aged-close.rollback.sql
-- ============================================================

SET LOCAL lock_timeout = '10s';

CREATE INDEX IF NOT EXISTS idx_deals_company_closed_at
  ON public.deals (organization_id, company_id, closed_at);

ALTER TABLE public.deal_activities
  DROP CONSTRAINT IF EXISTS deal_activities_type_check_v5_next;

ALTER TABLE public.deal_activities
  ADD CONSTRAINT deal_activities_type_check_v5_next CHECK (
    activity_type IN (
      'deal_created', 'stage_change', 'amount_change', 'owner_change',
      'nurture_change', 'snooze_change', 'note', 'email_in', 'email_out',
      'linkedin_in', 'linkedin_out', 'task_created', 'task_completed',
      'sequence_stopped', 'linkedin_connected', 'decision', 'signal',
      'aged_close', 'call_connected'
    )
  ) NOT VALID;

ALTER TABLE public.deal_activities
  VALIDATE CONSTRAINT deal_activities_type_check_v5_next;

ALTER TABLE public.deal_activities
  DROP CONSTRAINT IF EXISTS deal_activities_type_check;

ALTER TABLE public.deal_activities
  RENAME CONSTRAINT deal_activities_type_check_v5_next TO deal_activities_type_check;

CREATE OR REPLACE FUNCTION public.deal_hold_companies(
  p_organization_id text,
  p_company_ids uuid[] DEFAULT NULL,
  p_now timestamptz DEFAULT now()
)
RETURNS TABLE (
  company_id uuid,
  deal_id uuid,
  deal_name text,
  stage text,
  closed_at timestamptz,
  free_on timestamptz,
  primary_contact_id uuid
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT d.company_id,
         d.id,
         d.name,
         d.stage,
         d.closed_at,
         CASE WHEN d.closed_at IS NULL THEN NULL ELSE d.closed_at + interval '365 days' END,
         d.primary_contact_id
  FROM public.deals d
  WHERE d.organization_id = p_organization_id
    AND (p_company_ids IS NULL OR d.company_id = ANY (p_company_ids))
    AND (
      d.closed_at IS NULL
      OR (
        d.closed_at > p_now - interval '365 days'
        AND NOT EXISTS (
          SELECT 1
          FROM public.deal_activities a
          WHERE a.deal_id = d.id
            AND a.activity_type = 'aged_close'
            AND a.created_at >= d.closed_at - interval '1 minute'
        )
      )
    )
  ORDER BY d.company_id, d.closed_at NULLS FIRST, d.updated_at DESC;
$$;

COMMENT ON FUNCTION public.deal_hold_companies(text, uuid[], timestamptz) IS
  '452: companies held from new plays by a deal: open, or closed within 365 days (a deal closed by age frees at once). Open deals first per company.';

REVOKE ALL ON FUNCTION public.deal_hold_companies(text, uuid[], timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.deal_hold_companies(text, uuid[], timestamptz) TO service_role;
