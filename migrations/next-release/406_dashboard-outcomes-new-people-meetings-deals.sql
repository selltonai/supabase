-- ============================================================
-- Migration: dashboard-outcomes-new-people-meetings-deals (stage: next-release/406; the promotion keeps the number)
-- Date:      2026-10-19
-- Purpose:   KAN-322 FR-A11i: the dashboard's outcomes in one read, for one window:
--              new people (A8, work order D70 and D87), meetings booked and deals won (FR-C4c, D71).
-- Projects:  selltonai-database/supabase (owner); reader: selltonai GET /api/dashboard/intelligence, behind
--            NEXT_PUBLIC_REFRESH_DASHBOARD_NUMBERS_ENABLED (src/features/dashboard/outcomeNumbers.ts).
-- Contract:  One new read-only function. No table, column, constraint, RLS, trigger, cron or queue change.
--            Safe to drop: the reader shows "-" and the dashboard's "Some numbers could not load" notice without it.
-- Depends:   public.campaigns (user_id = owner, channel_strategy), public.campaign_companies, public.company_contacts,
--            public.contacts, public.campaign_contacts, public.deals and public.deal_activities (349, 367).
--
-- Definitions:
--   New person (D70, D87): a person whose FIRST link to any play in scope falls in [p_start, p_end), counted once
--     across channels and plays.
--     - A play that sends email from the start (channel_strategy NULL, 'email', 'mixed' or 'multi-channel') links a
--       person through their company: at the LATER of the company joining the play (campaign_companies.created_at)
--       and the person being created (contacts.created_at). Companies the play holds back (campaign_companies
--       .blocked_by_icp) link no one: Sellton never reaches out to them.
--     - Every play links the people it enrols (campaign_contacts.created_at): the LinkedIn plays' people.
--   Meeting (D71, D93): a deal that first reached Meeting booked or a later stage (Presentation, Negotiation,
--     Agreement, Won) in the window, from its stage history (deal_activities: 'stage_change' metadata.to, or the
--     stage it was created at, 'deal_created' metadata.stage). A deal that goes back and forth counts once, at its
--     first time. Counted once per person (the deal's primary contact, else its stage contact, else the deal).
--   Deal won (D71): a deal at Won whose closed_at falls in the window; its value is the sum of the known amounts, by
--     currency (deals.amount, deals.currency).
--   "Just me" (p_user_id): new people = the plays I own (campaigns.user_id), as the dashboard scopes plays; meetings
--     and deals = the deals I own (deals.owner_user_id).
--
-- Returns one row:
--   new_people bigint, meetings bigint, deals_won bigint,
--   won_value jsonb  -- {"EUR": 12000.00, "USD": 3000.00}; {} when no won deal has an amount
--
-- Performance: one pass over the scoped plays' links (indexes campaign_companies(campaign_id),
-- company_contacts(company_id), contacts pkey, campaign_contacts(campaign_id)); deals by
-- idx_deals_org_owner_stage / idx_deals_org_stage_updated; the stage history by idx_deal_activities_deal_created.
-- STABLE, SECURITY INVOKER, service_role only. Measured on a synthetic workspace (tests/run-dashboard-outcomes-contract.sh).
--
-- Rollback: next-release/rollback/406-407_dashboard-outcomes-and-people-v2.rollback.sql
-- ============================================================

