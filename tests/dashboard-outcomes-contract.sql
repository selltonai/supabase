-- KAN-322 FR-A11i (D70, D71, D87, D93): dashboard_outcomes_v1. Disposable database only.
-- Window [2026-09-24, 2026-10-01). Expected values are worked out by hand next to each fixture.
-- Ids: u(kind, n) = 00000000-0000-0000-000<kind>-<n, 12 digits>; kind 1 play, 2 company, 3 person, 4 deal.
CREATE FUNCTION pg_temp.u(kind int, n int) RETURNS uuid LANGUAGE sql IMMUTABLE AS
  $$ SELECT ('00000000-0000-0000-000' || kind || '-' || lpad(n::text, 12, '0'))::uuid $$;

INSERT INTO public.campaigns VALUES
  (pg_temp.u(1, 1), 'org_o', 'u_me', 'email'),
  (pg_temp.u(1, 2), 'org_o', 'u_me', 'linkedin'),
  (pg_temp.u(1, 3), 'org_o', 'u_other', 'mixed'),
  (pg_temp.u(1, 4), 'org_o', 'u_other', NULL),
  (pg_temp.u(1, 5), 'org_o', 'u_me', 'linkedin_first_email_fallback'),
  (pg_temp.u(1, 9), 'org_x', 'u_me', 'email');

-- Companies joining plays: K1 e1 in the window, K2 e1 before it, K3 e1 in it but held back, K4 the LinkedIn play
-- (a company link does not count there), K5 a play with no strategy (email), K6 LinkedIn-first (no company link),
-- K7 mixed before the window, K9 another workspace.
INSERT INTO public.campaign_companies (campaign_id, company_id, organization_id, created_at, blocked_by_icp) VALUES
  (pg_temp.u(1, 1), pg_temp.u(2, 1), 'org_o', '2026-09-25', false),
  (pg_temp.u(1, 1), pg_temp.u(2, 2), 'org_o', '2026-09-01', false),
  (pg_temp.u(1, 1), pg_temp.u(2, 3), 'org_o', '2026-09-26', true),
  (pg_temp.u(1, 2), pg_temp.u(2, 4), 'org_o', '2026-09-25', false),
  (pg_temp.u(1, 4), pg_temp.u(2, 5), 'org_o', '2026-09-27', NULL),
  (pg_temp.u(1, 5), pg_temp.u(2, 6), 'org_o', '2026-09-26', false),
  (pg_temp.u(1, 3), pg_temp.u(2, 7), 'org_o', '2026-09-20', false),
  (pg_temp.u(1, 9), pg_temp.u(2, 9), 'org_x', '2026-09-25', false),
  -- K8 joined e1 in the window, then the customer declined it in review (status 'rejected'): links no one.
  (pg_temp.u(1, 1), pg_temp.u(2, 8), 'org_o', '2026-09-26', false);
UPDATE public.campaign_companies SET status = 'rejected' WHERE company_id = pg_temp.u(2, 8);
UPDATE public.campaign_companies SET status = 'approved' WHERE company_id = pg_temp.u(2, 1);

