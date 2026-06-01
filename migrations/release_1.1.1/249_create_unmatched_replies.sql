-- Migration: Persist unmatched incoming replies
-- Release: 1.1.1
-- Purpose: Keep inbound replies that cannot be mapped to a contact/campaign so
-- support and later resolvers can recover them instead of dropping the event.

CREATE TABLE IF NOT EXISTS public.unmatched_replies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  email_id text,
  thread_id text,
  account_id text,
  user_id text,
  from_email text,
  from_name text,
  to_emails text[] NOT NULL DEFAULT '{}'::text[],
  cc_emails text[] NOT NULL DEFAULT '{}'::text[],
  subject text,
  message text,
  received_at timestamptz NOT NULL DEFAULT now(),
  raw_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  classification_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  resolution_status text NOT NULL DEFAULT 'unmatched'
    CHECK (resolution_status IN ('unmatched', 'resolved', 'ignored')),
  resolved_contact_id uuid REFERENCES public.contacts(id) ON DELETE SET NULL,
  resolved_company_id uuid REFERENCES public.companies(id) ON DELETE SET NULL,
  resolved_campaign_id uuid REFERENCES public.campaigns(id) ON DELETE SET NULL,
  resolved_by_user_id text,
  resolved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_unmatched_replies_email_id
  ON public.unmatched_replies (email_id)
  WHERE email_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_unmatched_replies_org_status
  ON public.unmatched_replies (organization_id, resolution_status, received_at DESC);

CREATE INDEX IF NOT EXISTS idx_unmatched_replies_thread_id
  ON public.unmatched_replies (thread_id)
  WHERE thread_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_unmatched_replies_received_at
  ON public.unmatched_replies (received_at);

CREATE OR REPLACE FUNCTION public.update_unmatched_replies_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS unmatched_replies_updated_at ON public.unmatched_replies;
CREATE TRIGGER unmatched_replies_updated_at
  BEFORE UPDATE ON public.unmatched_replies
  FOR EACH ROW
  EXECUTE FUNCTION public.update_unmatched_replies_updated_at();

ALTER TABLE public.unmatched_replies ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view unmatched replies for their organization"
  ON public.unmatched_replies;

CREATE POLICY "Users can view unmatched replies for their organization"
  ON public.unmatched_replies
  FOR SELECT
  USING (organization_id = current_setting('app.current_org_id', true));

DROP POLICY IF EXISTS "Users can insert unmatched replies for their organization"
  ON public.unmatched_replies;

CREATE POLICY "Users can insert unmatched replies for their organization"
  ON public.unmatched_replies
  FOR INSERT
  WITH CHECK (organization_id = current_setting('app.current_org_id', true));

DROP POLICY IF EXISTS "Users can update unmatched replies for their organization"
  ON public.unmatched_replies;

CREATE POLICY "Users can update unmatched replies for their organization"
  ON public.unmatched_replies
  FOR UPDATE
  USING (organization_id = current_setting('app.current_org_id', true));

COMMENT ON TABLE public.unmatched_replies IS
  'Incoming replies that the webhook could not confidently map to a contact/campaign.';

COMMENT ON COLUMN public.unmatched_replies.classification_snapshot IS
  'Webhook analysis snapshot: relevance, classification, sub-intent, sentiment, OOO, and policy.';