CREATE OR REPLACE FUNCTION public.dashboard_outcomes_v1(
  p_org_id text,
  p_start timestamptz,
  p_end timestamptz,
  p_user_id text DEFAULT NULL
)
RETURNS TABLE (
  new_people bigint,
  meetings bigint,
  deals_won bigint,
  won_value jsonb
)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = public
AS $$
  WITH scoped_campaigns AS (
    SELECT c.id, c.channel_strategy
    FROM public.campaigns c
    WHERE c.organization_id = p_org_id
      AND (p_user_id IS NULL OR c.user_id = p_user_id)
  ),
  links AS (
    -- Email plays: through the company, at the later of the company joining and the person being created (D87).
    SELECT cct.contact_id AS person, GREATEST(cc.created_at, ct.created_at) AS linked_at
    FROM scoped_campaigns s
    JOIN public.campaign_companies cc
      ON cc.campaign_id = s.id
     AND COALESCE(cc.blocked_by_icp, false) = false
    JOIN public.company_contacts cct
      ON cct.company_id = cc.company_id
     AND cct.organization_id = p_org_id
    JOIN public.contacts ct
      ON ct.id = cct.contact_id
     AND ct.organization_id = p_org_id
    WHERE COALESCE(s.channel_strategy, 'email') IN ('email', 'mixed', 'multi-channel')
    UNION ALL
    -- Every play: the people it enrols (the LinkedIn plays' people).
    SELECT cp.contact_id, cp.created_at
    FROM scoped_campaigns s
    JOIN public.campaign_contacts cp ON cp.campaign_id = s.id
    WHERE cp.contact_id IS NOT NULL
  ),
  first_links AS (
    SELECT person, MIN(linked_at) AS first_linked_at FROM links GROUP BY person
  ),
  scoped_deals AS (
    SELECT d.id, d.stage, d.closed_at, d.amount, d.currency,
           COALESCE(d.primary_contact_id::text, d.stage_contact_id::text, 'deal:' || d.id::text) AS person
    FROM public.deals d
    WHERE d.organization_id = p_org_id
      AND (p_user_id IS NULL OR d.owner_user_id = p_user_id)
  ),
  meeting_reached AS (
    SELECT a.deal_id, MIN(a.created_at) AS reached_at
    FROM scoped_deals d
    JOIN public.deal_activities a ON a.deal_id = d.id
    WHERE (a.activity_type = 'stage_change'
           AND a.metadata->>'to' IN ('MEETING_BOOKED', 'PRESENTATION', 'NEGOTIATION', 'AGREEMENT', 'WON'))
       OR (a.activity_type = 'deal_created'
           AND a.metadata->>'stage' IN ('MEETING_BOOKED', 'PRESENTATION', 'NEGOTIATION', 'AGREEMENT', 'WON'))
    GROUP BY a.deal_id
  ),
  won AS (
    SELECT d.amount, d.currency
    FROM scoped_deals d
    WHERE d.stage = 'WON'
      AND d.closed_at >= p_start
      AND d.closed_at < p_end
  )
  SELECT
    (SELECT count(*) FROM first_links WHERE first_linked_at >= p_start AND first_linked_at < p_end),
    (SELECT count(DISTINCT d.person)
       FROM meeting_reached m
       JOIN scoped_deals d ON d.id = m.deal_id
      WHERE m.reached_at >= p_start AND m.reached_at < p_end),
    (SELECT count(*) FROM won),
    COALESCE((SELECT jsonb_object_agg(currency, total)
                FROM (SELECT currency, SUM(amount) AS total FROM won WHERE amount IS NOT NULL GROUP BY currency) v),
             '{}'::jsonb)
$$;

REVOKE ALL ON FUNCTION public.dashboard_outcomes_v1(text, timestamptz, timestamptz, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dashboard_outcomes_v1(text, timestamptz, timestamptz, text) TO service_role;

COMMENT ON FUNCTION public.dashboard_outcomes_v1(text, timestamptz, timestamptz, text) IS
  'KAN-322 FR-A11i (D70, D71, D87, D93): new people (first link to a play in scope), meetings (deals first reaching Meeting booked or later, once per person) and won deals with their value by currency, in one window.';

-- Verify (read-only, any database the migration ran on):
-- SELECT proname, has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_exec,
--        has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_exec
--   FROM pg_proc p WHERE proname = 'dashboard_outcomes_v1';            -- expect one row, false, false
-- SELECT * FROM public.dashboard_outcomes_v1('<org>', now() - interval '30 days', now());
