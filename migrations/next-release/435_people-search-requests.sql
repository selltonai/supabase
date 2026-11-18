-- ============================================================
-- Migration: 435_people-search-requests
-- Date:      2026-11-12
-- Purpose:   Roles added to a launched play (PLAN_RELEASE_PROD_ROLES_SEARCH_2026_11_12.md section 5, F1): the
--            search queue moves out of campaigns.metadata into its own two tables.
--            1. people_search_requests: one row per save that adds roles to a launched play (the added titles
--               only). The app's save route inserts it; Modal's people_research_cron reads the pending rows,
--               writes company_ids once (the play's approved companies when its first run starts) and closes it.
--            2. people_search_request_companies: one row per request and company. Modal claims a company by
--               inserting its row BEFORE the search is paid for; the primary key makes the claim atomic, so two
--               runs never pay for the same company. A release (spend limit, AI Ark unavailable) deletes the row.
--               done_at, outcome and people_found are written after the search.
--            Counters are counted from the rows, never stored. Nothing else writes these tables, so a write to
--            campaigns.metadata can no longer lose a claim (stage 2026-11-12: 2 of 4 counter updates lost).
-- Projects:  selltonai-database/supabase (owner); selltonai writes people_search_requests (save route);
--            selltonai-modal reads both and writes both (people_research_queue).
-- Contract:  Additive only. Service role only: RLS on with no policies, anon and authenticated hold no privileges.
--            campaigns.metadata.people_search_pending is no longer written or read (never on production).
--            Merge order: this, then Modal, then the app.
-- Depends:   public.organization, public.campaigns, public.companies.
-- Rollback:  rollback/435_people-search-requests.rollback.sql
-- ============================================================

SET LOCAL lock_timeout = '10s';

-- 1. The request ---------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.people_search_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  campaign_id uuid NOT NULL REFERENCES public.campaigns(id) ON DELETE CASCADE,
  titles text[] NOT NULL CHECK (cardinality(titles) > 0),
  requested_at timestamptz NOT NULL DEFAULT now(),
  requested_by text,
  company_ids uuid[],
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'done', 'excluded')),
  closed_at timestamptz,
  outcome text,
  CHECK ((status = 'pending') = (closed_at IS NULL))
);

COMMENT ON TABLE public.people_search_requests IS
  'Roles added to a launched play, one row per save (the added titles only). requested_by is the Clerk user id. company_ids: the play''s approved companies, written once by the first cron run; a company approved later takes the normal path, which already searches the play''s roles. status pending until every listed company has a people_search_request_companies row (done, outcome completed) or the play is on the rep''s existing connections or cancelled (excluded).';

CREATE INDEX IF NOT EXISTS people_search_requests_pending_idx
  ON public.people_search_requests (requested_at)
  WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS people_search_requests_campaign_idx
  ON public.people_search_requests (campaign_id);

REVOKE ALL ON TABLE public.people_search_requests FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.people_search_requests TO service_role;
ALTER TABLE public.people_search_requests ENABLE ROW LEVEL SECURITY;
-- No policies on purpose: the service role (Modal, the app's server routes) reads and writes; browser keys see nothing.

-- 2. One company of a request --------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.people_search_request_companies (
  request_id uuid NOT NULL REFERENCES public.people_search_requests(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  claimed_at timestamptz NOT NULL DEFAULT now(),
  done_at timestamptz,
  outcome text CHECK (outcome IN ('searched', 'failed', 'skipped')),
  people_found integer CHECK (people_found >= 0),
  PRIMARY KEY (request_id, company_id)
);

COMMENT ON TABLE public.people_search_request_companies IS
  'A company of a people_search_requests row. Inserted (the claim) before the search is paid for; the primary key makes the claim atomic. A row with done_at NULL is a claim whose run stopped: it stays taken and is never paid for again. A release deletes the row.';

CREATE INDEX IF NOT EXISTS people_search_request_companies_org_idx
  ON public.people_search_request_companies (organization_id);

REVOKE ALL ON TABLE public.people_search_request_companies FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.people_search_request_companies TO service_role;
ALTER TABLE public.people_search_request_companies ENABLE ROW LEVEL SECURITY;
-- No policies on purpose, as above.

-- Verify:
-- select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'people_search_requests';
--   -> 10
-- select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'people_search_request_companies';
--   -> 7
-- select relrowsecurity from pg_class where oid in ('public.people_search_requests'::regclass, 'public.people_search_request_companies'::regclass);
--   -> t, t
