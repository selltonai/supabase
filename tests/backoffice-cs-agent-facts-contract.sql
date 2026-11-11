-- Migration 423's contract. Run by tests/run-backoffice-cs-agent-facts-contract.sh on a disposable database, in one
-- transaction: now() is the same instant in the fixtures and in both functions.

-- Fixtures: a web workspace, a phone-first workspace, an empty workspace and a deleted one. ------------------------
INSERT INTO public."user" (id, email) VALUES
  ('u_w1', 'owner@webco.test'), ('u_w2', 'second@webco.test'), ('u_w3', 'third@webco.test'),
  ('u_left', 'left@webco.test'), ('u_p1', 'owner@phoneco.test'), ('u_p2', 'second@phoneco.test'),
  ('u_g1', 'owner@goneco.test'), ('user_support', 'support@staff.test');

INSERT INTO public.organization (id, name, created_at, signup_source, mobile, onboarding_status, activation_paid_at, tier) VALUES
  ('org_web', 'Web Co', now() - interval '60 days', NULL, NULL, 'launched', now() - interval '50 days', 'tier1'),
  ('org_phone', 'Phone Co', now() - interval '15 days', 'mobile', '{"enabled": true}', 'pending', NULL, 'starter'),
  ('org_quiet', 'Quiet Co', now() - interval '2 days', 'web', 'null', 'pending', NULL, 'starter');
INSERT INTO public.organization (id, name, deleted) VALUES ('org_gone', 'Gone Co', true);

-- Members. u_left has a profile row in org_web (consent, the most recent last_seen_at) but is no longer a member.
INSERT INTO public.user_organizations (user_id, organization_id, role) VALUES
  ('u_w1', 'org_web', 'org:admin'), ('u_w2', 'org_web', 'admin'), ('u_w3', 'org_web', 'org:member'),
  ('u_p1', 'org_phone', 'org:owner'), ('u_p2', 'org_phone', 'org:member'), ('u_g1', 'org_gone', 'org:admin');
INSERT INTO public.user_profiles (user_id, organization_id) VALUES
  ('u_w1', 'org_web'), ('u_w2', 'org_web'), ('u_w3', 'org_web'), ('u_left', 'org_web'), ('u_p1', 'org_phone'), ('u_g1', 'org_gone');
UPDATE public.user_profiles SET last_seen_at = now() - interval '1 hour', consent_marketing_at = now() - interval '10 days'
  WHERE user_id = 'u_w1';
UPDATE public.user_profiles SET last_seen_at = now() - interval '3 days', consent_marketing_at = now() - interval '1 day'
  WHERE user_id = 'u_w2';
UPDATE public.user_profiles SET last_seen_at = now() - interval '5 minutes', consent_marketing_at = now() - interval '2 days'
  WHERE user_id = 'u_left';
UPDATE public.user_profiles SET last_seen_at = now() - interval '2 hours' WHERE user_id = 'u_p1';
UPDATE public.user_profiles SET consent_marketing_at = now() WHERE user_id = 'u_g1';

-- Settings. org_phone: a zone this server does not know (read as UTC) and one send day, tomorrow in UTC.
INSERT INTO public.organization_settings (organization_id, onboarding_completed_at, timezone, send_window_start, send_window_end, send_days) VALUES
  ('org_web', now() - interval '40 days', 'Europe/Berlin', 450, 1080, ARRAY[1, 2, 3, 4, 5]::smallint[]),
  ('org_phone', NULL, 'Mars/Olympus', 0, 1440,
   ARRAY[((extract(dow FROM now() AT TIME ZONE 'UTC')::integer + 1) % 7)]::smallint[]);

-- Billing.
INSERT INTO public.billing_customers (organization_id, card_brand, card_last4, status, monthly_spend_limit, billing_started_at, trial_started_at, trial_ends_at) VALUES
  ('org_web', 'visa', '4242', 'active', 200, now() - interval '35 days', now() - interval '45 days', now() - interval '38 days'),
  ('org_phone', NULL, '', 'active', NULL, NULL, NULL, NULL);
INSERT INTO public.billing_credits (organization_id, kind, trial_product, amount_usd, remaining_usd, expires_at, created_by) VALUES
  ('org_web', 'trial', 'web', 40, 0, now() - interval '38 days', 'staff_1'),
  ('org_web', 'manual', NULL, 25, 10, NULL, 'staff_1'),
  ('org_web', 'referral', NULL, 5, 5, now() - interval '1 day', 'staff_1');
INSERT INTO public.billing_invoices (organization_id, period_start, period_end, total, status, paid_at, created_at) VALUES
  ('org_web', now() - interval '14 days', now() - interval '7 days', 30, 'paid', now() - interval '7 days', now() - interval '7 days'),
  ('org_web', now() - interval '7 days', now() - interval '1 day', 12.50, 'sent', NULL, now() - interval '1 day'),
  ('org_web', now() - interval '1 day', now(), 99, 'draft', NULL, now());
INSERT INTO public.discount_codes (code, discount_type, discount_value, applies_to, created_by) VALUES
  ('SEATS20', 'percentage', 20, 'seats', 'staff_1'), ('ACT100', 'fixed_amount', 100, 'activation', 'staff_1');
INSERT INTO public.discount_code_redemptions (code, organization_id, redeemed_by) VALUES
  ('SEATS20', 'org_web', 'u_w1'), ('ACT100', 'org_web', 'u_w1');
