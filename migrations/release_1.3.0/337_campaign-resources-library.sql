-- 337 — Campaign resource library: org-level catalogue of shareable resources
-- (external links + uploaded files) that Sellton offers to a lead when they
-- reply positively, and teases in the opener.
--
-- Why: today the only reply-time share is email-only, case_study-only, and
-- auto-picked by vector similarity (email_generation_service inquiry path).
-- Operators want to curate ANY resource — a demo video, a landing page, a
-- one-pager — and have the copywriter tease it in the opener + share it on a
-- "yes, send it" reply across BOTH email and LinkedIn (reply_handler_service).
--
-- Model: this is an ORG-LEVEL library (not campaign-scoped rows). Which
-- resources a given campaign may offer is selected per-campaign and stored on
-- `campaigns.metadata.offered_resource_ids` (uuid[] of campaign_resources.id) —
-- consistent with the existing metadata flags (is_existing_connections,
-- ground_on_documents). A resource is EXACTLY one of: an external `url`
-- (video / landing page / article) OR a backing `file_id` in
-- organization_files (PDF / deck we already store + can mint /d/ short links
-- for via document_share_service.create_short_url). `kind` labels what it is so
-- the copywriter can tease it accurately without leaking the URL.
--
-- Affected projects:
--   - selltonai: resource CRUD API + campaign wizard curation UI read/write this.
--   - selltonai-modal: email_context_builder (tease) + reply_handler (share)
--     read this by id from campaigns.metadata.offered_resource_ids.
-- Deploy: this migration before the selltonai resource routes + Modal readers.
--
-- Additive + non-breaking. Safe to drop while empty.

CREATE TABLE IF NOT EXISTS public.campaign_resources (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  -- What kind of resource this is — drives how the copywriter frames the tease
  -- ("a short demo video", "a case study", "a one-pager") without seeing the URL.
  kind text NOT NULL CHECK (kind IN (
    'video', 'landing_page', 'article', 'pdf', 'deck', 'case_study', 'other'
  )),
  label text NOT NULL,
  -- Exactly one of (url, file_id) is set — enforced below. `url` = external link
  -- (shared as-is); `file_id` = an uploaded org file (shared via a minted /d/
  -- short link so opens are tracked in document_access_events).
  url text,
  file_id uuid REFERENCES public.organization_files(id) ON DELETE CASCADE,
  -- Operator note: what the resource covers + when to offer it. Fed to the
  -- copywriter as tease context (label + kind + description only, never the URL).
  description text,
  is_active boolean NOT NULL DEFAULT true,
  created_by text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  -- A resource is an external link XOR a backing file — never both, never neither.
  CONSTRAINT campaign_resources_url_xor_file CHECK (
    (url IS NOT NULL AND file_id IS NULL)
    OR (url IS NULL AND file_id IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS idx_campaign_resources_org_id
  ON public.campaign_resources(organization_id);
-- Library list view shows active resources for the org first.
CREATE INDEX IF NOT EXISTS idx_campaign_resources_org_active
  ON public.campaign_resources(organization_id, created_at DESC)
  WHERE is_active;

CREATE OR REPLACE FUNCTION public.update_campaign_resources_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS campaign_resources_updated_at ON public.campaign_resources;
CREATE TRIGGER campaign_resources_updated_at
  BEFORE UPDATE ON public.campaign_resources
  FOR EACH ROW
  EXECUTE FUNCTION public.update_campaign_resources_updated_at();

ALTER TABLE public.campaign_resources ENABLE ROW LEVEL SECURITY;

-- Org-scoped policies (operators manage their library in the app). Modal reads
-- via service_role, which bypasses RLS.
DROP POLICY IF EXISTS "Users can view campaign resources for their organization" ON public.campaign_resources;
CREATE POLICY "Users can view campaign resources for their organization" ON public.campaign_resources
  FOR SELECT USING (organization_id = current_setting('app.current_org_id', true));

DROP POLICY IF EXISTS "Users can insert campaign resources for their organization" ON public.campaign_resources;
CREATE POLICY "Users can insert campaign resources for their organization" ON public.campaign_resources
  FOR INSERT WITH CHECK (organization_id = current_setting('app.current_org_id', true));

DROP POLICY IF EXISTS "Users can update campaign resources for their organization" ON public.campaign_resources;
CREATE POLICY "Users can update campaign resources for their organization" ON public.campaign_resources
  FOR UPDATE USING (organization_id = current_setting('app.current_org_id', true));

DROP POLICY IF EXISTS "Users can delete campaign resources for their organization" ON public.campaign_resources;
CREATE POLICY "Users can delete campaign resources for their organization" ON public.campaign_resources
  FOR DELETE USING (organization_id = current_setting('app.current_org_id', true));

COMMENT ON TABLE public.campaign_resources IS
  'Org-level library of shareable resources (external links XOR uploaded files). Campaigns select which to offer via campaigns.metadata.offered_resource_ids (uuid[]). Teased in the opener and shared on a positive reply (reply_handler_service) — file-backed resources via a minted /d/ short link, external URLs as-is.';

-- Verify:
--   select column_name, data_type, column_default
--   from information_schema.columns
--   where table_name = 'campaign_resources' order by ordinal_position;
