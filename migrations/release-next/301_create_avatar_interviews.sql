-- ============================================================
-- Onboarding module foundation: avatar_interviews
-- Projects:
--   - selltonai: creates Retell web calls and receives Retell webhooks
--   - selltonai-modal: processes transcripts into onboarding V2 or sender_voice
-- App changes required together:
--   - Retell webhook should write call completion to this table and dispatch processing by avatar_type.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.avatar_interviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id TEXT NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  created_by TEXT NOT NULL,
  avatar_type TEXT NOT NULL,
  region TEXT,
  line_of_business TEXT,
  role_at_company TEXT,
  recipient_name TEXT,
  recipient_email TEXT,
  token TEXT UNIQUE,
  status TEXT NOT NULL DEFAULT 'pending',
  interview_config JSONB DEFAULT '{}'::jsonb,
  retell_call_id TEXT UNIQUE,
  transcript TEXT,
  recording_url TEXT,
  extracted_knowledge JSONB,
  duration_seconds INTEGER,
  completed_at TIMESTAMPTZ,
  processed_at TIMESTAMPTZ,
  error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT avatar_interviews_avatar_type_check CHECK (
    avatar_type IN ('onboarding','linkedin_voice','company_knowledge','sales_objections')
  ),
  CONSTRAINT avatar_interviews_status_check CHECK (
    status IN ('pending','in_progress','completed','processed','failed')
  )
);

CREATE INDEX IF NOT EXISTS idx_avatar_interviews_org_status
  ON public.avatar_interviews(organization_id, status);

CREATE INDEX IF NOT EXISTS idx_avatar_interviews_call_id
  ON public.avatar_interviews(retell_call_id)
  WHERE retell_call_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_avatar_interviews_token
  ON public.avatar_interviews(token)
  WHERE token IS NOT NULL;

DROP TRIGGER IF EXISTS update_avatar_interviews_updated_at ON public.avatar_interviews;
CREATE TRIGGER update_avatar_interviews_updated_at
  BEFORE UPDATE ON public.avatar_interviews
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

ALTER TABLE public.avatar_interviews ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS avatar_interviews_select_org ON public.avatar_interviews;
CREATE POLICY avatar_interviews_select_org
  ON public.avatar_interviews
  FOR SELECT
  USING (organization_id = (auth.jwt() ->> 'org_id'));

COMMENT ON TABLE public.avatar_interviews IS 'Tracking table for Retell avatar interviews used by onboarding and sender voice workflows.';
COMMENT ON COLUMN public.avatar_interviews.avatar_type IS 'onboarding and linkedin_voice are MVP; company_knowledge and sales_objections are Phase 2.';
