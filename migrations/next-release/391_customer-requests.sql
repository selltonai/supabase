-- ============================================================
-- Migration: customer-requests (stage: next-release/391; renumber at promotion if 391 is taken on main)
-- Date:      2026-10-07
-- Purpose:   KAN-322 FR-A9 (D19). Requests a customer sends from the app, stored per organization:
--              feedback   Help → "Submit feedback" (bug / idea / question, optional screenshot)
--              mailboxes  Email accounts → "Request mailboxes" (how many, own or new domain, names)
--              leave      Settings → Billing → "Close my account" (a request only: nothing is closed automatically)
-- Projects:  selltonai POST /api/customer-requests writes (service role, workspace from requireAuth only).
--            backoffice lists them on the organization page and posts each new one to Slack once
--            (requests:notify; slack_notified_at marks it).
-- Contract:  Additive. New table + private bucket. No existing table, function or policy changes. Safe to drop while empty.
-- Access:    Only the service role reads or writes (the app route and the backoffice). anon and authenticated get no
--            table privileges (Supabase grants them by default; the old public.feedback table shows what that leads to).
--            RLS is on with an org-scoped SELECT policy (the 338 convention) as a second layer.
--            The bucket has NO storage.objects policies: only the service role can upload or sign a URL.
-- Rollback:  DROP TABLE IF EXISTS public.customer_requests;
--            DELETE FROM storage.buckets WHERE id = 'customer-request-files';  (after deleting its objects)
-- ============================================================

CREATE TABLE IF NOT EXISTS public.customer_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  user_id text NOT NULL,
  type text NOT NULL CHECK (type IN ('feedback', 'mailboxes', 'leave')),
  status text NOT NULL DEFAULT 'new' CHECK (status IN ('new', 'in_progress', 'done')),
  -- The customer's own words (feedback: required; leave: optional; mailboxes: unused).
  body text CHECK (body IS NULL OR char_length(body) <= 5000),
  -- Named, type-specific fields the route validates: feedback {kind}; mailboxes {count, domain_choice, names}.
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  -- The app page the request was sent from.
  page text CHECK (page IS NULL OR char_length(page) <= 500),
  -- Object path in the customer-request-files bucket: <organization_id>/<request id>/<file name>.
  attachment_path text,
  -- Slack: set once the backoffice has posted the request; attempts bound the retries of a failing post.
  slack_notified_at timestamptz,
  -- Slack: when a notifier run claimed the row; another run skips it until the claim is 10 minutes old (a crash).
  slack_claimed_at timestamptz,
  slack_attempts integer NOT NULL DEFAULT 0,
  slack_last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_customer_requests_org_created
  ON public.customer_requests (organization_id, created_at DESC);
-- The notifier's queue: new rows not yet posted, oldest first.
CREATE INDEX IF NOT EXISTS idx_customer_requests_slack_pending
  ON public.customer_requests (created_at)
  WHERE slack_notified_at IS NULL;

CREATE OR REPLACE FUNCTION public.update_customer_requests_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.update_customer_requests_updated_at() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS customer_requests_updated_at ON public.customer_requests;
CREATE TRIGGER customer_requests_updated_at
  BEFORE UPDATE ON public.customer_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.update_customer_requests_updated_at();

REVOKE ALL ON TABLE public.customer_requests FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.customer_requests TO service_role;

ALTER TABLE public.customer_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Organization members can view their requests" ON public.customer_requests;
CREATE POLICY "Organization members can view their requests" ON public.customer_requests
  FOR SELECT USING (organization_id = current_setting('app.current_org_id', true));

COMMENT ON TABLE public.customer_requests IS
  'KAN-322 FR-A9: requests from the app (feedback, mailboxes, leave), per organization. Written by the app route with the service role; read and Slack-posted by the backoffice.';

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('customer-request-files', 'customer-request-files', false, 5242880,
        ARRAY['image/png', 'image/jpeg', 'image/webp', 'image/gif']::text[])
ON CONFLICT (id) DO UPDATE SET
  public = false,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DO $$
BEGIN
  IF has_table_privilege('anon', 'public.customer_requests', 'SELECT')
     OR has_table_privilege('authenticated', 'public.customer_requests', 'SELECT')
     OR has_table_privilege('anon', 'public.customer_requests', 'INSERT')
     OR has_table_privilege('authenticated', 'public.customer_requests', 'INSERT') THEN
    RAISE EXCEPTION '391: anon or authenticated can still read or write customer_requests';
  END IF;
END $$;

-- Verify (read-only):
-- SELECT has_table_privilege('anon', 'public.customer_requests', 'SELECT') AS anon_select,      -- false
--        has_table_privilege('authenticated', 'public.customer_requests', 'SELECT') AS auth_select, -- false
--        has_table_privilege('service_role', 'public.customer_requests', 'INSERT') AS service_insert; -- true
-- SELECT id, public, file_size_limit, allowed_mime_types FROM storage.buckets WHERE id = 'customer-request-files';
