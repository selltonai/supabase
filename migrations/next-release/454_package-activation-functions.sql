-- ============================================================
-- Migration: 454_package-activation-functions (stage: next-release/454; renumber at promotion if 454 is taken)
-- Date:      2026-11-27
-- Ticket:    KAN-borce27 (PLAN_YEAR_END_PACKAGES_AND_ONBOARDING_2026_11_27, T2; decisions B1-B27)
-- Purpose:   The three writes behind packages, each one transaction, so a retried webhook or a double click can
--            never half-activate a workspace or grant twice.
--            1. activate_package_checkout: a card purchase on the wall (B2, B16). Activates the workspace, records
--               the fee, ends a running trial or budget and its override, and inserts the usage grant (dedupe key
--               'checkout:<session id>'). No work-access override: card buyers work on auto.
--            2. redeem_package_code: a code for an invoice deal (B3, B21). Refusals are returned (and recorded in
--               package_code_attempts), never raised. On success it marks the code used, activates the workspace,
--               records the fee (0 paid, the invoiced price), proposes the usage grant to the backoffice as one
--               cs_recommendations row, and sets card_required when no card is on file.
--            3. end_package_grant_for_payment: a refund or dispute of a card purchase (B18, B27). A dispute or a
--               full refund ends the grant; a partial refund lowers it by the refunded share of the grant's
--               original amount, and ends it when what is already drawn reaches the new amount.
-- Projects:  selltonai-database/supabase (owner). selltonai calls all three (the Stripe webhook, the wall and
--            Settings -> Billing). backoffice approves the proposals redeem_package_code writes (its existing
--            allowance path) and reads the rows all three write. selltonai-modal: none (it draws the grants as
--            any usage grant). The mobile service and the engine: none.
-- Contract:  Additive. Three new functions, SECURITY DEFINER with search_path public, each returning jsonb; only
--            the service role may execute them. No table, column or row changes here.
--            Return shapes (the app and the backoffice code against them):
--              activate_package_checkout -> {status, activation_fee_id, allowance_id, ended_allowance_id
--                [, existing_allowance_id]}; status activated | already_done | amount_mismatch |
--                grant_conflict | unknown_package | unknown_organization | invalid_request.
--              redeem_package_code -> {ok: true, recommendation_id, blocked, package_id, grant_usd,
--                validity_days[, already_redeemed]} or {ok: false, reason}; reason too_many_attempts | not_found |
--                inactive | expired | used | email_mismatch | archived | existing_cohort |
--                already_activated_with_grant | package_pending (another code's proposal is still proposed).
--              end_package_grant_for_payment -> {status, allowance_id, amount_usd}; status ended | reduced |
--                not_found | unchanged. p_refunded_cents is the charge's refunded total so far (Stripe's
--                amount_refunded), p_amount_cents the charge amount.
--            The usage-grant marker is Modal's: a workspace_allowances row whose reason starts with
--            'Usage grant: '. A grant's override is work_access_mode 'force_allow' with work_access_reason
--            starting 'Allowance'; any other force_allow (a manual admin override) is never touched.
--            Application code: none must ship together with this file (nothing calls it until the app ships).
-- Depends:   453 (billing_packages, package_codes, package_code_attempts, the activation_fees columns),
--            public.organization (activation_paid_at, dispatch_suspended* 302; work_access_* 324; deleted 115;
--            billing_cohort 446), public.activation_fees (307), public.billing_customers (243),
--            public.cs_recommendations (422), public.workspace_allowances (427),
--            public.billing_allowance_deductions (446). public.workspace_deletions (428) is read when present.
-- Rollback:  rollback/454_package-activation-functions.rollback.sql
-- ============================================================

SET LOCAL lock_timeout = '10s';

