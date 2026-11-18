-- ============================================================
-- Migration: 439_customer-requests-trial-extension (stage: next-release/439; renumber at promotion if 439 is taken)
-- Date:      2026-11-13
-- Purpose:   A customer can ask for more trial time from the app ("Request more time" in the trial-ending notice). The
--            request is a customer_requests row of the new type 'trial_extension'. The backoffice's customer-success
--            agent reads open ones (status new or in_progress), weighs the workspace (usage, the Brain's company
--            profile) and proposes the extension; a super admin approves or declines, and the request is marked done.
-- Projects:  selltonai-database/supabase (owner). selltonai (the app) writes the new type from its request dialog;
--            backoffice reads it (Org 360, the Slack notifier, the agent). selltonai-modal, the mobile service and the
--            engine: none.
-- Contract:  customer_requests.type CHECK gains 'trial_extension'; every other column, default, trigger, grant and the
--            RLS state are 391's, unchanged. No rows change. body is the customer's own reason (optional, like leave);
--            details is '{}' for this type. Application code: none must ship together with this file (until the app
--            writes the type, nothing uses it; the backoffice also accepts a feedback row with details.kind
--            'trial_extension').
-- Depends:   391 (customer_requests).
-- Rollback:  rollback/439_customer-requests-trial-extension.rollback.sql (391's CHECK; trial_extension rows become
--            feedback rows with details.kind 'trial_extension', so nothing is lost).
-- ============================================================

SET LOCAL lock_timeout = '10s';

ALTER TABLE public.customer_requests DROP CONSTRAINT IF EXISTS customer_requests_type_check;
ALTER TABLE public.customer_requests
  ADD CONSTRAINT customer_requests_type_check
  CHECK (type IN ('feedback', 'mailboxes', 'leave', 'trial_extension'));

COMMENT ON COLUMN public.customer_requests.type IS
  'feedback | mailboxes | leave | trial_extension (439: the customer asks for more trial time; body is their reason).';
