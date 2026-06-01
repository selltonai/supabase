-- ============================================================
-- Onboarding funnel tracking and re-engagement
-- Projects:
--   - selltonai: writes funnel transitions and runs re-engagement cron
--   - backoffice/admin: reads funnel buckets and conversion history
-- App changes required together:
--   - New transitionOnboardingStatus helper should call transition_onboarding_status().
--   - Re-engagement cron can call find_funnel_dropouts().
-- ============================================================

CREATE TABLE IF NOT EXISTS public.onboarding_funnel_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id TEXT NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL,
  user_email TEXT NOT NULL,
  from_status TEXT,
  to_status TEXT NOT NULL,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_funnel_events_org_time
  ON public.onboarding_funnel_events(organization_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS idx_funnel_events_status
  ON public.onboarding_funnel_events(to_status, occurred_at DESC);

CREATE INDEX IF NOT EXISTS idx_funnel_events_user_email
  ON public.onboarding_funnel_events(user_email, occurred_at DESC);

CREATE TABLE IF NOT EXISTS public.onboarding_reengagement_sends (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id TEXT NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  user_email TEXT NOT NULL,
  sequence_step TEXT NOT NULL,
  discount_code_issued TEXT REFERENCES public.discount_codes(code) ON DELETE SET NULL,
  sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  opened_at TIMESTAMPTZ,
  clicked_at TIMESTAMPTZ,
  converted_at TIMESTAMPTZ,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE (organization_id, sequence_step)
);

CREATE INDEX IF NOT EXISTS idx_reengagement_sends_org
  ON public.onboarding_reengagement_sends(organization_id, sent_at DESC);

CREATE INDEX IF NOT EXISTS idx_reengagement_sends_step
  ON public.onboarding_reengagement_sends(sequence_step, sent_at DESC);

CREATE OR REPLACE FUNCTION public.transition_onboarding_status(
  p_org_id TEXT,
  p_user_id TEXT,
  p_user_email TEXT,
  p_from_status TEXT,
  p_to_status TEXT,
  p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS VOID AS $$
DECLARE
  v_current_status TEXT;
BEGIN
  SELECT onboarding_status
  INTO v_current_status
  FROM public.organization
  WHERE id = p_org_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Organization % not found', p_org_id;
  END IF;

  UPDATE public.organization
  SET onboarding_status = p_to_status
  WHERE id = p_org_id;

  INSERT INTO public.onboarding_funnel_events (
    organization_id,
    user_id,
    user_email,
    from_status,
    to_status,
    metadata
  )
  VALUES (
    p_org_id,
    p_user_id,
    p_user_email,
    COALESCE(p_from_status, v_current_status),
    p_to_status,
    COALESCE(p_metadata, '{}'::jsonb)
  );
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.find_funnel_dropouts(
  target_from_status TEXT,
  excluded_to_statuses TEXT[],
  hours_elapsed NUMERIC,
  sequence_step TEXT
)
RETURNS TABLE (
  organization_id TEXT,
  onboarding_status TEXT,
  user_id TEXT,
  user_email TEXT,
  entered_status_at TIMESTAMPTZ,
  company_website TEXT,
  v1_company_overview JSONB,
  v1_value_propositions JSONB,
  v1_case_studies JSONB,
  v1_competitors JSONB
) AS $$
BEGIN
  RETURN QUERY
  WITH latest_target AS (
    SELECT DISTINCT ON (e.organization_id)
      e.organization_id,
      e.user_id,
      e.user_email,
      e.occurred_at
    FROM public.onboarding_funnel_events e
    WHERE e.to_status = target_from_status
    ORDER BY e.organization_id, e.occurred_at DESC
  )
  SELECT
    o.id AS organization_id,
    o.onboarding_status,
    lt.user_id,
    lt.user_email,
    lt.occurred_at AS entered_status_at,
    r.company_website,
    r.v1_company_overview,
    r.v1_value_propositions,
    r.v1_case_studies,
    r.v1_competitors
  FROM latest_target lt
  JOIN public.organization o ON o.id = lt.organization_id
  LEFT JOIN public.onboarding_research r ON r.organization_id = lt.organization_id
  LEFT JOIN public.onboarding_reengagement_sends s
    ON s.organization_id = lt.organization_id
   AND s.sequence_step = find_funnel_dropouts.sequence_step
  WHERE lt.occurred_at <= NOW() - (hours_elapsed || ' hours')::interval
    AND s.id IS NULL
    AND NOT EXISTS (
      SELECT 1
      FROM public.onboarding_funnel_events progressed
      WHERE progressed.organization_id = lt.organization_id
        AND progressed.to_status = ANY(excluded_to_statuses)
        AND progressed.occurred_at > lt.occurred_at
    );
END;
$$ LANGUAGE plpgsql;

COMMENT ON TABLE public.onboarding_funnel_events IS 'Immutable onboarding state transition log used for funnel analytics and re-engagement.';
COMMENT ON TABLE public.onboarding_reengagement_sends IS 'Idempotent record of automated onboarding re-engagement emails.';
COMMENT ON FUNCTION public.transition_onboarding_status(TEXT, TEXT, TEXT, TEXT, TEXT, JSONB) IS 'Atomically updates organization.onboarding_status and logs a funnel event.';
COMMENT ON FUNCTION public.find_funnel_dropouts(TEXT, TEXT[], NUMERIC, TEXT) IS 'Finds orgs that entered a status, did not progress, and have not received a given re-engagement step.';
