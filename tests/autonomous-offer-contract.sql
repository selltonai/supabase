-- KAN-322 FR-B8a contract: campaign_human_approval_counts_v1 counts a person's approvals per play and type, never
-- Autonomous's, and user_profiles.ui_seen exists with its default. Hand-worked expectations; disposable database only.
\set P1 '''11111111-1111-1111-1111-111111111111'''
\set P2 '''22222222-2222-2222-2222-222222222222'''
INSERT INTO public.tasks (organization_id, campaign_id, task_type, status, completed_by_user_id, metadata) VALUES
  -- company: 2 by people; Autonomous approved 1, rejected 1; a person rejected 1; one still pending
  ('org_A', :P1, 'company_verification', 'completed', 'user_a', '{"verification_result":"approved","verified_by":"user_a"}'),
  ('org_A', :P1, 'company_verification', 'completed', 'user_b', '{"verification_result":"approved","verified_by":"user_b"}'),
  ('org_A', :P1, 'company_verification', 'completed', 'api', '{"verification_result":"approved","verified_by":"api","autopilot":true}'),
  ('org_A', :P1, 'company_verification', 'cancelled', 'api', '{"verification_result":"rejected","verified_by":"api","autopilot":true}'),
  ('org_A', :P1, 'company_verification', 'cancelled', 'user_a', '{"verification_result":"rejected","verified_by":"user_a"}'),
  ('org_A', :P1, 'company_verification', 'pending', NULL, '{}'),
  -- a completed company task that was not approved (defensive: only 'approved' counts)
  ('org_A', :P1, 'company_verification', 'completed', 'user_a', '{"verification_result":"rejected","verified_by":"user_a"}'),
  -- first emails: accepted by a person (2, one scheduled), bulk with an expired session (approvedBy, accepted_by api),
  -- the legacy PATCH (no accepted_by); Autonomous (accepted_by api, completed_by api); new_email counts as initial
  ('org_A', :P1, 'review_draft', 'completed', 'user_a', '{"channel":"email","email_type":"initial","accepted_by":"user_a"}'),
  ('org_A', :P1, 'review_draft', 'scheduled', 'user_a', '{"email_type":"initial","accepted_by":"user_a"}'),
  ('org_A', :P1, 'review_draft', 'completed', 'api', '{"email_type":"initial","accepted_by":"api","approvedBy":"user_b","bulk_approved":true}'),
  ('org_A', :P1, 'review_draft', 'completed', 'user_c', '{"emailType":"new_email"}'),
  ('org_A', :P1, 'review_draft', 'completed', 'api', '{"email_type":"initial","accepted_by":"api","autopilot":true}'),
  -- Autonomous accepted it ('api') although the row names a person as completer: accepted_by decides
  ('org_A', :P1, 'review_draft', 'completed', 'user_z', '{"email_type":"initial","accepted_by":"api","autopilot":true}'),
  -- follow-ups: one by a person (type key), one Autonomous, one declined
  ('org_A', :P1, 'review_draft', 'completed', 'user_a', '{"type":"slot_reminder_1","accepted_by":"user_a"}'),
  ('org_A', :P1, 'review_draft', 'completed', 'api', '{"email_type":"follow_up","accepted_by":"api","autopilot":true}'),
  ('org_A', :P1, 'review_draft', 'cancelled', 'user_a', '{"email_type":"follow_up","cancelled_by":"user_a"}'),
  -- a reply email by a person; an email with an unknown kind is not counted
  ('org_A', :P1, 'review_draft', 'completed', 'user_a', '{"reply_type":"meeting_response","accepted_by":"user_a"}'),
  ('org_A', :P1, 'review_draft', 'completed', 'user_a', '{"email_type":"something_new","accepted_by":"user_a"}'),
  -- LinkedIn invites: sent now by a person; scheduled by a person; completed later by the dispatcher (approver kept);
  -- Autonomous sent now (no approver) and scheduled (li_dispatch_approved_by autopilot)
  ('org_A', :P1, 'review_draft', 'completed', 'user_a', '{"channel":"linkedin","linkedin_action_type":"invitation","last_dispatch":{"approved_by_user_id":"user_a"}}'),
  ('org_A', :P1, 'review_draft', 'scheduled', NULL, '{"channel":"linkedin","linkedin_action_type":"invitation","li_dispatch_approved_by":"user_b"}'),
  ('org_A', :P1, 'review_draft', 'completed', NULL, '{"channel":"linkedin","linkedin_action_type":"invitation","li_dispatch_approved_by":"user_b"}'),
  ('org_A', :P1, 'review_draft', 'completed', NULL, '{"channel":"linkedin","linkedin_action_type":"invitation","autopilot":true}'),
  ('org_A', :P1, 'review_draft', 'scheduled', NULL, '{"channel":"linkedin","linkedin_action_type":"invitation","li_dispatch_approved_by":"autopilot","autopilot":true}'),
  -- LinkedIn messages: a person approved a task Autonomous had scheduled and the dispatcher returned (autopilot flag kept);
  -- a terminal autopilot completion with no marker at all; a message with no action type is a message
  ('org_A', :P1, 'review_draft', 'completed', 'user_a', '{"channel":"linkedin","linkedin_action_type":"message","autopilot":true,"last_dispatch":{"approved_by_user_id":"user_a"}}'),
  ('org_A', :P1, 'review_draft', 'completed', NULL, '{"channel":"linkedin","linkedin_action_type":"message"}'),
  ('org_A', :P1, 'review_draft', 'completed', NULL, '{"channel":"linkedin","li_dispatch_approved_by":"user_c"}'),
  -- a LinkedIn reply is never counted
  ('org_A', :P1, 'review_reply', 'completed', 'user_a', '{"channel":"linkedin","last_dispatch":{"approved_by_user_id":"user_a"}}'),
  -- another play, another workspace, no play
  ('org_A', :P2, 'company_verification', 'completed', 'user_a', '{"verification_result":"approved","verified_by":"user_a"}'),
  ('org_B', :P1, 'company_verification', 'completed', 'user_x', '{"verification_result":"approved","verified_by":"user_x"}'),
  ('org_A', NULL, 'company_verification', 'completed', 'user_a', '{"verification_result":"approved","verified_by":"user_a"}');

