-- ============================================================
-- Migration: 366_contact-automation-holds
-- Date:      2026-08-25
-- Purpose:   Separate a hard automation hold from stop_drafts, which also
--            marks ordinary outbound sequence boundaries.
-- Projects:  selltonai-database/supabase (owner), selltonai and
--            selltonai-modal (writers/readers).
-- Contract:  Additive nullable contact fields. Deploy this migration before
--            either application begins reading or writing the new fields.
-- Depends:   public.contacts and the outreach fields introduced by migration
--            250/328.
-- ============================================================

ALTER TABLE public.contacts
  ADD COLUMN IF NOT EXISTS automation_hold_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS automation_hold_reason TEXT;

COMMENT ON COLUMN public.contacts.automation_hold_at IS
  'When set, CRM next-best-action, nurture, and LinkedIn reply drafting must not create new automated outreach for this contact.';

COMMENT ON COLUMN public.contacts.automation_hold_reason IS
  'Stable machine-readable reason for automation_hold_at, such as unsubscribe, do_not_contact, negative_manual_takeover, negative_reply, or terminal_stage.';

-- stop_drafts historically represented both normal sequence completion and a
-- true human-requested stop. Backfill only records with an independent hard-
-- stop marker; stop_drafts by itself intentionally remains an outbound sender
-- boundary rather than an automation hold.
UPDATE public.contacts
SET
  automation_hold_at = COALESCE(
    unsubscribed_at,
    stage_updated_at,
    last_reply_at,
    updated_at,
    NOW()
  ),
  automation_hold_reason = CASE
    WHEN unsubscribed_at IS NOT NULL THEN 'unsubscribe'
    WHEN COALESCE(do_not_contact, FALSE) THEN 'do_not_contact'
    WHEN UPPER(COALESCE(last_reply_sentiment, last_email_sentiment, '')) IN ('NEGATIVE', 'VERY_NEGATIVE')
      THEN 'negative_reply'
    WHEN pipeline_stage IN ('NOT_INTERESTED', 'CLOSED_LOST') THEN 'terminal_stage'
    ELSE 'legacy_hard_stop'
  END
WHERE automation_hold_at IS NULL
  AND COALESCE(stop_drafts, FALSE)
  AND (
    unsubscribed_at IS NOT NULL
    OR COALESCE(do_not_contact, FALSE)
    OR pipeline_stage IN ('NOT_INTERESTED', 'CLOSED_LOST')
    OR UPPER(COALESCE(last_reply_sentiment, last_email_sentiment, '')) IN ('NEGATIVE', 'VERY_NEGATIVE')
  );

-- Verification after apply:
-- SELECT column_name, data_type
-- FROM information_schema.columns
-- WHERE table_schema = 'public'
--   AND table_name = 'contacts'
--   AND column_name IN ('automation_hold_at', 'automation_hold_reason');
--
-- SELECT automation_hold_reason, COUNT(*)
-- FROM public.contacts
-- WHERE automation_hold_at IS NOT NULL
-- GROUP BY automation_hold_reason;
