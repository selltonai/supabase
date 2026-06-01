-- ============================================================
-- Onboarding UX screening foundation
-- Projects:
--   - selltonai: stores website screening state, override decisions, and live research progress
--   - selltonai-modal: writes screening results and appends research findings_stream entries
--   - backoffice/admin: can audit screening failures and override rates
-- App changes required together:
--   - Phase 2 should add /api/onboarding/screen-website and Modal /onboarding/screen-website.
--   - Phase 3 should render not-a-fit, thin-content, and override UI using these columns.
-- Notes:
--   - This migration is idempotent for easy Supabase SQL editor application.
--   - public.organization is the workspace table in this schema.
-- ============================================================

ALTER TABLE public.onboarding_research
  ADD COLUMN IF NOT EXISTS fit_type TEXT,
  ADD COLUMN IF NOT EXISTS is_supported BOOLEAN,
  ADD COLUMN IF NOT EXISTS screening_confidence NUMERIC(3,2),
  ADD COLUMN IF NOT EXISTS screening_reason TEXT,
  ADD COLUMN IF NOT EXISTS detected_business_name TEXT,
  ADD COLUMN IF NOT EXISTS detected_offering_summary TEXT,
  ADD COLUMN IF NOT EXISTS screening_overridden BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS screening_override_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS screening_override_by_user_id TEXT,
  ADD COLUMN IF NOT EXISTS screening_checked_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS screening_input_url TEXT,
  ADD COLUMN IF NOT EXISTS screening_homepage_reachable BOOLEAN,
  ADD COLUMN IF NOT EXISTS screening_homepage_status INTEGER,
  ADD COLUMN IF NOT EXISTS screening_metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS flagged_unclear BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS thin_content_fallback_text TEXT,
  ADD COLUMN IF NOT EXISTS findings_stream JSONB NOT NULL DEFAULT '[]'::jsonb;

UPDATE public.onboarding_research
SET
  screening_overridden = COALESCE(screening_overridden, FALSE),
  screening_metadata = COALESCE(screening_metadata, '{}'::jsonb),
  flagged_unclear = COALESCE(flagged_unclear, FALSE),
  findings_stream = CASE
    WHEN jsonb_typeof(COALESCE(findings_stream, '[]'::jsonb)) = 'array'
      THEN COALESCE(findings_stream, '[]'::jsonb)
    ELSE '[]'::jsonb
  END;

