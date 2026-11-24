-- ============================================================
-- Migration: 451_customer-requests-switch-to-full (stage: next-release/451; renumber at promotion if 451 is taken)
-- Date:      2026-11-21
-- Purpose:   A phone-only person can ask for full Sellton from the web billing page ("Switch to full"). The request
--            is a customer_requests row of the new type 'switch_to_full'. The backoffice posts it to the CS Slack;
--            staff turn the person's seat into a web seat and the person is emailed (Borce, 21 Nov 2026).
-- Projects:  selltonai-database/supabase (owner). selltonai (the app) writes the new type from its request dialog;
--            backoffice reads it (the Slack notifier, the workspace page). selltonai-modal, the mobile service and
--            the engine: none.
-- Contract:  customer_requests.type CHECK gains 'switch_to_full'; every other column, default, trigger, grant and the
--            RLS state are 391's, unchanged. No rows change. body is the person's own note (optional); details is
--            '{}' for this type. Application code: none must ship together with this file (until the app writes the
--            type, nothing uses it).
-- Depends:   391 (customer_requests), 439 (trial_extension).
-- Rollback:  rollback/451_customer-requests-switch-to-full.rollback.sql (439's CHECK; switch_to_full rows become
--            feedback rows with details.kind 'switch_to_full', so nothing is lost).
-- ============================================================

SET LOCAL lock_timeout = '10s';

ALTER TABLE public.customer_requests DROP CONSTRAINT IF EXISTS customer_requests_type_check;
ALTER TABLE public.customer_requests
  ADD CONSTRAINT customer_requests_type_check
  CHECK (type IN ('feedback', 'mailboxes', 'leave', 'trial_extension', 'switch_to_full'));

COMMENT ON COLUMN public.customer_requests.type IS
  'feedback | mailboxes | leave | trial_extension (439) | switch_to_full (451: a phone-only person asks for full Sellton).';
