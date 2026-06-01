-- Migration: Positive follow-up reply metadata
-- Release: 1.1.1
-- Purpose: Preserve the last positive follow-up signal separately from the
-- generic last_email_intent JSON so cron can safely target follow-up flows.

ALTER TABLE public.contacts
  ADD COLUMN IF NOT EXISTS last_reply_sentiment text,
  ADD COLUMN IF NOT EXISTS last_reply_sub_intent text,
  ADD COLUMN IF NOT EXISTS last_reply_at timestamptz;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'contacts_last_reply_sentiment_chk'
      AND conrelid = 'public.contacts'::regclass
  ) THEN
    ALTER TABLE public.contacts
      ADD CONSTRAINT contacts_last_reply_sentiment_chk
      CHECK (
        last_reply_sentiment IS NULL
        OR last_reply_sentiment = ANY (
          ARRAY['VERY_POSITIVE', 'POSITIVE', 'NEUTRAL', 'NEGATIVE', 'VERY_NEGATIVE']
        )
      );
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_contacts_positive_followup_reply
  ON public.contacts (organization_id, pipeline_stage, last_reply_at DESC)
  WHERE last_reply_sentiment IN ('VERY_POSITIVE', 'POSITIVE')
    AND last_reply_sub_intent = 'FOLLOW_UP';

COMMENT ON COLUMN public.contacts.last_reply_sentiment IS
  'Sentiment of the most recent real-person incoming reply.';

COMMENT ON COLUMN public.contacts.last_reply_sub_intent IS
  'Sub-intent of the most recent real-person incoming reply.';

COMMENT ON COLUMN public.contacts.last_reply_at IS
  'Timestamp of the most recent real-person incoming reply.';

