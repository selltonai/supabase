-- ============================================================
-- Migration: 418_learning-loop-tables
-- Date:      2026-11-04
-- Purpose:   The learning loop (PLAN_WRITER_ENGINE_NEXT_2026_11_04.md section 3, lane L), rings L1 and L2.
--            1. learning_reports: one row per workspace and ISO week, the weekly outcome report (L1) as the Monday
--               job built it and who it was emailed to. Read by the app's play Statistics tab.
--            2. learning_frame_outcomes: per workspace, play, step and opener frame, what the play's sent messages
--               got back to date (sent, replies, positive replies, meetings, held, edited). Written by the same
--               Monday job; read by the writer's frame choice (L2, behind OUTREACH_WRITER_LEARN_FRAMES, default off).
-- Projects:  selltonai-database/supabase (owner); selltonai-modal writes both (learning_report_job) and reads the
--            second (learning_frames); selltonai reads the first (api/tasks/outcome-report).
-- Contract:  Additive only. Every row carries its organization_id: learning never crosses workspaces. Service role
--            only (no policies). The Modal code runs without these tables (it logs and goes on), so the order of the
--            deploys does not matter. Rollback: rollback/418_learning-loop-tables.rollback.sql
-- ============================================================

CREATE TABLE IF NOT EXISTS public.learning_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  week text NOT NULL,
  period_start timestamptz NOT NULL,
  period_end timestamptz NOT NULL,
  report jsonb NOT NULL,
  recipients jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT learning_reports_org_week_unique UNIQUE (organization_id, week)
);

COMMENT ON TABLE public.learning_reports IS
  'Learning loop L1: one workspace''s weekly outcome report (per play and opener frame: sent, replies, positive, meetings, held, edited; three best and three worst messages). Written by selltonai-modal learning_report_job every Monday.';

CREATE INDEX IF NOT EXISTS learning_reports_org_created_idx
  ON public.learning_reports (organization_id, created_at DESC);

ALTER TABLE public.learning_reports ENABLE ROW LEVEL SECURITY;
-- No policies on purpose: the service role (Modal, the app's server routes) reads and writes; browser keys see nothing.

CREATE TABLE IF NOT EXISTS public.learning_frame_outcomes (
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  campaign_id uuid NOT NULL REFERENCES public.campaigns(id) ON DELETE CASCADE,
  step text NOT NULL,
  framework text NOT NULL,
  sent integer NOT NULL DEFAULT 0,
  replied integer NOT NULL DEFAULT 0,
  positive integer NOT NULL DEFAULT 0,
  meetings integer NOT NULL DEFAULT 0,
  held integer NOT NULL DEFAULT 0,
  edited integer NOT NULL DEFAULT 0,
  computed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (organization_id, campaign_id, step, framework)
);

COMMENT ON TABLE public.learning_frame_outcomes IS
  'Learning loop L1/L2: per workspace, play, step and opener frame, what the sent messages got back to date. Replies the classifier marked as not a reply (out of office, automated, bounces) never count. Read by the writer''s frame choice only for the same organization and play, and only at 30 or more sent per frame (D5).';

CREATE INDEX IF NOT EXISTS learning_frame_outcomes_campaign_idx
  ON public.learning_frame_outcomes (campaign_id, step);

ALTER TABLE public.learning_frame_outcomes ENABLE ROW LEVEL SECURITY;
-- No policies on purpose, as above.
