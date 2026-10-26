-- ============================================================
-- Migration: crm-play-lists (stage: next-release/411)
-- Date:      2026-10-26
-- Plan:      PLAN_PLAY_LISTS_PHONE_AND_WEB_2026_10_26.md (PL-1, PL-2), decided by Borce 2026-10-26
-- Purpose:   One CRM list per play, named after the play, so a play's companies and people
--            can be found with the People and Companies list filters.
--            1. crm_lists.campaign_id: the play a list belongs to (one list per play). When the
--               play is deleted the list stays (ON DELETE SET NULL).
--            2. crm_list_members.source also allows 'play'.
--            3. add_play_list_members(org, play, companies[], people[]): creates the play's list
--               when missing (kind campaign_output, named after the play, owned by the play's
--               owner) and adds the members once. Called by the phone service for its plays, and
--               by the triggers below for web plays.
--            4. Web plays: after rows are added to campaign_companies or campaign_contacts, the
--               companies and people go into the play's list, once the play has left draft.
--               When a play leaves draft, what it already has goes in. When a play is renamed,
--               its list's name follows.
--            Phone plays (lead_source = 'mobile') are skipped by the triggers: the phone service
--            adds its own kept companies and people through add_play_list_members.
--            5. get_companies_by_list: the Companies page list filter, one page of a list's
--               companies with the columns of get_companies_by_campaign (210), so a large list
--               never goes into a request URL.
-- Projects:  selltonai-database/supabase (owner). Readers: selltonai (People and Companies list
--            filters, Lists page), selltonai-modal (GET /lists returns campaign_id with `*`).
--            Writer: the mobile service (add_play_list_members), these triggers.
-- Contract:  Additive. No existing column, row or function changes; one CHECK widened. A list
--            failure never blocks adding a company or a person to a play: the trigger bodies
--            catch every error and raise a WARNING instead. Members are list rows only:
--            deleting a play list (KAN-334 crm_list_delete_batch) removes the list and its member
--            rows, never the companies, because play lists never set companies.crm_list_id.
--            No backfill job (Borce, 2026-10-26). A web play that has already left draft gets its
--            list when its next company or person is added; the list then starts with everything
--            the play already has, so it is never a partial list.
-- Depends:   public.crm_lists (237, 332, 346, 400), public.crm_list_members (315),
--            public.campaigns, public.campaign_companies (91), public.campaign_contacts (260),
--            public.companies, public.contacts.
-- Rollback:  rollback/411_crm-play-lists.rollback.sql
-- ============================================================

-- campaigns and crm_lists are read on every request; fail fast instead of queueing behind a
-- long transaction (the runner rolls the file back and it can be re-run).
SET LOCAL lock_timeout = '10s';

-- 1. The play a list belongs to ---------------------------------------------------------------

ALTER TABLE public.crm_lists
  ADD COLUMN IF NOT EXISTS campaign_id uuid REFERENCES public.campaigns(id) ON DELETE SET NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_crm_lists_campaign_id_unique
  ON public.crm_lists (campaign_id)
  WHERE campaign_id IS NOT NULL;

COMMENT ON COLUMN public.crm_lists.campaign_id IS
  'The play this list belongs to (one list per play, source campaign_output, named after the play). NULL for imported and hand-made lists, and once the play is deleted (the list stays).';

-- 2. Member kind 'play' --------------------------------------------------------------------------

ALTER TABLE public.crm_list_members
  DROP CONSTRAINT IF EXISTS crm_list_members_source_check;
ALTER TABLE public.crm_list_members
  ADD CONSTRAINT crm_list_members_source_check
  CHECK (source IN ('manual', 'campaign_selection', 'play'));

-- 3. Create the play's list when missing and add members once ------------------------------------