-- 1. A card purchase ------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.activate_package_checkout(
  p_session_id text,
  p_org_id text,
  p_package_id text,
  p_amount_paid_cents integer,
  p_currency text,
  p_payment_intent_id text,
  p_user_id text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_now timestamptz := now();
  v_actor constant text := 'system:stripe_checkout';
  v_dedupe text := 'checkout:' || p_session_id;
  v_pkg public.billing_packages%ROWTYPE;
  v_fee_id uuid;
  v_grant_id uuid;
  v_ended_id uuid;
  v_existing_id uuid;
  v_had_fee boolean;
  v_had_grant boolean;
BEGIN
  IF nullif(btrim(coalesce(p_session_id, '')), '') IS NULL OR nullif(btrim(coalesce(p_org_id, '')), '') IS NULL THEN
    RETURN jsonb_build_object('status', 'invalid_request');
  END IF;

  -- One activation at a time per workspace: a second webhook for the same session waits here, then finds the work
  -- done.
  PERFORM 1 FROM public.organization WHERE id = p_org_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'unknown_organization');
  END IF;

  SELECT id INTO v_fee_id FROM public.activation_fees WHERE stripe_checkout_session_id = p_session_id;
  SELECT id INTO v_grant_id FROM public.workspace_allowances WHERE dedupe_key = v_dedupe;
  v_had_fee := v_fee_id IS NOT NULL;
  v_had_grant := v_grant_id IS NOT NULL;

  -- Activate (a retry finishes what an earlier attempt left).
  UPDATE public.organization SET activation_paid_at = v_now WHERE id = p_org_id AND activation_paid_at IS NULL;

  IF v_had_fee AND v_had_grant THEN
    RETURN jsonb_build_object('status', 'already_done', 'activation_fee_id', v_fee_id, 'allowance_id', v_grant_id,
                              'ended_allowance_id', NULL);
  END IF;

  SELECT * INTO v_pkg FROM public.billing_packages WHERE id = p_package_id;

  IF NOT v_had_fee THEN
    INSERT INTO public.activation_fees
      (organization_id, amount_paid_cents, currency, paid_at, stripe_checkout_session_id, stripe_payment_intent_id,
       activated_by, metadata, source, package_id)
    VALUES
      (p_org_id, greatest(coalesce(p_amount_paid_cents, 0), 0), lower(coalesce(nullif(btrim(p_currency), ''), 'usd')),
       v_now, p_session_id, p_payment_intent_id, p_user_id,
       -- The package's terms at payment: a partial refund reduces the grant from these, whatever the package says
       -- later.
       CASE WHEN v_pkg.id IS NULL THEN '{}'::jsonb
            ELSE jsonb_build_object('package', jsonb_build_object(
                   'id', v_pkg.id, 'label', v_pkg.label, 'price_usd', v_pkg.price_usd,
                   'grant_usd', v_pkg.grant_usd, 'validity_days', v_pkg.validity_days)) END,
       'stripe_checkout', p_package_id)
    RETURNING id INTO v_fee_id;
  END IF;

  IF v_had_grant THEN
    -- Only the fee row was missing.
    RETURN jsonb_build_object('status', 'activated', 'activation_fee_id', v_fee_id, 'allowance_id', v_grant_id,
                              'ended_allowance_id', NULL);
  END IF;

  -- The money is recorded and the workspace activated in both refusals below; no grant is written.
  IF v_pkg.id IS NULL THEN
    RETURN jsonb_build_object('status', 'unknown_package', 'activation_fee_id', v_fee_id, 'allowance_id', NULL,
                              'ended_allowance_id', NULL);
  END IF;
  IF coalesce(p_amount_paid_cents, 0) < round(v_pkg.price_usd * 100) THEN
    RETURN jsonb_build_object('status', 'amount_mismatch', 'activation_fee_id', v_fee_id, 'allowance_id', NULL,
                              'ended_allowance_id', NULL);
  END IF;

  -- B16: a running trial or budget (any active allowance that is not a usage grant) ends at payment.
  UPDATE public.workspace_allowances
     SET status = 'ended', ended_by = v_actor, ended_at = v_now
   WHERE organization_id = p_org_id AND status = 'active' AND NOT starts_with(reason, 'Usage grant: ')
  RETURNING id INTO v_ended_id;

  -- B14: one grant at a time.
  SELECT id INTO v_existing_id
    FROM public.workspace_allowances
   WHERE organization_id = p_org_id AND status = 'active' AND starts_with(reason, 'Usage grant: ')
   LIMIT 1;
  IF v_existing_id IS NOT NULL THEN
    RETURN jsonb_build_object('status', 'grant_conflict', 'activation_fee_id', v_fee_id, 'allowance_id', NULL,
                              'ended_allowance_id', v_ended_id, 'existing_allowance_id', v_existing_id);
  END IF;

  -- The ended allowance's override goes back to auto (checked after the conflict: a running grant keeps its own).
  -- A manual admin override (any other reason) is left alone.
  UPDATE public.organization
     SET work_access_mode = 'auto', work_access_reason = NULL, work_access_until = NULL,
         work_access_updated_by = v_actor, work_access_updated_at = v_now
   WHERE id = p_org_id AND work_access_mode = 'force_allow' AND starts_with(coalesce(work_access_reason, ''), 'Allowance');

  BEGIN
    INSERT INTO public.workspace_allowances
      (organization_id, kind, amount_usd, starts_at, expires_at, on_end, invoiced, reason, set_by, approved_by,
       approved_at, status, dedupe_key)
    VALUES
      (p_org_id, 'prepaid', v_pkg.grant_usd, v_now, v_now + make_interval(days => v_pkg.validity_days),
       'continue_billed', true,
       'Usage grant: ' || v_pkg.label || ' · ' || coalesce(nullif(btrim(p_payment_intent_id), ''), p_session_id),
       v_actor, v_actor, v_now, 'active', v_dedupe)
    RETURNING id INTO v_grant_id;
  EXCEPTION WHEN unique_violation THEN
    -- An allowance granted at the same moment by a writer that does not lock the workspace (the backoffice).
    SELECT id INTO v_existing_id
      FROM public.workspace_allowances WHERE organization_id = p_org_id AND status = 'active' LIMIT 1;
    RETURN jsonb_build_object('status', 'grant_conflict', 'activation_fee_id', v_fee_id, 'allowance_id', NULL,
                              'ended_allowance_id', v_ended_id, 'existing_allowance_id', v_existing_id);
  END;

  RETURN jsonb_build_object('status', 'activated', 'activation_fee_id', v_fee_id, 'allowance_id', v_grant_id,
                            'ended_allowance_id', v_ended_id);
