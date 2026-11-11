-- ============================================================
-- Migration: 429_backoffice-cs-agent-economics (stage: next-release/429; renumber at promotion if 429 is taken)
-- Date:      2026-11-11
-- Purpose:   The backoffice's customer-success agent, its workspace economics snapshot: per workspace and per
--            person, per 4-week cycle, the revenue, the costs and the contribution, as the backoffice computes them
--            nightly.
--            1. workspace_economics: one row per workspace (user_id NULL) and one per person (user_id set) for each
--               cycle: seat, workspace and usage revenue, the usage's original cost, the provider cost of the
--               person's connections, the allocated infrastructure, the contribution and the margin percent, the
--               inputs the numbers came from, and when they were computed.
-- Projects:  selltonai-database/supabase (owner). backoffice is the only writer (its nightly job, upsert on the
--            unique key) and the only reader. selltonai-modal, selltonai, the mobile service and the engine: none.
-- Contract:  Additive. One new table; no other object changes. Service role only: RLS on with no policies, and anon
--            and authenticated get no table privileges.
--            Every number is computed by the backoffice; the table checks the arithmetic: contribution_usd is the
--            three revenues minus the four costs, exactly; margin_percent is NULL when the revenue is zero.
--            Revenue and cost columns are never negative. cycle_end is exclusive and after cycle_start.
--            One row per organization, person and cycle: unique on (organization_id, coalesce(user_id, ''),
--            cycle_start). user_key is that coalesce as a stored generated column, so the writer can name the key
--            in an upsert (PostgREST on_conflict=organization_id,user_key,cycle_start); it is never written.
--            Re-running a cycle replaces its row. usage, billing_settings, billing_invoices, billing_credits and
--            connection_ledger are read by the backoffice to fill it and are not changed here.
--            The backoffice treats a missing table as "feature not deployed", so this file and the backoffice build
--            can ship in either order. Application code: none must ship together with this file.
-- Depends:   public.organization (release_1.0.0).
-- Rollback:  rollback/429_backoffice-cs-agent-economics.rollback.sql
--
-- Definitions:
--   Cycle         4 weeks from the workspace's billing cycle anchor: [cycle_start, cycle_end).
--   Person        user_id: the Clerk user id (text, no key), as org_seats and linkedin_accounts hold it.
--   Revenue       seat_revenue_usd + workspace_revenue_usd + usage_revenue_usd.
--   Contribution  revenue - usage_original_cost_usd - provider_cost_usd - allocated_infra_usd.
--   Margin        contribution / revenue * 100, rounded to 2 decimals; NULL without revenue.
--   Inputs        a jsonb object: where each number came from (tables, settings keys, counts), for the reader.
-- ============================================================

-- organization is read on every request; fail fast instead of queueing behind a long transaction (the runner rolls
-- the file back and it can be re-run).
SET LOCAL lock_timeout = '10s';

CREATE TABLE IF NOT EXISTS public.workspace_economics (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  -- NULL: the whole workspace. Set: one person.
  user_id text CHECK (user_id IS NULL OR char_length(user_id) BETWEEN 1 AND 200),
  -- The unique key's person part: '' for the workspace row. Generated, never written.
  user_key text GENERATED ALWAYS AS (coalesce(user_id, '')) STORED,
  cycle_start date NOT NULL,
  cycle_end date NOT NULL,
  seat_revenue_usd numeric(12, 2) NOT NULL DEFAULT 0 CHECK (seat_revenue_usd >= 0),
  workspace_revenue_usd numeric(12, 2) NOT NULL DEFAULT 0 CHECK (workspace_revenue_usd >= 0),
  usage_revenue_usd numeric(12, 2) NOT NULL DEFAULT 0 CHECK (usage_revenue_usd >= 0),
  usage_original_cost_usd numeric(12, 2) NOT NULL DEFAULT 0 CHECK (usage_original_cost_usd >= 0),
  provider_cost_usd numeric(12, 2) NOT NULL DEFAULT 0 CHECK (provider_cost_usd >= 0),
  allocated_infra_usd numeric(12, 2) NOT NULL DEFAULT 0 CHECK (allocated_infra_usd >= 0),
  contribution_usd numeric(12, 2) NOT NULL DEFAULT 0,
  margin_percent numeric(9, 2),
  inputs jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(inputs) = 'object'),
  computed_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT workspace_economics_cycle_check CHECK (cycle_end > cycle_start),
  CONSTRAINT workspace_economics_contribution_check CHECK (
    contribution_usd = seat_revenue_usd + workspace_revenue_usd + usage_revenue_usd
                       - usage_original_cost_usd - provider_cost_usd - allocated_infra_usd
  ),
  CONSTRAINT workspace_economics_margin_check CHECK (
    margin_percent IS NULL OR seat_revenue_usd + workspace_revenue_usd + usage_revenue_usd > 0
  ),
  -- The nightly job's upsert key: unique on (organization_id, coalesce(user_id, ''), cycle_start).
  CONSTRAINT workspace_economics_cycle_unique UNIQUE (organization_id, user_key, cycle_start)
);

-- The latest workspace rows (the Billing column, the Today card, the agent's read).
CREATE INDEX IF NOT EXISTS workspace_economics_workspace_idx
  ON public.workspace_economics (organization_id, cycle_start DESC)
  WHERE user_id IS NULL;
CREATE INDEX IF NOT EXISTS workspace_economics_cycle_idx
  ON public.workspace_economics (cycle_start DESC)
  WHERE user_id IS NULL;

-- Access: the service role only ----------------------------------------------------------------------
-- Supabase grants new tables to anon and authenticated by default; take that away. RLS is on with no policies on
-- purpose: the backoffice reads and writes with the service role, and browser keys see nothing.

REVOKE ALL ON TABLE public.workspace_economics FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.workspace_economics TO service_role;

ALTER TABLE public.workspace_economics ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.workspace_economics IS
  'Backoffice customer-success agent: the economics of a workspace (user_id NULL) or one person (user_id set) in one 4-week cycle [cycle_start, cycle_end): seat, workspace and usage revenue, usage original cost, provider cost, allocated infrastructure, contribution (revenue minus the costs, checked) and margin percent (NULL without revenue), with the inputs the numbers came from. Filled nightly by the backoffice, upsert on (organization_id, user_key, cycle_start); user_key is coalesce(user_id, ''''), generated. Backoffice only.';

-- Fail the file if a browser key can still reach the table.
DO $$
BEGIN
  IF has_table_privilege('anon', 'public.workspace_economics', 'SELECT')
     OR has_table_privilege('authenticated', 'public.workspace_economics', 'SELECT')
     OR has_table_privilege('anon', 'public.workspace_economics', 'INSERT')
     OR has_table_privilege('authenticated', 'public.workspace_economics', 'INSERT')
     OR has_table_privilege('anon', 'public.workspace_economics', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.workspace_economics', 'UPDATE')
     OR has_table_privilege('anon', 'public.workspace_economics', 'DELETE')
     OR has_table_privilege('authenticated', 'public.workspace_economics', 'DELETE') THEN
    RAISE EXCEPTION '429: anon or authenticated can still read or write workspace_economics';
  END IF;
END $$;

-- Verify (read-only):
-- select relname, relrowsecurity from pg_class where relname = 'workspace_economics';
--   -> workspace_economics, true
-- select count(*) from pg_policies where tablename = 'workspace_economics';
--   -> 0
-- select has_table_privilege('anon', 'public.workspace_economics', 'SELECT'),            -- false
--        has_table_privilege('service_role', 'public.workspace_economics', 'INSERT');    -- true