INSERT INTO public.usage (organization_id, session_id, provider, sellton_cost, created_at) VALUES
  ('org_web', 's', 'openai', 1.50, now() - interval '1 day'),
  ('org_web', 's', 'openai', 2.25, now() - interval '10 days'),
  ('org_web', 's', 'openai', 4.00, now() - interval '20 days'),
  ('org_web', 's', 'openai', 100.00, now() - interval '40 days');

-- Seats.
INSERT INTO public.org_seats (organization_id, clerk_user_id, clerk_membership_id, user_email, seat_status, is_billable, seat_type,
                              mobile_trial_started_at, mobile_trial_ends_at, mobile_activated_at) VALUES
  ('org_web', 'u_w1', 'm_w1', 'owner@webco.test', 'active', true, 'customer', NULL, NULL, NULL),
  ('org_web', 'u_w2', 'm_w2', 'second@webco.test', 'active', false, 'internal_support', NULL, NULL, NULL),
  ('org_web', 'u_w3', 'm_w3', 'third@webco.test', 'terminated', true, 'customer', NULL, NULL, NULL),
  ('org_phone', 'u_p1', 'm_p1', 'owner@phoneco.test', 'active', true, 'customer',
   now() - interval '10 days', now() - interval '3 days', now() - interval '3 days'),
  ('org_phone', 'u_p2', 'm_p2', 'second@phoneco.test', 'active', true, 'customer',
   now() - interval '2 days', now() + interval '5 days', NULL);

-- Plays. org_phone has 21, to check the 20-item cap and the order.
INSERT INTO public.campaigns (id, organization_id, user_id, name, status, created_at, started_at, launched_at) VALUES
  ('00000000-0000-0000-0000-0000000000c1', 'org_web', 'u_w1', 'Spring outreach', 'active', now() - interval '30 days', NULL, now() - interval '28 days'),
  ('00000000-0000-0000-0000-0000000000c2', 'org_web', 'u_w1', 'Summer outreach', 'active', now() - interval '20 days', now() - interval '18 days', NULL),
  ('00000000-0000-0000-0000-0000000000c3', 'org_web', 'u_w2', 'Autumn draft', 'draft', now() - interval '5 days', NULL, NULL),
  ('00000000-0000-0000-0000-0000000000c4', 'org_web', 'u_w1', 'Old cancelled', 'cancelled', now() - interval '60 days', NULL, NULL),
  ('00000000-0000-0000-0000-0000000000c5', 'org_web', 'u_w1', 'Old finished', 'completed', now() - interval '100 days', NULL, now() - interval '95 days'),
  ('00000000-0000-0000-0000-0000000000d1', 'org_gone', 'u_g1', 'Gone play', 'active', now() - interval '1 day', NULL, NULL);
INSERT INTO public.campaigns (organization_id, user_id, name, status, created_at)
SELECT 'org_phone', 'u_p1', 'Phone play ' || g, 'draft', now() - g * interval '1 hour'
FROM generate_series(1, 21) g;

-- A prospect. Nothing about this person may reach the facts.
INSERT INTO public.contacts (id, organization_id, name, email) VALUES
  ('00000000-0000-0000-0000-0000000000a1', 'org_web', 'Jane Prospect', 'jane.prospect@acme-prospect.test');

-- Tasks. Members of org_web: u_w1, u_w2, u_w3. 'api' is Autonomous and the engine; user_support is not a member.
INSERT INTO public.tasks (organization_id, title, task_type, status, campaign_id, contact_id, created_by_user_id, created_at,
                          completed_by_user_id, completed_at, body) VALUES
  ('org_web', 't1', 'review_draft', 'completed', '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000a1',
   'api', now() - interval '3 days', 'u_w1', now() - interval '2 days', 'Hi Jane Prospect, jane.prospect@acme-prospect.test'),
  ('org_web', 't2', 'review_draft', 'completed', '00000000-0000-0000-0000-0000000000c1', NULL,
   NULL, now() - interval '4 days', 'u_w2', now() - interval '2 days 1 hour', NULL),
  ('org_web', 't3', 'review_draft', 'completed', '00000000-0000-0000-0000-0000000000c2', NULL,
   'api', now() - interval '11 days', 'u_w1', now() - interval '10 days', NULL),
  ('org_web', 't4 autonomous', 'review_draft', 'completed', '00000000-0000-0000-0000-0000000000c1', NULL,
   'api', now() - interval '1 day 1 hour', 'api', now() - interval '1 day', NULL),
  ('org_web', 't5 automated draft', 'review_draft', 'pending', '00000000-0000-0000-0000-0000000000c1', NULL,
   'api', now() - interval '1 hour', NULL, NULL, NULL),
  ('org_web', 't6 by a member', 'review_draft', 'pending', NULL, NULL,
   'u_w3', now() - interval '20 days', NULL, NULL, NULL),
  ('org_web', 't7 support', 'review_draft', 'completed', '00000000-0000-0000-0000-0000000000c2', NULL,
   'api', now() - interval '7 hours', 'user_support', now() - interval '6 hours', NULL),
  ('org_web', 't8 meeting', 'meeting', 'scheduled', '00000000-0000-0000-0000-0000000000c2', NULL,
   'api', now() - interval '5 days', NULL, NULL, NULL),
  ('org_web', 't9 old meeting', 'meeting', 'scheduled', '00000000-0000-0000-0000-0000000000c2', NULL,
   'api', now() - interval '40 days', NULL, NULL, NULL),
  ('org_gone', 'g1', 'review_draft', 'pending', '00000000-0000-0000-0000-0000000000d1', NULL,
   'u_g1', now() - interval '1 day', NULL, NULL, NULL);