END;
$$;

COMMENT ON FUNCTION public.activate_package_checkout(text, text, text, integer, text, text, text) IS
  '454: a card package purchase in one transaction, keyed on the Checkout session: activation_paid_at, the activation_fees row (source stripe_checkout), a running trial or budget ended with its override, and the usage grant (prepaid, dedupe checkout:<session>). Retries finish what is missing. Returns {status: activated | already_done | amount_mismatch | grant_conflict | unknown_package | unknown_organization | invalid_request, activation_fee_id, allowance_id, ended_allowance_id}.';

-- 2. A code for an invoice deal ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.redeem_package_code(
  p_code text,
  p_org_id text,
  p_email text,
  p_user_id text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_now timestamptz := now();
  v_code text := upper(btrim(coalesce(p_code, '')));
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_row public.package_codes%ROWTYPE;
  v_org public.organization%ROWTYPE;
  v_pkg public.billing_packages%ROWTYPE;
  v_reason text;
  v_flag boolean;
  v_card boolean;
  v_grant numeric(12, 2);
  v_days integer;
  v_label text;
  v_preview text;
  v_recommendation_id uuid;
BEGIN
  -- The refusals, in the contract's order. The first that applies is recorded and returned.
  IF (SELECT count(*) FROM public.package_code_attempts
       WHERE organization_id = p_org_id AND created_at > v_now - interval '24 hours') >= 10 THEN
    v_reason := 'too_many_attempts';
  END IF;

  IF v_reason IS NULL THEN
    -- Two redemptions of one code: the second waits here, then reads it used.
    SELECT * INTO v_row FROM public.package_codes WHERE code = v_code FOR UPDATE;
    IF NOT FOUND THEN
      v_reason := 'not_found';
    ELSIF v_row.redeemed_at IS NOT NULL AND v_row.redeemed_org_id = p_org_id AND v_row.recommendation_id IS NOT NULL THEN
      -- The same workspace again (a retried request): the first redemption's answer, nothing written or counted.
      RETURN jsonb_build_object(
        'ok', true, 'already_redeemed', true, 'recommendation_id', v_row.recommendation_id,
        'blocked', coalesce((SELECT dispatch_suspended AND dispatch_suspended_reason = 'card_required'
                               FROM public.organization WHERE id = p_org_id), false),
        'package_id', v_row.package_id,
        'grant_usd', coalesce(v_row.grant_usd, (SELECT grant_usd FROM public.billing_packages WHERE id = v_row.package_id)),
        'validity_days', coalesce(v_row.validity_days,
                                  (SELECT validity_days FROM public.billing_packages WHERE id = v_row.package_id)));
    ELSIF NOT v_row.active THEN
      v_reason := 'inactive';
    ELSIF v_row.expires_at <= v_now THEN
      v_reason := 'expired';
    ELSIF v_row.redeemed_at IS NOT NULL THEN
      v_reason := 'used';
    ELSIF (v_row.email_domain IS NOT NULL
           AND (position('@' IN v_email) = 0 OR split_part(v_email, '@', 2) <> v_row.email_domain))
       OR (v_row.email_exact IS NOT NULL AND v_email <> v_row.email_exact) THEN
      v_reason := 'email_mismatch';
    END IF;
  END IF;

  IF v_reason IS NULL THEN
    SELECT * INTO v_org FROM public.organization WHERE id = p_org_id FOR UPDATE;
    v_flag := false;
    -- Archived as the backoffice reads it (app/cs/deletion/exclusion.ts): the deleted marker, the 'archived'
    -- dispatch reason, or an open workspace_deletions request. A workspace that does not exist counts as deleted.
    IF FOUND AND NOT v_org.deleted AND v_org.dispatch_suspended_reason IS DISTINCT FROM 'archived'
       AND to_regclass('public.workspace_deletions') IS NOT NULL THEN
      EXECUTE 'SELECT EXISTS (SELECT 1 FROM public.workspace_deletions
                               WHERE organization_id = $1 AND status NOT IN (''cancelled'', ''reversed''))'
        INTO v_flag USING p_org_id;
    END IF;
    IF v_org.id IS NULL OR v_org.deleted OR v_org.dispatch_suspended_reason = 'archived' OR v_flag THEN
      v_reason := 'archived';
    ELSIF v_org.billing_cohort = 'existing' THEN
      v_reason := 'existing_cohort';
    ELSIF EXISTS (SELECT 1 FROM public.workspace_allowances
                   WHERE organization_id = p_org_id AND status = 'active' AND starts_with(reason, 'Usage grant: ')) THEN
      v_reason := 'already_activated_with_grant';
    ELSIF EXISTS (SELECT 1 FROM public.cs_recommendations
                   WHERE organization_id = p_org_id AND status = 'proposed'
                     AND starts_with(dedupe_key, 'package_code:')) THEN
      -- One code per workspace (B14): an earlier code's proposal still waits for approval or dismissal.
      v_reason := 'package_pending';
    END IF;
  END IF;

  IF v_reason IS NOT NULL THEN
    INSERT INTO public.package_code_attempts (organization_id, code_tried, reason)
    VALUES (p_org_id, left(v_code, 200), v_reason);
    RETURN jsonb_build_object('ok', false, 'reason', v_reason);
  END IF;

  -- The terms: the code's own (a custom deal, or an override on a package), else the package's as they are now.
  IF v_row.package_id IS NOT NULL THEN
    SELECT * INTO v_pkg FROM public.billing_packages WHERE id = v_row.package_id;
  END IF;
  v_grant := coalesce(v_row.grant_usd, v_pkg.grant_usd);
  v_days := coalesce(v_row.validity_days, v_pkg.validity_days);
  v_label := coalesce(v_pkg.label, 'Custom');
  v_preview := format('usage grant (deployment), %s USD for %s days from approval, then regular billing',
                      to_char(v_grant, 'FM999999999990.00'), v_days);

  -- The proposal the backoffice's Today shows. Its payload is the one the Commercial panel writes for a usage
  -- grant of kind prepaid (app/cs/commercial/forms.ts parseCommercialForm 'allowance' with usage_grant 1, and
  -- proposeCommercial in apply.ts), without expires_at: the backoffice sets it at approval, validity_days from
  -- then. The row itself does not expire (expires_at NULL): an invoice deal waits for its approval.
  INSERT INTO public.cs_recommendations
    (organization_id, kind, status, title, payload, grounding, reason, created_by, dedupe_key, expires_at)
  VALUES
    (p_org_id, 'allowance', 'proposed',
     left(v_preview || ' for ' || coalesce(nullif(v_org.name, ''), p_org_id), 200),
     jsonb_build_object(
       'kind', 'prepaid',
       'amount_usd', v_grant,
       'on_end', 'continue_billed',
       'stripe_invoice_id', NULL,
       'invoiced', true,
       'usage_grant', true,
       'preview', v_preview,
       'requires_super_admin', true,
       'source', 'package_code',
       'validity_days', v_days,
       'invoice_ref', v_row.invoice_ref,
       'package_code', v_row.code,
       'package_id', v_row.package_id),
     jsonb_build_object('facts', '[]'::jsonb, 'source', 'package_code'),
     left(v_label || ' · ' || v_row.invoice_ref, 500),
     'system:package_code',
     'package_code:' || v_row.code,
     NULL)
  RETURNING id INTO v_recommendation_id;

  UPDATE public.package_codes
     SET redeemed_org_id = p_org_id, redeemed_by = p_user_id, redeemed_at = v_now,
         recommendation_id = v_recommendation_id
   WHERE code = v_row.code;

  UPDATE public.organization SET activation_paid_at = v_now WHERE id = p_org_id AND activation_paid_at IS NULL;

  INSERT INTO public.activation_fees
    (organization_id, amount_paid_cents, amount_discounted_cents, paid_at, activated_by, metadata, source, package_id,
     invoice_ref, invoiced_price_cents)
  VALUES
    (p_org_id, 0, 0, v_now, p_user_id, jsonb_build_object('package_code', v_row.code), 'package_code', v_row.package_id,
     v_row.invoice_ref, round(v_row.price_usd * 100)::integer);

  -- B21: blocked until approved, unless a card is on file. A card is what Modal's _has_card_on_file counts
  -- (billing_service.py: stripe_payment_method_id, card_last4 or card_brand). A workspace already paused for
  -- another reason keeps that reason (as the hourly card-required gate does).
  v_card := EXISTS (
    SELECT 1 FROM public.billing_customers
     WHERE organization_id = p_org_id
       AND (coalesce(stripe_payment_method_id, '') <> '' OR coalesce(card_last4, '') <> '' OR coalesce(card_brand, '') <> '')
  );
  IF NOT v_card THEN
    UPDATE public.organization
       SET dispatch_suspended = true, dispatch_suspended_reason = 'card_required', dispatch_suspended_at = v_now
     WHERE id = p_org_id AND dispatch_suspended IS NOT TRUE;
  END IF;

  RETURN jsonb_build_object('ok', true, 'recommendation_id', v_recommendation_id, 'blocked', NOT v_card,
                            'package_id', v_row.package_id, 'grant_usd', v_grant, 'validity_days', v_days);
