-- SP-38: Add provider delivery tracking fields for notification emails

ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS email_delivery_status TEXT,
  ADD COLUMN IF NOT EXISTS email_last_event_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS email_provider_event JSONB;

CREATE INDEX IF NOT EXISTS idx_notifications_resend_message_id
  ON public.notifications (resend_message_id)
  WHERE resend_message_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_notifications_email_delivery_status
  ON public.notifications (email_delivery_status)
  WHERE email_delivery_status IS NOT NULL;

UPDATE public.notifications
SET
  email_delivery_status = COALESCE(email_delivery_status, 'accepted'),
  email_last_event_at = COALESCE(email_last_event_at, email_sent_at, created_at)
WHERE email_sent = TRUE
  AND email_delivery_status IS NULL;