CREATE OR REPLACE FUNCTION public.add_play_list_members(
  p_organization_id text,
  p_campaign_id uuid,
  p_company_ids uuid[] DEFAULT '{}',
  p_contact_ids uuid[] DEFAULT '{}'
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_campaign record;
  v_list_id uuid;
BEGIN
  SELECT id, organization_id, name, user_id
  INTO v_campaign
  FROM public.campaigns
  WHERE id = p_campaign_id AND organization_id = p_organization_id;

  IF NOT FOUND THEN
    RETURN NULL;  -- no such play in this workspace: nothing is created
  END IF;

  INSERT INTO public.crm_lists (organization_id, name, source, row_count, campaign_id, user_id)
  VALUES (
    p_organization_id,
    coalesce(nullif(btrim(v_campaign.name), ''), 'Play'),
    'campaign_output',
    0,
    p_campaign_id,
    v_campaign.user_id
  )
  ON CONFLICT (campaign_id) WHERE campaign_id IS NOT NULL DO NOTHING;

  SELECT id INTO v_list_id
  FROM public.crm_lists
  WHERE campaign_id = p_campaign_id AND organization_id = p_organization_id;

  IF v_list_id IS NULL THEN
    RETURN NULL;  -- the play's list belongs to another workspace: never mix workspaces
  END IF;

  -- Only companies and people of this workspace become members.
  INSERT INTO public.crm_list_members (list_id, organization_id, company_id, source)
  SELECT DISTINCT v_list_id, p_organization_id, c.id, 'play'
  FROM public.companies c
  WHERE c.id = ANY (coalesce(p_company_ids, '{}'))
    AND c.organization_id = p_organization_id
  ON CONFLICT (list_id, organization_id, company_id) WHERE company_id IS NOT NULL DO NOTHING;

  INSERT INTO public.crm_list_members (list_id, organization_id, contact_id, source)
  SELECT DISTINCT v_list_id, p_organization_id, ct.id, 'play'
  FROM public.contacts ct
  WHERE ct.id = ANY (coalesce(p_contact_ids, '{}'))
    AND ct.organization_id = p_organization_id
  ON CONFLICT (list_id, organization_id, contact_id) WHERE contact_id IS NOT NULL DO NOTHING;

  UPDATE public.crm_lists l
  SET row_count = (SELECT count(*) FROM public.crm_list_members m WHERE m.list_id = v_list_id),
      updated_at = now()
  WHERE l.id = v_list_id;

  RETURN v_list_id;
END;
$$;

COMMENT ON FUNCTION public.add_play_list_members(text, uuid, uuid[], uuid[]) IS
  'Creates the play''s CRM list when missing (source campaign_output, named after the play, owned by the play''s owner) and adds the given companies and people once. Returns the list id, or NULL when the play is not in this workspace. Called by the mobile service for phone plays and by the play-list triggers for web plays.';

-- 4. Web plays: triggers ---------------------------------------------------------------------------

-- Everything a web play has: all its companies and people.
CREATE OR REPLACE FUNCTION public.play_list_fill(p_organization_id text, p_campaign_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN public.add_play_list_members(
    p_organization_id,
    p_campaign_id,
    coalesce((SELECT array_agg(cc.company_id) FROM public.campaign_companies cc
              WHERE cc.campaign_id = p_campaign_id AND cc.organization_id = p_organization_id), '{}'),
    coalesce((SELECT array_agg(DISTINCT ct.contact_id) FROM public.campaign_contacts ct
              WHERE ct.campaign_id = p_campaign_id AND ct.organization_id = p_organization_id), '{}')
  );
END;
$$;

-- A web play fills its list once it has left draft. Phone plays add their own members.
-- A play without a list yet gets everything it has; otherwise only the new rows go in.
CREATE OR REPLACE FUNCTION public.play_list_after_company_links()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  r record;
BEGIN
  BEGIN
    FOR r IN
      SELECT c.id AS campaign_id, c.organization_id, array_agg(DISTINCT n.company_id) AS company_ids,
             EXISTS (SELECT 1 FROM public.crm_lists l WHERE l.campaign_id = c.id) AS has_list
      FROM new_rows n
      JOIN public.campaigns c ON c.id = n.campaign_id
      WHERE c.status IS DISTINCT FROM 'draft'
        AND c.lead_source IS DISTINCT FROM 'mobile'
      GROUP BY c.id, c.organization_id
    LOOP
      IF r.has_list THEN
        PERFORM public.add_play_list_members(r.organization_id, r.campaign_id, r.company_ids, '{}');
      ELSE
        PERFORM public.play_list_fill(r.organization_id, r.campaign_id);
      END IF;
    END LOOP;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'play list (companies) skipped: % (%)', SQLERRM, SQLSTATE;
  END;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.play_list_after_contact_links()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  r record;
BEGIN
  BEGIN
    FOR r IN
      SELECT c.id AS campaign_id, c.organization_id, array_agg(DISTINCT n.contact_id) AS contact_ids,
             EXISTS (SELECT 1 FROM public.crm_lists l WHERE l.campaign_id = c.id) AS has_list
      FROM new_rows n
      JOIN public.campaigns c ON c.id = n.campaign_id
      WHERE c.status IS DISTINCT FROM 'draft'
        AND c.lead_source IS DISTINCT FROM 'mobile'
      GROUP BY c.id, c.organization_id
    LOOP
      IF r.has_list THEN
        PERFORM public.add_play_list_members(r.organization_id, r.campaign_id, '{}', r.contact_ids);
      ELSE
        PERFORM public.play_list_fill(r.organization_id, r.campaign_id);
      END IF;
    END LOOP;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'play list (people) skipped: % (%)', SQLERRM, SQLSTATE;
  END;
  RETURN NULL;
END;
$$;

-- Leaving draft: what the play already has goes in. Renamed: the list's name follows.
CREATE OR REPLACE FUNCTION public.play_list_after_campaign_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  BEGIN
    IF NEW.name IS DISTINCT FROM OLD.name AND nullif(btrim(NEW.name), '') IS NOT NULL THEN
      UPDATE public.crm_lists
      SET name = btrim(NEW.name), updated_at = now()
      WHERE campaign_id = NEW.id AND name IS DISTINCT FROM btrim(NEW.name);
    END IF;

    IF OLD.status IS NOT DISTINCT FROM 'draft'
       AND NEW.status IS DISTINCT FROM 'draft'
       AND NEW.lead_source IS DISTINCT FROM 'mobile' THEN
      PERFORM public.play_list_fill(NEW.organization_id, NEW.id);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'play list (play update) skipped: % (%)', SQLERRM, SQLSTATE;
  END;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS play_list_after_company_links ON public.campaign_companies;
CREATE TRIGGER play_list_after_company_links
  AFTER INSERT ON public.campaign_companies
  REFERENCING NEW TABLE AS new_rows
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.play_list_after_company_links();

DROP TRIGGER IF EXISTS play_list_after_contact_links ON public.campaign_contacts;
CREATE TRIGGER play_list_after_contact_links
  AFTER INSERT ON public.campaign_contacts
  REFERENCING NEW TABLE AS new_rows
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.play_list_after_contact_links();

DROP TRIGGER IF EXISTS play_list_after_campaign_update ON public.campaigns;
CREATE TRIGGER play_list_after_campaign_update
  AFTER UPDATE OF status, name ON public.campaigns
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status OR OLD.name IS DISTINCT FROM NEW.name)
  EXECUTE FUNCTION public.play_list_after_campaign_update();

-- 5. Companies page list filter -------------------------------------------------------------------

-- The same columns and paging as get_companies_by_campaign (210), for one CRM list. A list's
-- companies are its members, the companies it owns (crm_list_id) and the companies extracted from
-- its imported rows: the same set crm_list_delete_batch (400) works on. p_assigned_to_user_id
-- scopes the result to one owner, as the Companies route does for members.
CREATE OR REPLACE FUNCTION public.get_companies_by_list(
  p_organization_id TEXT,
  p_list_id UUID,
  p_status TEXT DEFAULT NULL,
  p_search TEXT DEFAULT NULL,
  p_sort_by TEXT DEFAULT 'name',
  p_sort_order TEXT DEFAULT 'asc',
  p_page INTEGER DEFAULT 1,
  p_limit INTEGER DEFAULT 50,
  p_assigned_to_user_id TEXT DEFAULT NULL
)
RETURNS TABLE (
  id UUID,
  organization_id TEXT,
  name TEXT,
  website TEXT,
  size TEXT,
  linkedin_url TEXT,
  description TEXT,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ,
  used_for_outreach BOOLEAN,
  phone TEXT,
  employee_count INTEGER,
  logo TEXT,
  location TEXT,
  industries TEXT[],
  icp_score JSONB,
  deep_research JSONB,
  outreach_strategy JSONB,
  universal_name TEXT,
  company_type TEXT,
  cover TEXT,
  tagline TEXT,
  founded_year INTEGER,
  object_urn BIGINT,
  followers INTEGER,
  locations JSONB,
  funding_data JSONB,
  specialities TEXT[],
  hashtags TEXT[],
  processing_status TEXT,
  b2b_result JSONB,
  blocked_by_icp BOOLEAN,
  total_count BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_offset INTEGER;
  v_total BIGINT;
BEGIN
  v_offset := (greatest(p_page, 1) - 1) * p_limit;

  SELECT COUNT(*) INTO v_total
  FROM public.companies c
  WHERE c.organization_id = p_organization_id
    AND c.id IN (
      SELECT m.company_id FROM public.crm_list_members m
      WHERE m.list_id = p_list_id AND m.organization_id = p_organization_id AND m.company_id IS NOT NULL
      UNION
      SELECT oc.id FROM public.companies oc
      WHERE oc.organization_id = p_organization_id AND oc.crm_list_id = p_list_id::text
      UNION
      SELECT r.extracted_company_id FROM public.crm_raw_records r
      WHERE r.list_id = p_list_id AND r.organization_id = p_organization_id AND r.extracted_company_id IS NOT NULL
    )
    AND (p_assigned_to_user_id IS NULL OR c.assigned_to_user_id = p_assigned_to_user_id)
    AND (
      p_status IS NULL
      OR (p_status = 'approved' AND c.processing_status = 'approved' AND COALESCE(c.blocked_by_icp, false) = false)
      OR (p_status = 'processing' AND c.processing_status IN ('processing', 'pending'))
      OR (p_status = 'processed' AND (c.processing_status IN ('imported', 'processed', 'approved', 'declined') OR c.blocked_by_icp = true))
      OR (p_status = 'declined' AND c.processing_status = 'declined')
      OR (p_status = 'blocked_by_icp' AND c.blocked_by_icp = true)
      OR (p_status = 'failed' AND c.processing_status = 'failed')
      OR (p_status = 'scheduled' AND c.processing_status = 'scheduled')
    )
    AND (p_search IS NULL OR p_search = '' OR c.name ILIKE '%' || p_search || '%' OR c.location ILIKE '%' || p_search || '%');

  RETURN QUERY
  SELECT
    c.id, c.organization_id, c.name, c.website, c.size, c.linkedin_url, c.description,
    c.created_at, c.updated_at, c.used_for_outreach, c.phone, c.employee_count, c.logo,
    c.location, c.industries, c.icp_score, c.deep_research, c.outreach_strategy,
    c.universal_name, c.company_type, c.cover, c.tagline, c.founded_year, c.object_urn,
    c.followers, c.locations, c.funding_data, c.specialities, c.hashtags,
    c.processing_status, c.b2b_result, c.blocked_by_icp, v_total
  FROM public.companies c
  WHERE c.organization_id = p_organization_id
    AND c.id IN (
      SELECT m.company_id FROM public.crm_list_members m
      WHERE m.list_id = p_list_id AND m.organization_id = p_organization_id AND m.company_id IS NOT NULL
      UNION
      SELECT oc.id FROM public.companies oc
      WHERE oc.organization_id = p_organization_id AND oc.crm_list_id = p_list_id::text
      UNION
      SELECT r.extracted_company_id FROM public.crm_raw_records r
      WHERE r.list_id = p_list_id AND r.organization_id = p_organization_id AND r.extracted_company_id IS NOT NULL
    )
    AND (p_assigned_to_user_id IS NULL OR c.assigned_to_user_id = p_assigned_to_user_id)
    AND (
      p_status IS NULL
      OR (p_status = 'approved' AND c.processing_status = 'approved' AND COALESCE(c.blocked_by_icp, false) = false)
      OR (p_status = 'processing' AND c.processing_status IN ('processing', 'pending'))
      OR (p_status = 'processed' AND (c.processing_status IN ('imported', 'processed', 'approved', 'declined') OR c.blocked_by_icp = true))
      OR (p_status = 'declined' AND c.processing_status = 'declined')
      OR (p_status = 'blocked_by_icp' AND c.blocked_by_icp = true)
      OR (p_status = 'failed' AND c.processing_status = 'failed')
      OR (p_status = 'scheduled' AND c.processing_status = 'scheduled')
    )
    AND (p_search IS NULL OR p_search = '' OR c.name ILIKE '%' || p_search || '%' OR c.location ILIKE '%' || p_search || '%')
  ORDER BY
    CASE WHEN p_sort_by = 'name' AND p_sort_order = 'asc' THEN c.name END ASC,
    CASE WHEN p_sort_by = 'name' AND p_sort_order = 'desc' THEN c.name END DESC,
    CASE WHEN p_sort_by = 'created_at' AND p_sort_order = 'asc' THEN c.created_at END ASC,
    CASE WHEN p_sort_by = 'created_at' AND p_sort_order = 'desc' THEN c.created_at END DESC,
    c.name ASC, c.id ASC
  LIMIT p_limit OFFSET v_offset;
END;
$$;

COMMENT ON FUNCTION public.get_companies_by_list(text, uuid, text, text, text, text, integer, integer, text) IS
  'Companies page list filter: one page of a CRM list''s companies (members, owned, extracted), the columns of get_companies_by_campaign. Service role only (selltonai api/companies/route.ts).';

-- 6. Grants: the functions are for the service role only (the 390 and 400 pattern) --------------

REVOKE ALL ON FUNCTION public.get_companies_by_list(text, uuid, text, text, text, text, integer, integer, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_companies_by_list(text, uuid, text, text, text, text, integer, integer, text) TO service_role;

REVOKE ALL ON FUNCTION public.add_play_list_members(text, uuid, uuid[], uuid[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.add_play_list_members(text, uuid, uuid[], uuid[]) TO service_role;
REVOKE ALL ON FUNCTION public.play_list_fill(text, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.play_list_fill(text, uuid) TO service_role;
REVOKE ALL ON FUNCTION public.play_list_after_company_links() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.play_list_after_contact_links() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.play_list_after_campaign_update() FROM PUBLIC, anon, authenticated;

-- Verify (read only):
-- SELECT column_name FROM information_schema.columns WHERE table_name = 'crm_lists' AND column_name = 'campaign_id';  -- 1 row
-- SELECT tgname FROM pg_trigger WHERE tgname LIKE 'play_list_after_%';  -- 3 rows
-- SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'crm_list_members_source_check';  -- includes 'play'
