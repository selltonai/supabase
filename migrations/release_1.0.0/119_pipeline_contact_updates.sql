-- Email Inbox Intent: contact-level fields only
-- Safe to run multiple times (idempotent for columns and indexes).
-- Assumes PostgreSQL.

-- 1) Add columns to public.contacts
ALTER TABLE public.contacts
  ADD COLUMN IF NOT EXISTS pipeline_stage text,
  ADD COLUMN IF NOT EXISTS ooo_until timestamptz,
  ADD COLUMN IF NOT EXISTS unsubscribed_at timestamptz,
  ADD COLUMN IF NOT EXISTS stop_drafts boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS last_email_sentiment text,
  ADD COLUMN IF NOT EXISTS last_email_intent jsonb,
  ADD COLUMN IF NOT EXISTS last_thread_id text,
  ADD COLUMN IF NOT EXISTS last_incoming_email_at timestamptz,
  ADD COLUMN IF NOT EXISTS stage_updated_at timestamptz;

-- 2) Add CHECK constraints for enum-like fields (conditional)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'contacts_pipeline_stage_chk'
  ) THEN
    ALTER TABLE public.contacts
      ADD CONSTRAINT contacts_pipeline_stage_chk
      CHECK (
        pipeline_stage IS NULL OR pipeline_stage = ANY (ARRAY[
          'PROSPECT',
          'LEAD',
          'APPOINTMENT_REQUESTED',
          'APPOINTMENT_SCHEDULED',
          'APPOINTMENT_CANCELLED',
          'PRESENTATION_SCHEDULED',
          'CONTRACT_NEGOTIATIONS',
          'AGREEMENT_IN_PRINCIPLE',
          'CLOSED_WON',
          'CLOSED_LOST',
          'REENGAGEMENT'
        ]::text[])
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'contacts_last_email_sentiment_chk'
  ) THEN
    ALTER TABLE public.contacts
      ADD CONSTRAINT contacts_last_email_sentiment_chk
      CHECK (
        last_email_sentiment IS NULL OR last_email_sentiment = ANY (ARRAY[
          'VERY_POSITIVE',
          'POSITIVE',
          'NEUTRAL',
          'NEGATIVE',
          'VERY_NEGATIVE'
        ]::text[])
      );
  END IF;
END
$$;

-- 3) Helpful indexes for runtime filters and automation
CREATE INDEX IF NOT EXISTS idx_contacts_pipeline_stage ON public.contacts (pipeline_stage);
CREATE INDEX IF NOT EXISTS idx_contacts_unsubscribed_at ON public.contacts (unsubscribed_at);
CREATE INDEX IF NOT EXISTS idx_contacts_ooo_until ON public.contacts (ooo_until);
CREATE INDEX IF NOT EXISTS idx_contacts_stop_drafts ON public.contacts (stop_drafts);
CREATE INDEX IF NOT EXISTS idx_contacts_last_incoming_email_at ON public.contacts (last_incoming_email_at);

-- Optional: JSONB index if you plan to filter within last_email_intent
-- CREATE INDEX IF NOT EXISTS idx_contacts_last_email_intent_gin ON public.contacts USING GIN (last_email_intent);

-- 4) Documentation comments
COMMENT ON COLUMN public.contacts.pipeline_stage IS 'Enum-like stage: PROSPECT | LEAD | APPOINTMENT_REQUESTED | APPOINTMENT_SCHEDULED | APPOINTMENT_CANCELLED | PRESENTATION_SCHEDULED | CONTRACT_NEGOTIATIONS | AGREEMENT_IN_PRINCIPLE | CLOSED_WON | CLOSED_LOST | REENGAGEMENT';
COMMENT ON COLUMN public.contacts.ooo_until IS 'Out-of-office return date; drafts should be blocked until this date when set';
COMMENT ON COLUMN public.contacts.unsubscribed_at IS 'Timestamp of unsubscribe; never auto-clear';
COMMENT ON COLUMN public.contacts.stop_drafts IS 'If true, do not generate or send drafts (OOO, unsubscribe, or stage gating)';
COMMENT ON COLUMN public.contacts.last_email_sentiment IS 'VERY_POSITIVE | POSITIVE | NEUTRAL | NEGATIVE | VERY_NEGATIVE';
COMMENT ON COLUMN public.contacts.last_email_intent IS 'Full JSON snapshot of last email analysis (relevance, classification, sub_intent, sentiment, ooo, policy)';
COMMENT ON COLUMN public.contacts.last_thread_id IS 'Last associated thread identifier from email system';
COMMENT ON COLUMN public.contacts.last_incoming_email_at IS 'Timestamp of most recent incoming email processed';
COMMENT ON COLUMN public.contacts.stage_updated_at IS 'Timestamp of last pipeline_stage change';