-- Campaign emails: the reply carries the prospect's address and a body.
INSERT INTO public.campaign_emails (campaign_id, contact_id, organization_id, subject, content, sent_at, replied_at, reply_content, classification) VALUES
  ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000a1', 'org_web', 'Hi Jane Prospect', 'Body',
   now() - interval '3 days', now() - interval '1 day', 'Sure, write to jane.prospect@acme-prospect.test',
   '{"intent": "positive_intent", "confidence": 0.9}'),
  ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000a1', 'org_web', 'Follow-up', 'Body',
   now() - interval '10 days', NULL, NULL, NULL),
  ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000a1', 'org_web', 'Old', 'Body',
   now() - interval '40 days', now() - interval '35 days', 'Not now', '{"intent": "not_interested"}');

-- LinkedIn.
INSERT INTO public.linkedin_accounts (id, organization_id, user_id, unipile_account_id, provider, status, disconnected_at, last_status_change_at) VALUES
  ('00000000-0000-0000-0000-0000000000b1', 'org_web', 'u_w1', 'uni_1', 'LINKEDIN', 'active', NULL, now() - interval '30 days'),
  ('00000000-0000-0000-0000-0000000000b2', 'org_web', 'u_w2', 'uni_2', 'LINKEDIN', 'credentials_expired', NULL, now() - interval '4 days'),
  ('00000000-0000-0000-0000-0000000000b3', 'org_web', 'u_w2', 'uni_3', 'WHATSAPP', 'active', NULL, now() - interval '4 days');
INSERT INTO public.linkedin_action_log (organization_id, user_id, linkedin_account_id, unipile_account_id, action_type, recipient_provider_id, success, created_at) VALUES
  ('org_web', 'u_w1', '00000000-0000-0000-0000-0000000000b1', 'uni_1', 'invitation', 'jane-prospect', true, now() - interval '5 days'),
  ('org_web', 'u_w1', '00000000-0000-0000-0000-0000000000b1', 'uni_1', 'invitation', 'john-prospect', true, now() - interval '5 days'),
  ('org_web', 'u_w1', '00000000-0000-0000-0000-0000000000b1', 'uni_1', 'message', 'jane-prospect', false, now() - interval '2 days'),
  ('org_web', 'u_w1', '00000000-0000-0000-0000-0000000000b1', 'uni_1', 'profile_view', 'jane-prospect', true, now() - interval '2 days'),
  ('org_web', 'u_w1', '00000000-0000-0000-0000-0000000000b1', 'uni_1', 'message', 'jane-prospect', true, now() - interval '40 days');

-- Files: one by a person, one by the pipeline.
INSERT INTO public.organization_files (organization_id, file_name, file_type, file_url, file_size, uploaded_at, uploaded_by) VALUES
  ('org_web', 'brand.pdf', 'pdf', 'x', 1, now() - interval '3 days', 'alice@webco.test'),
  ('org_web', 'auto.pdf', 'pdf', 'x', 1, now() - interval '1 hour', 'system');

-- Research.
INSERT INTO public.onboarding_research (organization_id, status, interview_call_id, error_message, fit_type, is_supported, created_at, updated_at) VALUES
  ('org_web', 'approved', 'call_1', NULL, 'b2b', true, now() - interval '44 days', now() - interval '30 days');

-- Our own email to the customer, and the reply.
INSERT INTO public.onboarding_reengagement_sends (organization_id, user_email, sequence_step, sent_at) VALUES
  ('org_web', 'owner@webco.test', 'pending-24h', now() - interval '20 days');
INSERT INTO public.email_broadcasts (id, title, subject, body) VALUES ('00000000-0000-0000-0000-0000000000e1', 'News', 'News', 'News');
INSERT INTO public.email_broadcast_sends (broadcast_id, organization_id, user_email, status, sent_at) VALUES
  ('00000000-0000-0000-0000-0000000000e1', 'org_web', 'owner@webco.test', 'sent', now() - interval '6 days'),
  ('00000000-0000-0000-0000-0000000000e1', 'org_phone', 'owner@phoneco.test', 'sent', now() - interval '2 days'),
  ('00000000-0000-0000-0000-0000000000e1', 'org_quiet', 'owner@quietco.test', 'failed', now() - interval '1 day');