END;
$$;

COMMENT ON FUNCTION public.redeem_package_code(text, text, text, text) IS
  '454: redeem an activation code (upper-cased) for a workspace with the person''s verified email. Refusals are recorded in package_code_attempts and returned as {ok: false, reason}. Success, in one transaction: the code used, activation_paid_at, an activation_fees row (source package_code, 0 paid, invoiced_price_cents), one cs_recommendations allowance proposal (usage grant, prepaid, invoiced) and card_required when no card is on file. Returns {ok: true, recommendation_id, blocked, package_id, grant_usd, validity_days}.';

-- 3. A refund or dispute of a card purchase -------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.end_package_grant_for_payment(
  p_payment_intent_id text,
  p_kind text,
  p_refunded_cents integer,
  p_amount_cents integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_now timestamptz := now();
  v_fee public.activation_fees%ROWTYPE;
  v_grant public.workspace_allowances%ROWTYPE;
  v_actor text;
  v_original numeric;
  v_new numeric(12, 2);
  v_drawn numeric;
BEGIN
  IF p_kind IS NULL OR p_kind NOT IN ('refund', 'dispute')
     OR (p_kind = 'refund' AND (coalesce(p_amount_cents, 0) <= 0 OR p_refunded_cents IS NULL)) THEN
    RETURN jsonb_build_object('status', 'unchanged', 'reason', 'invalid_request', 'allowance_id', NULL,
                              'amount_usd', NULL);
  END IF;
  v_actor := 'system:stripe_' || p_kind;

  -- The payment intent -> its Checkout session -> the grant written for that session.
  SELECT * INTO v_fee
    FROM public.activation_fees
   WHERE stripe_payment_intent_id = p_payment_intent_id AND stripe_checkout_session_id IS NOT NULL
   ORDER BY created_at DESC
   LIMIT 1;
  IF v_fee.id IS NOT NULL THEN
    SELECT * INTO v_grant
      FROM public.workspace_allowances
     WHERE dedupe_key = 'checkout:' || v_fee.stripe_checkout_session_id
     FOR UPDATE;
  END IF;
  IF v_grant.id IS NULL THEN
    RETURN jsonb_build_object('status', 'not_found', 'allowance_id', NULL, 'amount_usd', NULL);
  END IF;

  -- Already ended, spent or expired: nothing to do (a retried webhook lands here too).
  IF v_grant.status <> 'active' THEN
    RETURN jsonb_build_object('status', 'unchanged', 'allowance_id', v_grant.id, 'amount_usd', v_grant.amount_usd);
  END IF;

  -- B18: a dispute or a full refund ends the grant.
  IF p_kind = 'dispute' OR p_refunded_cents >= p_amount_cents THEN
    UPDATE public.workspace_allowances
       SET status = 'ended', ended_by = v_actor, ended_at = v_now
     WHERE id = v_grant.id;
    RETURN jsonb_build_object('status', 'ended', 'allowance_id', v_grant.id, 'amount_usd', v_grant.amount_usd);
  END IF;

  IF p_refunded_cents <= 0 THEN
    RETURN jsonb_build_object('status', 'unchanged', 'allowance_id', v_grant.id, 'amount_usd', v_grant.amount_usd);
  END IF;

  -- B27: the refunded share of the grant as it was bought (the fee row's package terms), so the same refund
  -- total gives the same amount however often it arrives, and a later, larger refund total lowers it further.
  v_original := coalesce(
    (v_fee.metadata -> 'package' ->> 'grant_usd')::numeric,
    (SELECT grant_usd FROM public.billing_packages WHERE id = v_fee.package_id),
    v_grant.amount_usd);
  v_new := round(v_original * (1 - p_refunded_cents::numeric / p_amount_cents), 2);

  SELECT coalesce(sum(amount_usd), 0) INTO v_drawn
    FROM public.billing_allowance_deductions WHERE allowance_id = v_grant.id;

  IF v_new <= 0 OR v_drawn >= v_new THEN
    -- What is already drawn covers the reduced grant: it is spent (B20 applies from here).
    UPDATE public.workspace_allowances
       SET status = 'ended', ended_by = v_actor, ended_at = v_now,
           amount_usd = CASE WHEN v_new > 0 AND v_new < amount_usd THEN v_new ELSE amount_usd END
     WHERE id = v_grant.id
    RETURNING * INTO v_grant;
    RETURN jsonb_build_object('status', 'ended', 'allowance_id', v_grant.id, 'amount_usd', v_grant.amount_usd);
  END IF;

  IF v_new >= v_grant.amount_usd THEN
    RETURN jsonb_build_object('status', 'unchanged', 'allowance_id', v_grant.id, 'amount_usd', v_grant.amount_usd);
  END IF;

  UPDATE public.workspace_allowances SET amount_usd = v_new WHERE id = v_grant.id;
  RETURN jsonb_build_object('status', 'reduced', 'allowance_id', v_grant.id, 'amount_usd', v_new);
END;
$$;

COMMENT ON FUNCTION public.end_package_grant_for_payment(text, text, integer, integer) IS
  '454: a refund or dispute of a card package (activation_fees.stripe_payment_intent_id -> session -> grant checkout:<session>). A dispute or full refund ends the grant; a partial refund (p_refunded_cents = the refunded total so far) lowers amount_usd by that share of the grant as bought and ends it when billing_allowance_deductions already reach the new amount. Idempotent. Returns {status: ended | reduced | not_found | unchanged, allowance_id, amount_usd}.';

-- Access: the service role only ------------------------------------------------------------------------------
-- Functions are executable by PUBLIC by default, and Supabase grants new functions to anon and authenticated.

REVOKE ALL ON FUNCTION public.activate_package_checkout(text, text, text, integer, text, text, text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.redeem_package_code(text, text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.end_package_grant_for_payment(text, text, integer, integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.activate_package_checkout(text, text, text, integer, text, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.redeem_package_code(text, text, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.end_package_grant_for_payment(text, text, integer, integer) TO service_role;

-- Fail the file if a browser key can still execute a function.
DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY['public.activate_package_checkout(text, text, text, integer, text, text, text)',
                           'public.redeem_package_code(text, text, text, text)',
                           'public.end_package_grant_for_payment(text, text, integer, integer)'] LOOP
    IF has_function_privilege('anon', f, 'EXECUTE') OR has_function_privilege('authenticated', f, 'EXECUTE') THEN
      RAISE EXCEPTION '454: anon or authenticated can still execute %', f;
    END IF;
    IF NOT has_function_privilege('service_role', f, 'EXECUTE') THEN
      RAISE EXCEPTION '454: service_role cannot execute %', f;
    END IF;
  END LOOP;
END $$;

-- Verify (read-only):
-- select proname, prosecdef, proconfig from pg_proc
--  where proname in ('activate_package_checkout', 'redeem_package_code', 'end_package_grant_for_payment');
--   -> three rows, prosecdef true, proconfig {search_path=public}
-- select has_function_privilege('anon', 'public.redeem_package_code(text, text, text, text)', 'EXECUTE');  -- false
