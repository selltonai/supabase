-- ============================================================
-- Migration: 431_workspace-switch (stage: next-release/431; renumber at promotion if 431 is taken)
-- Date:      2026-11-11
-- Status:    DRAFT by lane E (the engine) for Zoran's review (card D1-2). Not applied anywhere.
-- Purpose:   The switch that says which workspaces the new engine serves: one row per organization.
--            engine_on      the new engine serves this workspace
--            old_engine_on  the phone's service (the old engine) still serves it
--            synthetic      the workspace is test data and can never send
--            switched_at    when the row last changed; note: why
-- Projects:  sellton-new-engine (reads it; it replaces the engine's SELLTON_PLAYS_ORGS list once it drives stage,
--            E-M0 step 3). selltonai-mobile, selltonai, selltonai-modal, backoffice: none.
-- Contract:  Additive. One new table; nothing else changes. Service role only: RLS on with no policies, and anon and
--            authenticated get no table privileges (as 428). Application code that must ship with it: none.
-- Seed:      NOT included. The card says "seeded with the two switched workspaces"; their ids are not known to lane E.
--            Zoran: fill in the commented block at the end, or insert them by hand when applying.
-- Depends:   public.organization.
-- Rollback:  rollback/431_workspace-switch.rollback.sql
-- Re-apply:  idempotent; a second run changes nothing (the seed block, if filled in, is ON CONFLICT DO NOTHING).
-- ============================================================

SET LOCAL lock_timeout = '10s';

CREATE TABLE IF NOT EXISTS public.workspace_switch (
  organization_id text PRIMARY KEY REFERENCES public.organization(id) ON DELETE CASCADE,
  engine_on boolean NOT NULL DEFAULT false,
  old_engine_on boolean NOT NULL DEFAULT false,
  synthetic boolean NOT NULL DEFAULT false,
  switched_at timestamptz NOT NULL DEFAULT now(),
  note text
);

-- Access: the service role only (the same pattern as 428). RLS is on with no policies on purpose.
REVOKE ALL ON TABLE public.workspace_switch FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.workspace_switch TO service_role;
ALTER TABLE public.workspace_switch ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.workspace_switch IS
  'Which workspaces the new engine serves: engine_on (new engine), old_engine_on (the phone''s service), synthetic (test data, never sends). Service role only.';

-- ---- SEED: FOR ZORAN TO FILL IN (lane E does not know the two organization ids; none are invented) ----------
-- Uncomment, put the two real organization ids in, and check which of engine_on / old_engine_on / synthetic each needs.
--
-- INSERT INTO public.workspace_switch (organization_id, engine_on, old_engine_on, synthetic, note) VALUES
--   ('<ORGANIZATION_ID_1>', true, false, false, '<note>'),
--   ('<ORGANIZATION_ID_2>', true, false, false, '<note>')
-- ON CONFLICT (organization_id) DO NOTHING;

-- Verify (read-only).
SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname = 'public' AND tablename = 'workspace_switch';