INSERT INTO public.cs_recommendations (organization_id, kind, status, approved_by, approved_at, executed_at, outcome, created_at) VALUES
  ('org_web', 'email', 'executed', 'staff_1', now() - interval '5 days', now() - interval '4 days',
   jsonb_build_object('replied_at', to_jsonb(now() - interval '2 days') #>> '{}'), now() - interval '5 days');
INSERT INTO public.cs_recommendations (organization_id, kind, status, created_at) VALUES
  ('org_web', 'tip', 'proposed', now() - interval '2 days'),
  ('org_web', 'note', 'proposed', now() - interval '1 hour'),
  ('org_web', 'email', 'proposed', now() - interval '3 days');
UPDATE public.cs_recommendations SET outcome = '{"replied_at": "not a date"}'::jsonb
  WHERE organization_id = 'org_web' AND kind = 'email' AND status = 'proposed';

-- Requests, notes, support.
INSERT INTO public.customer_requests (organization_id, user_id, type, status, body, created_at) VALUES
  ('org_web', 'u_w1', 'feedback', 'done', 'Great', now() - interval '10 days'),
  ('org_web', 'u_w1', 'leave', 'new', 'Ask jane.prospect@acme-prospect.test', now() - interval '1 day');
INSERT INTO public.backoffice_org_notes (organization_id, body, created_by, archived_at, created_at) VALUES
  ('org_web', 'Called them', 'staff_1', NULL, now() - interval '5 days'),
  ('org_web', 'Stalling', 'agent', NULL, now() - interval '1 day'),
  ('org_web', 'Old', 'agent', now(), now() - interval '1 hour');
INSERT INTO public.support_workspace_sessions (organization_id, support_user_id, support_user_email, status, expires_at, revoked_at, created_at) VALUES
  ('org_web', 'user_support', 'support@staff.test', 'active', now() + interval '1 hour', NULL, now() - interval '3 days'),
  ('org_web', 'user_support', 'support@staff.test', 'expired', now() - interval '39 days', NULL, now() - interval '40 days');

CREATE FUNCTION pg_temp.cs_keys(j jsonb) RETURNS text[] LANGUAGE sql AS $$
  SELECT coalesce(array_agg(k ORDER BY k), '{}'::text[]) FROM jsonb_object_keys(j) k
$$;
CREATE FUNCTION pg_temp.cs_sorted(a text[]) RETURNS text[] LANGUAGE sql AS $$
  SELECT array_agg(x ORDER BY x) FROM unnest(a) x
$$;

DO $$
DECLARE
  r record;
  f jsonb;
  ph jsonb;
  n integer;
  cols text[];
  fn text;
BEGIN
  -- Functions: STABLE, SECURITY INVOKER, search_path pinned; service role only.
  FOREACH fn IN ARRAY ARRAY['public.backoffice_cs_segment_inputs_v1()', 'public.backoffice_cs_workspace_facts_v1(text)'] LOOP
    IF (SELECT provolatile FROM pg_proc WHERE oid = fn::regprocedure) <> 's' THEN RAISE EXCEPTION '% is not STABLE', fn; END IF;
    IF (SELECT prosecdef FROM pg_proc WHERE oid = fn::regprocedure) THEN RAISE EXCEPTION '% is SECURITY DEFINER', fn; END IF;
    IF NOT (SELECT 'search_path=public' = ANY (proconfig) FROM pg_proc WHERE oid = fn::regprocedure) THEN
      RAISE EXCEPTION '% does not pin search_path', fn;
    END IF;
    IF has_function_privilege('anon', fn, 'EXECUTE') OR has_function_privilege('authenticated', fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'anon/authenticated can execute %', fn;
    END IF;
    IF NOT has_function_privilege('service_role', fn, 'EXECUTE') THEN RAISE EXCEPTION 'service_role cannot execute %', fn; END IF;
  END LOOP;
  BEGIN
    SET LOCAL ROLE anon;
    PERFORM * FROM public.backoffice_cs_segment_inputs_v1();
    RAISE EXCEPTION 'anon executed backoffice_cs_segment_inputs_v1';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    SET LOCAL ROLE anon;
    PERFORM public.backoffice_cs_workspace_facts_v1('org_web');
    RAISE EXCEPTION 'anon executed backoffice_cs_workspace_facts_v1';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM public.backoffice_cs_workspace_facts_v1('org_web');
    RAISE EXCEPTION 'authenticated executed backoffice_cs_workspace_facts_v1';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  IF current_user <> 'postgres' THEN RAISE EXCEPTION 'role not restored: %', current_user; END IF;

  -- The two columns.
  IF (SELECT count(*) FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'user_profiles'
        AND column_name IN ('last_seen_at', 'consent_marketing_at') AND data_type = 'timestamp with time zone') <> 2 THEN
    RAISE EXCEPTION 'user_profiles.last_seen_at / consent_marketing_at missing or not timestamptz';
  END IF;

  -- The rollup's columns are CsSegmentInputRow's fields, in order.
  SELECT array_agg(a.name ORDER BY a.ord) INTO cols
  FROM pg_proc p, unnest(p.proargnames, p.proargmodes::text[]) WITH ORDINALITY AS a(name, mode, ord)
  WHERE p.oid = 'public.backoffice_cs_segment_inputs_v1()'::regprocedure AND a.mode = 't';
  IF cols <> ARRAY['organization_id', 'name', 'created_at', 'signup_source', 'mobile_configured', 'onboarding_status',
                   'onboarding_completed_at', 'activation_paid_at', 'has_card_on_file', 'billing_status', 'trial_started_at',
                   'trial_ends_at', 'mobile_trial_ends_at', 'mobile_activated_at', 'member_count', 'active_seats',
                   'terminated_seats', 'plays_total', 'plays_live', 'first_play_launched_at', 'last_human_action_at',
                   'last_seen_at', 'activity_window_days', 'approvals_7d', 'approvals_prev_7d', 'pending_approvals',
                   'emails_sent_30d', 'replies_30d', 'meetings_30d', 'last_customer_email_at', 'last_customer_reply_at',
                   'last_chase_at', 'timezone', 'send_window_start', 'send_window_end', 'send_days',
                   'marketing_consent_members'] THEN
    RAISE EXCEPTION 'rollup columns differ from CsSegmentInputRow: %', cols;
  END IF;

  -- Rollup: one row per workspace not deleted.
  SELECT count(*) INTO n FROM public.backoffice_cs_segment_inputs_v1();
  IF n <> 3 THEN RAISE EXCEPTION 'rollup has % rows, expected 3', n; END IF;
  IF EXISTS (SELECT 1 FROM public.backoffice_cs_segment_inputs_v1() s WHERE s.organization_id = 'org_gone') THEN
    RAISE EXCEPTION 'the deleted workspace is in the rollup';
  END IF;

  -- The web workspace.
  SELECT * INTO r FROM public.backoffice_cs_segment_inputs_v1() s WHERE s.organization_id = 'org_web';
  IF r.name <> 'Web Co' OR r.signup_source IS NOT NULL OR r.mobile_configured OR r.onboarding_status <> 'launched'
     OR r.onboarding_completed_at <> now() - interval '40 days' OR r.activation_paid_at <> now() - interval '50 days' THEN
    RAISE EXCEPTION 'org_web identity fields wrong: %', row_to_json(r);
  END IF;
  IF NOT r.has_card_on_file OR r.billing_status <> 'active' OR r.trial_started_at <> now() - interval '45 days'
     OR r.trial_ends_at <> now() - interval '38 days' OR r.mobile_trial_ends_at IS NOT NULL OR r.mobile_activated_at IS NOT NULL THEN
    RAISE EXCEPTION 'org_web billing fields wrong: %', row_to_json(r);
  END IF;
  IF r.member_count <> 3 OR r.active_seats <> 2 OR r.terminated_seats <> 1 THEN
    RAISE EXCEPTION 'org_web people wrong: %', row_to_json(r);
  END IF;
  IF r.plays_total <> 4 OR r.plays_live <> 2 OR r.first_play_launched_at <> now() - interval '95 days' THEN
    RAISE EXCEPTION 'org_web plays wrong (cancelled excluded, 2 live): %', row_to_json(r);
  END IF;
  -- Approvals: t1 and t2 in the last 7 days, t3 in the 7 before; Autonomous (t4) and support (t7) do not count.
  IF r.approvals_7d <> 2 OR r.approvals_prev_7d <> 1 THEN
    RAISE EXCEPTION 'org_web approvals_7d % / approvals_prev_7d %, expected 2 / 1', r.approvals_7d, r.approvals_prev_7d;
  END IF;
  -- The last human action is t1's approval (2 days ago): the automated draft (1 hour), Autonomous (1 day), support
  -- (6 hours) and the pipeline's file (1 hour) are later and ignored.
  IF r.last_human_action_at IS DISTINCT FROM now() - interval '2 days' OR r.activity_window_days <> 45 THEN
    RAISE EXCEPTION 'org_web last_human_action_at %, expected 2 days ago', r.last_human_action_at;
  END IF;
  IF r.pending_approvals <> 2 OR r.meetings_30d <> 1 OR r.emails_sent_30d <> 2 OR r.replies_30d <> 1 THEN
    RAISE EXCEPTION 'org_web pending/meetings/emails wrong: %', row_to_json(r);
  END IF;
  -- Members only: u_left's later last_seen_at and consent do not count.
  IF r.last_seen_at IS DISTINCT FROM now() - interval '1 hour' OR r.marketing_consent_members <> 2 THEN
    RAISE EXCEPTION 'org_web last_seen_at % / marketing_consent_members %, expected 1 hour ago / 2',
      r.last_seen_at, r.marketing_consent_members;
  END IF;
  IF r.last_customer_email_at IS DISTINCT FROM now() - interval '4 days'
     OR r.last_customer_reply_at IS DISTINCT FROM now() - interval '2 days'
     OR r.last_chase_at IS DISTINCT FROM now() - interval '20 days' THEN
    RAISE EXCEPTION 'org_web our own email wrong: %', row_to_json(r);
  END IF;
  IF r.timezone <> 'Europe/Berlin' OR r.send_window_start <> 450 OR r.send_window_end <> 1080 OR r.send_days <> ARRAY[1, 2, 3, 4, 5] THEN
    RAISE EXCEPTION 'org_web send window wrong: %', row_to_json(r);
  END IF;

  -- The phone-first workspace.
  SELECT * INTO r FROM public.backoffice_cs_segment_inputs_v1() s WHERE s.organization_id = 'org_phone';
  IF r.signup_source <> 'mobile' OR NOT r.mobile_configured OR r.has_card_on_file
     OR r.mobile_trial_ends_at <> now() + interval '5 days' OR r.mobile_activated_at <> now() - interval '3 days'
     OR r.member_count <> 2 OR r.active_seats <> 2 OR r.plays_total <> 21 OR r.plays_live <> 0
     OR r.marketing_consent_members <> 0 OR r.last_seen_at <> now() - interval '2 hours'
     OR r.last_customer_email_at <> now() - interval '2 days' OR r.last_customer_reply_at IS NOT NULL THEN
    RAISE EXCEPTION 'org_phone row wrong: %', row_to_json(r);
  END IF;

  -- The empty workspace: zeros and nulls, never an error. mobile = JSON null is not configured.
  SELECT * INTO r FROM public.backoffice_cs_segment_inputs_v1() s WHERE s.organization_id = 'org_quiet';
  IF r.mobile_configured OR r.has_card_on_file OR r.member_count <> 0 OR r.plays_total <> 0 OR r.approvals_7d <> 0
     OR r.pending_approvals <> 0 OR r.marketing_consent_members <> 0 OR r.last_human_action_at IS NOT NULL
     OR r.last_customer_email_at IS NOT NULL OR r.timezone IS NOT NULL OR r.send_days IS NOT NULL THEN
    RAISE EXCEPTION 'org_quiet row wrong: %', row_to_json(r);
  END IF;

  -- Facts: the shape of CsWorkspaceFacts, key for key.
  f := public.backoffice_cs_workspace_facts_v1('org_web');
  IF f IS NULL THEN RAISE EXCEPTION 'no facts for org_web'; END IF;
  IF pg_temp.cs_keys(f) <> pg_temp.cs_sorted(ARRAY['generated_at', 'organization', 'segment', 'health_score', 'members', 'seats',
       'research', 'plays', 'outcomes', 'activity', 'billing', 'requests', 'mailboxes', 'notes', 'support', 'caps', 'recommendations']) THEN
    RAISE EXCEPTION 'facts top-level keys: %', pg_temp.cs_keys(f);
  END IF;
  IF pg_temp.cs_keys(f->'organization') <> pg_temp.cs_sorted(ARRAY['id', 'name', 'tier', 'created_at', 'signup_source',
       'onboarding_status', 'onboarding_mode', 'activation_paid_at', 'work_access_mode', 'dispatch_suspended', 'timezone', 'last_seen_at'])
     OR pg_temp.cs_keys(f->'members') <> pg_temp.cs_sorted(ARRAY['total', 'admins', 'web_users', 'phone_users', 'last_web_login_at', 'marketing_consent'])
     OR pg_temp.cs_keys(f->'seats') <> pg_temp.cs_sorted(ARRAY['active', 'billable', 'web', 'mobile'])
     OR pg_temp.cs_keys(f->'research') <> pg_temp.cs_sorted(ARRAY['status', 'started_at', 'updated_at', 'days_in_status', 'fit_type',
       'is_supported', 'has_interview', 'error'])
     OR pg_temp.cs_keys(f->'plays') <> pg_temp.cs_sorted(ARRAY['total', 'active', 'draft', 'approved_not_launched', 'completed',
       'first_launched_at', 'last_launched_at', 'items'])
     OR pg_temp.cs_keys(f->'plays'->'items'->0) <> pg_temp.cs_sorted(ARRAY['id', 'name', 'status', 'created_at', 'launched_at',
       'approvals_30d', 'sent_30d', 'replies_30d', 'meetings_30d', 'drafts_waiting'])
     OR pg_temp.cs_keys(f->'outcomes') <> pg_temp.cs_sorted(ARRAY['window_days', 'approvals', 'approvals_total', 'drafts_waiting',
       'emails_sent', 'linkedin_sent', 'replies', 'positive_replies', 'meetings', 'meetings_total', 'last_approval_at',
       'last_reply_at', 'last_meeting_at'])
     OR pg_temp.cs_keys(f->'activity') <> pg_temp.cs_sorted(ARRAY['last_human_action_at', 'days_since_human_action', 'human_actions_7d'])
     OR pg_temp.cs_keys(f->'billing') <> pg_temp.cs_sorted(ARRAY['status', 'card_on_file', 'billing_started_at', 'paying', 'trial_active',
       'trial_ends_at', 'trial_credit_usd', 'trial_credit_remaining_usd', 'credit_remaining_usd', 'monthly_spend_limit_usd',
       'usage_7d_usd', 'usage_prev_7d_usd', 'usage_28d_usd', 'last_invoice_at', 'open_invoice_usd', 'seat_discount_percent'])
     OR pg_temp.cs_keys(f->'requests') <> pg_temp.cs_sorted(ARRAY['open', 'leave_open', 'last_type', 'last_at'])
     OR pg_temp.cs_keys(f->'mailboxes') <> pg_temp.cs_sorted(ARRAY['email_connected', 'email_disconnected', 'linkedin_connected',
       'linkedin_disconnected', 'last_disconnected_at'])
     OR pg_temp.cs_keys(f->'notes') <> pg_temp.cs_sorted(ARRAY['count', 'agent_count', 'last_at'])
     OR pg_temp.cs_keys(f->'support') <> pg_temp.cs_sorted(ARRAY['sessions_30d', 'active_session', 'last_session_at'])
     OR pg_temp.cs_keys(f->'caps') <> pg_temp.cs_sorted(ARRAY['last_customer_email_at', 'customer_replied_since_last_email',
       'can_email', 'next_email_at', 'in_quiet_hours'])
     OR pg_temp.cs_keys(f->'recommendations') <> pg_temp.cs_sorted(ARRAY['proposed', 'last_kind', 'last_at']) THEN
    RAISE EXCEPTION 'facts nested keys differ from CsWorkspaceFacts: %', f;
  END IF;

  -- No prospect data: not the address, not the name, not a reply or draft body. No address of anyone at all.
  IF strpos(f::text, '@') > 0 OR strpos(f::text, 'acme-prospect') > 0 OR strpos(f::text, 'Jane') > 0
     OR strpos(f::text, 'Sure, write') > 0 OR strpos(f::text, 'jane-prospect') > 0 THEN
    RAISE EXCEPTION 'facts leak prospect or personal data: %', f;
  END IF;

  -- Facts: values.
  IF f->'segment' <> 'null'::jsonb OR f->'health_score' <> 'null'::jsonb
     OR (f->>'generated_at')::timestamptz <> now() THEN
    RAISE EXCEPTION 'segment/health_score/generated_at wrong: %', f;
  END IF;
  IF f->'organization'->>'id' <> 'org_web' OR f->'organization'->>'signup_source' <> 'web'
     OR f->'organization'->>'timezone' <> 'Europe/Berlin' OR f->'organization'->>'tier' <> 'tier1'
     OR (f->'organization'->>'dispatch_suspended')::boolean
     OR (f->'organization'->>'last_seen_at')::timestamptz <> now() - interval '1 hour' THEN
    RAISE EXCEPTION 'facts organization wrong: %', f->'organization';
  END IF;
  IF f->'members' <> '{"total": 3, "admins": 2, "web_users": 0, "phone_users": 0, "last_web_login_at": null, "marketing_consent": 2}'::jsonb
     OR f->'seats' <> '{"active": 2, "billable": 1, "web": 2, "mobile": 0}'::jsonb THEN
    RAISE EXCEPTION 'facts members/seats wrong: % %', f->'members', f->'seats';
  END IF;
  IF f->'research'->>'status' <> 'approved' OR (f->'research'->>'days_in_status')::integer <> 30
     OR NOT (f->'research'->>'has_interview')::boolean OR (f->'research'->>'error')::boolean THEN
    RAISE EXCEPTION 'facts research wrong: %', f->'research';
  END IF;
  IF (f->'plays'->>'total')::integer <> 5 OR (f->'plays'->>'active')::integer <> 2 OR (f->'plays'->>'draft')::integer <> 1
     OR (f->'plays'->>'completed')::integer <> 1 OR (f->'plays'->>'approved_not_launched')::integer <> 0
     OR (f->'plays'->>'first_launched_at')::timestamptz <> now() - interval '95 days'
     OR (f->'plays'->>'last_launched_at')::timestamptz <> now() - interval '18 days'
     OR jsonb_array_length(f->'plays'->'items') <> 5 OR f->'plays'->'items'->0->>'name' <> 'Autumn draft' THEN
    RAISE EXCEPTION 'facts plays wrong: %', f->'plays';
  END IF;
  SELECT i INTO ph FROM jsonb_array_elements(f->'plays'->'items') i WHERE i->>'name' = 'Spring outreach';
  IF ph - 'id' - 'created_at' - 'launched_at' <> '{"name": "Spring outreach", "status": "active", "approvals_30d": 2, "sent_30d": 2,
        "replies_30d": 1, "meetings_30d": 0, "drafts_waiting": 1}'::jsonb THEN
    RAISE EXCEPTION 'facts play item wrong: %', ph;
  END IF;
  SELECT i INTO ph FROM jsonb_array_elements(f->'plays'->'items') i WHERE i->>'name' = 'Summer outreach';
  IF (ph->>'approvals_30d')::integer <> 1 OR (ph->>'meetings_30d')::integer <> 1 OR (ph->>'sent_30d')::integer <> 0
     OR (ph->>'launched_at')::timestamptz <> now() - interval '18 days' THEN
    RAISE EXCEPTION 'facts play item wrong: %', ph;
  END IF;
  IF (f->'outcomes') - 'last_approval_at' - 'last_reply_at' - 'last_meeting_at' <> '{"window_days": 30, "approvals": 3,
        "approvals_total": 3, "drafts_waiting": 2, "emails_sent": 2, "linkedin_sent": 2, "replies": 1, "positive_replies": 1,
        "meetings": 1, "meetings_total": 2}'::jsonb
     OR (f->'outcomes'->>'last_approval_at')::timestamptz <> now() - interval '2 days'
     OR (f->'outcomes'->>'last_reply_at')::timestamptz <> now() - interval '1 day'
     OR (f->'outcomes'->>'last_meeting_at')::timestamptz <> now() - interval '5 days' THEN
    RAISE EXCEPTION 'facts outcomes wrong: %', f->'outcomes';
  END IF;
  -- Human actions in 7 days: t1, t2 (approvals), the draft play (5 days), the brand file (3 days).
  IF (f->'activity'->>'last_human_action_at')::timestamptz <> now() - interval '2 days'
     OR (f->'activity'->>'days_since_human_action')::integer <> 2 OR (f->'activity'->>'human_actions_7d')::integer <> 4 THEN
    RAISE EXCEPTION 'facts activity wrong: %', f->'activity';
  END IF;
  IF f->'billing'->>'status' <> 'active' OR NOT (f->'billing'->>'card_on_file')::boolean OR NOT (f->'billing'->>'paying')::boolean
     OR (f->'billing'->>'trial_active')::boolean OR (f->'billing'->>'trial_ends_at')::timestamptz <> now() - interval '38 days'
     OR (f->'billing'->>'trial_credit_usd')::numeric <> 40 OR (f->'billing'->>'trial_credit_remaining_usd')::numeric <> 0
     OR (f->'billing'->>'credit_remaining_usd')::numeric <> 10 OR (f->'billing'->>'monthly_spend_limit_usd')::numeric <> 200
     OR (f->'billing'->>'usage_7d_usd')::numeric <> 1.50 OR (f->'billing'->>'usage_prev_7d_usd')::numeric <> 2.25
     OR (f->'billing'->>'usage_28d_usd')::numeric <> 7.75
     OR (f->'billing'->>'last_invoice_at')::timestamptz <> now() - interval '1 day'
     OR (f->'billing'->>'open_invoice_usd')::numeric <> 12.50 OR (f->'billing'->>'seat_discount_percent')::numeric <> 20 THEN
    RAISE EXCEPTION 'facts billing wrong: %', f->'billing';
  END IF;
  IF (f->'requests'->>'open')::integer <> 1 OR NOT (f->'requests'->>'leave_open')::boolean OR f->'requests'->>'last_type' <> 'leave'
     OR (f->'requests'->>'last_at')::timestamptz <> now() - interval '1 day' THEN
    RAISE EXCEPTION 'facts requests wrong: %', f->'requests';
  END IF;
  IF (f->'mailboxes') - 'last_disconnected_at' <> '{"email_connected": 0, "email_disconnected": 0, "linkedin_connected": 1,
        "linkedin_disconnected": 1}'::jsonb
     OR (f->'mailboxes'->>'last_disconnected_at')::timestamptz <> now() - interval '4 days' THEN
    RAISE EXCEPTION 'facts mailboxes wrong: %', f->'mailboxes';
  END IF;
  IF (f->'notes'->>'count')::integer <> 2 OR (f->'notes'->>'agent_count')::integer <> 1
     OR (f->'notes'->>'last_at')::timestamptz <> now() - interval '1 day'
     OR (f->'support'->>'sessions_30d')::integer <> 1 OR NOT (f->'support'->>'active_session')::boolean
     OR (f->'support'->>'last_session_at')::timestamptz <> now() - interval '3 days' THEN
    RAISE EXCEPTION 'facts notes/support wrong: % %', f->'notes', f->'support';
  END IF;
  -- The customer replied (2 days ago) after our last email (4 days ago): we may email.
  IF (f->'caps'->>'last_customer_email_at')::timestamptz <> now() - interval '4 days'
     OR NOT (f->'caps'->>'customer_replied_since_last_email')::boolean OR NOT (f->'caps'->>'can_email')::boolean
     OR f->'caps'->'next_email_at' <> 'null'::jsonb OR jsonb_typeof(f->'caps'->'in_quiet_hours') <> 'boolean' THEN
    RAISE EXCEPTION 'facts caps wrong: %', f->'caps';
  END IF;
  IF (f->'recommendations'->>'proposed')::integer <> 3 OR f->'recommendations'->>'last_kind' <> 'note'
     OR (f->'recommendations'->>'last_at')::timestamptz <> now() - interval '1 hour' THEN
    RAISE EXCEPTION 'facts recommendations wrong: %', f->'recommendations';
  END IF;

  -- The phone-first workspace: 20 items of 21, newest first; the phone trial; no email for 7 days after ours; quiet
  -- (today is not a send day in UTC, the fallback for a zone this server does not know).
  ph := public.backoffice_cs_workspace_facts_v1('org_phone');
  IF jsonb_array_length(ph->'plays'->'items') <> 20 OR (ph->'plays'->>'total')::integer <> 21
     OR ph->'plays'->'items'->0->>'name' <> 'Phone play 1' OR ph->'plays'->'items'->19->>'name' <> 'Phone play 20' THEN
    RAISE EXCEPTION 'org_phone items wrong: %', ph->'plays';
  END IF;
  IF ph->'organization'->>'signup_source' <> 'mobile' OR ph->'seats' <> '{"active": 2, "billable": 2, "web": 1, "mobile": 1}'::jsonb
     OR (ph->'members'->>'phone_users')::integer <> 2 OR (ph->'members'->>'admins')::integer <> 1
     OR NOT (ph->'billing'->>'trial_active')::boolean OR (ph->'billing'->>'trial_ends_at')::timestamptz <> now() + interval '5 days'
     OR (ph->'billing'->>'card_on_file')::boolean OR ph->'billing'->'trial_credit_usd' <> 'null'::jsonb
     OR ph->'research'->'status' <> 'null'::jsonb OR (ph->'research'->>'has_interview')::boolean THEN
    RAISE EXCEPTION 'org_phone facts wrong: %', ph;
  END IF;
  IF (ph->'caps'->>'can_email')::boolean OR (ph->'caps'->>'customer_replied_since_last_email')::boolean
     OR (ph->'caps'->>'next_email_at')::timestamptz <> now() + interval '5 days'
     OR NOT (ph->'caps'->>'in_quiet_hours')::boolean THEN
    RAISE EXCEPTION 'org_phone caps wrong: %', ph->'caps';
  END IF;

  -- The empty workspace: zeros and nulls; an unknown one: NULL.
  ph := public.backoffice_cs_workspace_facts_v1('org_quiet');
  IF (ph->'plays'->>'total')::integer <> 0 OR ph->'plays'->'items' <> '[]'::jsonb OR (ph->'billing'->>'credit_remaining_usd')::numeric <> 0
     OR ph->'activity'->'last_human_action_at' <> 'null'::jsonb OR (ph->'caps'->>'in_quiet_hours')::boolean
     OR NOT (ph->'caps'->>'can_email')::boolean OR ph->'organization'->'timezone' <> 'null'::jsonb THEN
    RAISE EXCEPTION 'org_quiet facts wrong: %', ph;
  END IF;
  IF public.backoffice_cs_workspace_facts_v1('org_unknown') IS NOT NULL THEN
    RAISE EXCEPTION 'facts for an unknown organization are not NULL';
  END IF;
END $$;
SELECT 'backoffice cs agent facts contract passed' AS result;