ALTER TABLE public.onboarding_research
  ALTER COLUMN screening_overridden SET DEFAULT FALSE,
  ALTER COLUMN screening_overridden SET NOT NULL,
  ALTER COLUMN screening_metadata SET DEFAULT '{}'::jsonb,
  ALTER COLUMN screening_metadata SET NOT NULL,
  ALTER COLUMN flagged_unclear SET DEFAULT FALSE,
  ALTER COLUMN flagged_unclear SET NOT NULL,
  ALTER COLUMN findings_stream SET DEFAULT '[]'::jsonb,
  ALTER COLUMN findings_stream SET NOT NULL;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'onboarding_research_fit_type_check'
      AND conrelid = 'public.onboarding_research'::regclass
  ) THEN
    ALTER TABLE public.onboarding_research
      DROP CONSTRAINT onboarding_research_fit_type_check;
  END IF;

  ALTER TABLE public.onboarding_research
    ADD CONSTRAINT onboarding_research_fit_type_check
    CHECK (
      fit_type IS NULL OR fit_type IN (
        'b2b',
        'b2b2c',
        'b2c_ecommerce',
        'b2c_subscription',
        'news_media',
        'personal_blog',
        'non_profit',
        'education',
        'government',
        'adult',
        'gambling',
        'social_profile',
        'consumer_marketplace',
        'content_page',
        'thin_content',
        'unclear'
      )
    );

  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'onboarding_research_screening_confidence_check'
      AND conrelid = 'public.onboarding_research'::regclass
  ) THEN
    ALTER TABLE public.onboarding_research
      DROP CONSTRAINT onboarding_research_screening_confidence_check;
  END IF;

  ALTER TABLE public.onboarding_research
    ADD CONSTRAINT onboarding_research_screening_confidence_check
    CHECK (
      screening_confidence IS NULL
      OR (screening_confidence >= 0 AND screening_confidence <= 1)
    );

  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'onboarding_research_findings_stream_array_check'
      AND conrelid = 'public.onboarding_research'::regclass
  ) THEN
    ALTER TABLE public.onboarding_research
      DROP CONSTRAINT onboarding_research_findings_stream_array_check;
  END IF;

  ALTER TABLE public.onboarding_research
    ADD CONSTRAINT onboarding_research_findings_stream_array_check
    CHECK (jsonb_typeof(findings_stream) = 'array');

  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'onboarding_research_status_check'
      AND conrelid = 'public.onboarding_research'::regclass
  ) THEN
    ALTER TABLE public.onboarding_research
      DROP CONSTRAINT onboarding_research_status_check;
  END IF;

  ALTER TABLE public.onboarding_research
    ADD CONSTRAINT onboarding_research_status_check
    CHECK (
      status IN (
        'screening',
        'screening_failed',
        'screening_overridden',
        'screening_thin_content',
        'researching',
        'v1_complete',
        'interviewing',
        'interviewing_complete',
        'v2_generating',
        'v2_complete',
        'approved',
        'failed'
      )
    );

  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'organization_onboarding_status_check'
      AND conrelid = 'public.organization'::regclass
  ) THEN
    ALTER TABLE public.organization
      DROP CONSTRAINT organization_onboarding_status_check;
  END IF;

  ALTER TABLE public.organization
    ADD CONSTRAINT organization_onboarding_status_check
    CHECK (
      onboarding_status IN (
        'pending',
        'intro_skipped',
        'qualified',
        'screening',
        'screening_failed',
        'screening_overridden',
        'screening_thin_content',
        'researching',
        'v1_complete',
        'interviewing',
        'interviewing_complete',
        'v2_generating',
        'v2_complete',
        'kb_built',
        'approved',
        'launched',
        'failed'
      )
    );
END $$;

CREATE INDEX IF NOT EXISTS idx_onboarding_research_screening_fit
  ON public.onboarding_research(fit_type, screening_confidence)
  WHERE fit_type IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_onboarding_research_screening_overrides
  ON public.onboarding_research(screening_overridden, screening_override_at DESC)
  WHERE screening_overridden = TRUE;

CREATE INDEX IF NOT EXISTS idx_onboarding_research_screening_checked
  ON public.onboarding_research(screening_checked_at DESC)
  WHERE screening_checked_at IS NOT NULL;

COMMENT ON COLUMN public.onboarding_research.fit_type IS
  'Fast website screening classification before expensive grounded onboarding research.';

COMMENT ON COLUMN public.onboarding_research.is_supported IS
  'True when the screened website is supported for autonomous onboarding, normally b2b or b2b2c.';

COMMENT ON COLUMN public.onboarding_research.screening_confidence IS
  '0-1 confidence returned by the lightweight website screening model.';

COMMENT ON COLUMN public.onboarding_research.screening_reason IS
  'Short explanation for the website screening classification.';

COMMENT ON COLUMN public.onboarding_research.detected_business_name IS
  'Company name detected during fast website screening.';

COMMENT ON COLUMN public.onboarding_research.detected_offering_summary IS
  'One-sentence offering summary detected during fast website screening.';

COMMENT ON COLUMN public.onboarding_research.screening_overridden IS
  'True when a user overrides an ambiguous or non-fit screening result and continues anyway.';

COMMENT ON COLUMN public.onboarding_research.screening_metadata IS
  'Raw and operational metadata from website screening, excluding large scraped page bodies.';

COMMENT ON COLUMN public.onboarding_research.flagged_unclear IS
  'True when the website screening was low-confidence and later V1/V2 quality gates should be stricter.';

COMMENT ON COLUMN public.onboarding_research.thin_content_fallback_text IS
  'User-provided company description when the website exists but has too little useful public content.';

COMMENT ON COLUMN public.onboarding_research.findings_stream IS
  'Append-only JSON array of small research milestones surfaced by the onboarding research animation.';