DO $$
DECLARE got text; want text;
BEGIN
  SELECT string_agg(approval_type || '=' || approvals, ', ' ORDER BY approval_type) INTO got
    FROM public.campaign_human_approval_counts_v1('org_A', '11111111-1111-1111-1111-111111111111');
  want := 'company=2, followup_email=1, initial_email=4, linkedin_invite=3, linkedin_message=2, reply_email=1';
  IF got IS DISTINCT FROM want THEN RAISE EXCEPTION 'play 1: got %, want %', got, want; END IF;

  SELECT string_agg(campaign_id || ':' || approval_type || '=' || approvals, ', ' ORDER BY campaign_id, approval_type) INTO got
    FROM public.campaign_human_approval_counts_v1('org_A') WHERE approval_type = 'company';
  want := '11111111-1111-1111-1111-111111111111:company=2, 22222222-2222-2222-2222-222222222222:company=1';
  IF got IS DISTINCT FROM want THEN RAISE EXCEPTION 'every play: got %, want %', got, want; END IF;

  IF (SELECT count(*) FROM public.campaign_human_approval_counts_v1('org_A') WHERE campaign_id IS NULL) <> 0 THEN
    RAISE EXCEPTION 'a task without a play is never counted';
  END IF;

  IF (SELECT count(*) FROM public.campaign_human_approval_counts_v1('org_C')) <> 0 THEN
    RAISE EXCEPTION 'an empty workspace returns no rows';
  END IF;

  IF has_function_privilege('anon', 'public.campaign_human_approval_counts_v1(text,uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.campaign_human_approval_counts_v1(text,uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.campaign_human_approval_counts_v1(text,uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'only service_role may call campaign_human_approval_counts_v1';
  END IF;

  IF (SELECT ui_seen FROM public.user_profiles WHERE user_id = 'user_a') IS DISTINCT FROM '{}'::jsonb THEN
    RAISE EXCEPTION 'ui_seen defaults to {} on existing rows';
  END IF;
  IF (SELECT is_nullable FROM information_schema.columns WHERE table_name = 'user_profiles' AND column_name = 'ui_seen') <> 'NO' THEN
    RAISE EXCEPTION 'ui_seen is NOT NULL';
  END IF;
END $$;