INSERT INTO public.contacts (id, organization_id, created_at) VALUES
  (pg_temp.u(3, 1), 'org_o', '2026-09-01'),   -- P1 at K1: linked when K1 joined (09-25) -> new (team, me)
  (pg_temp.u(3, 2), 'org_o', '2026-09-26'),   -- P2 at K2: found later (09-26), K2 joined 09-01 -> new (team, me)
  (pg_temp.u(3, 3), 'org_o', '2026-08-01'),   -- P3 at K2: linked 09-01 -> not new
  (pg_temp.u(3, 4), 'org_o', '2026-09-01'),   -- P4 at K3 (held back) -> never linked
  (pg_temp.u(3, 5), 'org_o', '2026-09-01'),   -- P5 at K4 (LinkedIn play), not enrolled -> never linked
  (pg_temp.u(3, 6), 'org_o', '2026-09-01'),   -- P6 at K4, enrolled in l1 09-27 -> new (team, me)
  (pg_temp.u(3, 7), 'org_o', '2026-09-01'),   -- P7 at K5 (n1, a colleague's) linked 09-27 -> new (team only)
  (pg_temp.u(3, 8), 'org_o', '2026-09-01'),   -- P8 at K1 (09-25), but enrolled in l1 on 09-10 -> first link 09-10, not new
  (pg_temp.u(3, 9), 'org_o', '2026-09-01'),   -- P9 at K6 (LinkedIn-first: no company link), enrolled 10-01 (the end) -> not new
  (pg_temp.u(3, 10), 'org_o', '2026-09-01'),  -- P10 at K1 (09-25) and K5 (09-27) -> new once (team, me)
  (pg_temp.u(3, 12), 'org_o', '2026-09-01'),  -- P12 at K7 (mixed, 09-20) -> not new
  (pg_temp.u(3, 13), 'org_o', '2026-09-01'),  -- P13 at K7 (09-20), enrolled in my l1 09-28 -> new for me only
  (pg_temp.u(3, 14), 'org_o', '2026-09-01'),  -- P14 at K5 (n1, a colleague's) linked 09-27 -> new (team only)
  (pg_temp.u(3, 99), 'org_x', '2026-09-01'),  -- another workspace
  (pg_temp.u(3, 15), 'org_o', '2026-09-01'),  -- P15 at K8 (declined) -> never linked
  (pg_temp.u(3, 16), 'org_o', '2026-09-01'),  -- P16 at K1, a duplicate of P1 (canonical P1) -> P1 once
  (pg_temp.u(3, 17), 'org_o', '2026-09-01');  -- P17 at K2 (09-01): its duplicate P18, enrolled 09-27, is P17 -> not new
-- P18 is a duplicate of P17 (created later); P19 was enrolled but the person was deleted (no contacts row).
INSERT INTO public.contacts (id, organization_id, created_at, canonical_contact_id) VALUES
  (pg_temp.u(3, 18), 'org_o', '2026-09-27', pg_temp.u(3, 17));
UPDATE public.contacts SET canonical_contact_id = pg_temp.u(3, 1) WHERE id = pg_temp.u(3, 16);

INSERT INTO public.company_contacts (company_id, contact_id, organization_id) VALUES
  (pg_temp.u(2, 1), pg_temp.u(3, 1), 'org_o'), (pg_temp.u(2, 2), pg_temp.u(3, 2), 'org_o'),
  (pg_temp.u(2, 2), pg_temp.u(3, 3), 'org_o'), (pg_temp.u(2, 3), pg_temp.u(3, 4), 'org_o'),
  (pg_temp.u(2, 4), pg_temp.u(3, 5), 'org_o'), (pg_temp.u(2, 4), pg_temp.u(3, 6), 'org_o'),
  (pg_temp.u(2, 5), pg_temp.u(3, 7), 'org_o'), (pg_temp.u(2, 1), pg_temp.u(3, 8), 'org_o'),
  (pg_temp.u(2, 6), pg_temp.u(3, 9), 'org_o'), (pg_temp.u(2, 1), pg_temp.u(3, 10), 'org_o'),
  (pg_temp.u(2, 5), pg_temp.u(3, 10), 'org_o'), (pg_temp.u(2, 7), pg_temp.u(3, 12), 'org_o'),
  (pg_temp.u(2, 7), pg_temp.u(3, 13), 'org_o'), (pg_temp.u(2, 9), pg_temp.u(3, 99), 'org_x'),
  (pg_temp.u(2, 5), pg_temp.u(3, 14), 'org_o'),
  (pg_temp.u(2, 8), pg_temp.u(3, 15), 'org_o'), (pg_temp.u(2, 1), pg_temp.u(3, 16), 'org_o'),
  (pg_temp.u(2, 2), pg_temp.u(3, 17), 'org_o');

INSERT INTO public.campaign_contacts (campaign_id, contact_id, organization_id, created_at) VALUES
  (pg_temp.u(1, 2), pg_temp.u(3, 6), 'org_o', '2026-09-27'),
  (pg_temp.u(1, 2), pg_temp.u(3, 8), 'org_o', '2026-09-10'),
  (pg_temp.u(1, 5), pg_temp.u(3, 9), 'org_o', '2026-10-01'),
  (pg_temp.u(1, 2), pg_temp.u(3, 13), 'org_o', '2026-09-28'),
  (pg_temp.u(1, 2), pg_temp.u(3, 18), 'org_o', '2026-09-27'),
  (pg_temp.u(1, 2), pg_temp.u(3, 19), 'org_o', '2026-09-27');

-- Deals and their stage history.
INSERT INTO public.deals VALUES
  (pg_temp.u(4, 1), 'org_o', pg_temp.u(3, 1), NULL, 'u_me', 'MEETING_BOOKED', NULL, 'USD', NULL),
  (pg_temp.u(4, 2), 'org_o', pg_temp.u(3, 1), NULL, 'u_me', 'MEETING_BOOKED', NULL, 'USD', NULL),
  (pg_temp.u(4, 3), 'org_o', pg_temp.u(3, 2), NULL, 'u_other', 'PRESENTATION', NULL, 'USD', NULL),
  (pg_temp.u(4, 4), 'org_o', pg_temp.u(3, 3), NULL, 'u_other', 'MEETING_BOOKED', NULL, 'USD', NULL),
  (pg_temp.u(4, 5), 'org_o', NULL, pg_temp.u(3, 7), 'u_me', 'MEETING_BOOKED', NULL, 'USD', NULL),
  (pg_temp.u(4, 6), 'org_o', NULL, NULL, 'u_me', 'WON', 1000, 'EUR', '2026-09-27'),
  (pg_temp.u(4, 7), 'org_o', pg_temp.u(3, 2), NULL, 'u_other', 'WON', 500, 'USD', '2026-09-28'),
  (pg_temp.u(4, 8), 'org_o', pg_temp.u(3, 13), NULL, 'u_me', 'WON', NULL, 'USD', '2026-09-29'),
  (pg_temp.u(4, 9), 'org_o', NULL, NULL, 'u_me', 'WON', 700, 'USD', '2026-10-01'),
  (pg_temp.u(4, 10), 'org_o', pg_temp.u(3, 10), NULL, 'u_other', 'LOST', 900, 'USD', '2026-09-28'),
  (pg_temp.u(4, 11), 'org_o', pg_temp.u(3, 8), NULL, 'u_me', 'WON', 2000, 'EUR', '2026-09-26'),
  (pg_temp.u(4, 12), 'org_o', pg_temp.u(3, 12), NULL, 'u_other', 'MEETING_REQUESTED', NULL, 'USD', NULL),
  (pg_temp.u(4, 13), 'org_o', NULL, pg_temp.u(3, 1), 'u_other', 'MEETING_BOOKED', NULL, 'USD', NULL),
  (pg_temp.u(4, 99), 'org_x', pg_temp.u(3, 99), NULL, 'u_me', 'WON', 300, 'GBP', '2026-09-27');

INSERT INTO public.deal_activities (deal_id, organization_id, activity_type, metadata, created_at) VALUES
  -- D1 (P1, mine): created at Lead, booked 09-25 -> a meeting.
  (pg_temp.u(4, 1), 'org_o', 'deal_created', '{"stage":"LEAD"}', '2026-09-01'),
  (pg_temp.u(4, 1), 'org_o', 'stage_change', '{"from":"LEAD","to":"MEETING_BOOKED"}', '2026-09-25'),
  -- D2 (P1 again, mine): created at Meeting booked 09-26 -> the same person, counted once.
  (pg_temp.u(4, 2), 'org_o', 'deal_created', '{"stage":"MEETING_BOOKED"}', '2026-09-26'),
  -- D3 (P2, a colleague's): requested, then straight to Presentation 09-27 -> a meeting (it passed Meeting booked).
  (pg_temp.u(4, 3), 'org_o', 'deal_created', '{"stage":"LEAD"}', '2026-09-01'),
  (pg_temp.u(4, 3), 'org_o', 'stage_change', '{"from":"LEAD","to":"MEETING_REQUESTED"}', '2026-09-25'),
  (pg_temp.u(4, 3), 'org_o', 'stage_change', '{"from":"MEETING_REQUESTED","to":"PRESENTATION"}', '2026-09-27'),
  -- D4 (P3): booked 09-10, back to Lead, booked again 09-26 -> first reached before the window, not a meeting.
  (pg_temp.u(4, 4), 'org_o', 'stage_change', '{"from":"LEAD","to":"MEETING_BOOKED"}', '2026-09-10'),
  (pg_temp.u(4, 4), 'org_o', 'stage_change', '{"from":"MEETING_BOOKED","to":"LEAD"}', '2026-09-20'),
  (pg_temp.u(4, 4), 'org_o', 'stage_change', '{"from":"LEAD","to":"MEETING_BOOKED"}', '2026-09-26'),
  -- D5 (no primary, stage contact P7, mine): booked 09-30 -> a meeting, person P7.
  (pg_temp.u(4, 5), 'org_o', 'stage_change', '{"from":"MEETING_REQUESTED","to":"MEETING_BOOKED"}', '2026-09-30'),
  -- D6 (no contact, mine): created at Won 09-27 -> a meeting (the deal is the person) and won, 1000 EUR.
  (pg_temp.u(4, 6), 'org_o', 'deal_created', '{"stage":"WON"}', '2026-09-27'),
  -- D7 (P2, a colleague's): to Won 09-28 -> P2 already counted (D3); won, 500 USD.
  (pg_temp.u(4, 7), 'org_o', 'stage_change', '{"from":"AGREEMENT","to":"WON"}', '2026-09-28'),
  -- D8 (P13, mine): to Won 09-29 without an amount -> a meeting (P13); won, no value.
  (pg_temp.u(4, 8), 'org_o', 'stage_change', '{"from":"LEAD","to":"WON"}', '2026-09-29'),
  -- D9 (mine): won at the window's end -> outside it.
  (pg_temp.u(4, 9), 'org_o', 'stage_change', '{"from":"AGREEMENT","to":"WON"}', '2026-10-01'),
  -- D10 (P10, a colleague's): booked 09-25, then lost -> a meeting; not won.
  (pg_temp.u(4, 10), 'org_o', 'stage_change', '{"from":"LEAD","to":"MEETING_BOOKED"}', '2026-09-25'),
  (pg_temp.u(4, 10), 'org_o', 'stage_change', '{"from":"MEETING_BOOKED","to":"LOST"}', '2026-09-28'),
  -- D11 (P8, mine): booked 09-01, won 09-26, 2000 EUR -> won; not a meeting in the window.
  (pg_temp.u(4, 11), 'org_o', 'stage_change', '{"from":"LEAD","to":"MEETING_BOOKED"}', '2026-09-01'),
  (pg_temp.u(4, 11), 'org_o', 'stage_change', '{"from":"MEETING_BOOKED","to":"WON"}', '2026-09-26'),
  -- A note and an amount change never count as a stage.
  (pg_temp.u(4, 3), 'org_o', 'note', '{"to":"MEETING_BOOKED"}', '2026-09-25'),
  -- D12 (P12, a colleague's): only requested 09-26, and a note saying "to MEETING_BOOKED" 09-27 -> not a meeting.
  (pg_temp.u(4, 12), 'org_o', 'stage_change', '{"from":"LEAD","to":"MEETING_REQUESTED"}', '2026-09-26'),
  (pg_temp.u(4, 12), 'org_o', 'note', '{"to":"MEETING_BOOKED"}', '2026-09-27'),
  (pg_temp.u(4, 12), 'org_o', 'amount_change', '{"to":"WON"}', '2026-09-27'),
  -- D13 (no primary, stage contact P1, a colleague's): booked 09-28 -> P1 again, counted once.
  (pg_temp.u(4, 13), 'org_o', 'stage_change', '{"from":"LEAD","to":"MEETING_BOOKED"}', '2026-09-28'),
  -- Another workspace.
  (pg_temp.u(4, 99), 'org_x', 'stage_change', '{"from":"LEAD","to":"MEETING_BOOKED"}', '2026-09-25');

DO $$
DECLARE r record;
BEGIN
  -- All team: new people P1 (and its duplicate P16), P2, P6, P7, P10, P14 = 6 (not P15: declined; not P17/P18: P17
  -- linked 09-01; not P19: deleted); meetings P1 (D1, D2, D13), P2, P7, D6, P13, P10 = 6 (not D12);
  -- won D6, D7, D8, D11 = 4, EUR 3000, USD 500.
  SELECT * INTO r FROM public.dashboard_outcomes_v1('org_o', '2026-09-24', '2026-10-01');
  IF (r.new_people, r.meetings, r.deals_won) IS DISTINCT FROM (6::bigint, 6::bigint, 4::bigint) THEN
    RAISE EXCEPTION 'team counts: got % % %', r.new_people, r.meetings, r.deals_won;
  END IF;
  IF r.won_value IS DISTINCT FROM '{"EUR": 3000.00, "USD": 500.00}'::jsonb THEN
    RAISE EXCEPTION 'team value: got %', r.won_value;
  END IF;

  -- Just me (u_me): new people P1, P2, P6, P10, P13 = 5 (not P7 or P14: a colleague's play); meetings on my deals P1, P7, D6,
  -- P13 = 4; won D6, D8, D11 = 3, EUR 3000.
  SELECT * INTO r FROM public.dashboard_outcomes_v1('org_o', '2026-09-24', '2026-10-01', 'u_me');
  IF (r.new_people, r.meetings, r.deals_won) IS DISTINCT FROM (5::bigint, 4::bigint, 3::bigint) THEN
    RAISE EXCEPTION 'mine counts: got % % %', r.new_people, r.meetings, r.deals_won;
  END IF;
  IF r.won_value IS DISTINCT FROM '{"EUR": 3000.00}'::jsonb THEN
    RAISE EXCEPTION 'mine value: got %', r.won_value;
  END IF;
  -- (The set for me differs from the team's: P13 in, P7 and P14 out.)

  -- The window before: new people P3 and P17 (09-01), P8 (09-10), P12 and P13 for the team (09-20) = 5;
  -- meetings D4 (P3, 09-10), D11 (P8, 09-01) = 2; nothing won.
  SELECT * INTO r FROM public.dashboard_outcomes_v1('org_o', '2026-08-24', '2026-09-24');
  IF (r.new_people, r.meetings, r.deals_won, r.won_value) IS DISTINCT FROM (5::bigint, 2::bigint, 0::bigint, '{}'::jsonb) THEN
    RAISE EXCEPTION 'previous window: got % % % %', r.new_people, r.meetings, r.deals_won, r.won_value;
  END IF;

  -- A workspace with nothing: one row of zeros, never no row.
  SELECT * INTO r FROM public.dashboard_outcomes_v1('org_empty', '2026-09-24', '2026-10-01');
  IF NOT FOUND OR (r.new_people, r.meetings, r.deals_won, r.won_value) IS DISTINCT FROM (0::bigint, 0::bigint, 0::bigint, '{}'::jsonb) THEN
    RAISE EXCEPTION 'empty workspace: got % % % %', r.new_people, r.meetings, r.deals_won, r.won_value;
  END IF;

  -- The other workspace sees only its own.
  SELECT * INTO r FROM public.dashboard_outcomes_v1('org_x', '2026-09-24', '2026-10-01');
  IF (r.new_people, r.meetings, r.deals_won, r.won_value) IS DISTINCT FROM (1::bigint, 1::bigint, 1::bigint, '{"GBP": 300.00}'::jsonb) THEN
    RAISE EXCEPTION 'other workspace: got % % % %', r.new_people, r.meetings, r.deals_won, r.won_value;
  END IF;

  -- Only the service role may call it (Supabase grants new functions to anon and authenticated by default).
  IF has_function_privilege('anon', 'public.dashboard_outcomes_v1(text, timestamptz, timestamptz, text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.dashboard_outcomes_v1(text, timestamptz, timestamptz, text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.dashboard_outcomes_v1(text, timestamptz, timestamptz, text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'grants: anon or authenticated can call it, or service_role cannot';
  END IF;
  RAISE NOTICE 'dashboard_outcomes_v1 contract: ok';
END $$;
