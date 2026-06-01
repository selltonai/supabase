-- ============================================================
-- Onboarding Phase 7: sender_voice profiles
-- Projects:
--   - selltonai: starts Retell sender voice interviews after LinkedIn connect
--   - selltonai-modal: distills transcripts into this table
-- App changes required together:
--   - Retell webhook should dispatch linkedin_voice transcripts to Modal.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.sender_voice (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id TEXT NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL,
  linkedin_account_id UUID,
  voice_summary TEXT,
  voice_profile JSONB NOT NULL DEFAULT '{}'::jsonb,
  do_say TEXT[] NOT NULL DEFAULT '{}'::text[],
  dont_say TEXT[] NOT NULL DEFAULT '{}'::text[],
  message_examples JSONB NOT NULL DEFAULT '[]'::jsonb,
  transcript TEXT,
  voice_card_text TEXT,
  last_distilled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT sender_voice_org_user_unique UNIQUE (organization_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_sender_voice_org
  ON public.sender_voice(organization_id);

CREATE INDEX IF NOT EXISTS idx_sender_voice_user
  ON public.sender_voice(user_id);

DROP TRIGGER IF EXISTS update_sender_voice_updated_at ON public.sender_voice;
CREATE TRIGGER update_sender_voice_updated_at
  BEFORE UPDATE ON public.sender_voice
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

ALTER TABLE public.sender_voice ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS sender_voice_select_org ON public.sender_voice;
CREATE POLICY sender_voice_select_org
  ON public.sender_voice
  FOR SELECT
  USING (organization_id = (auth.jwt() ->> 'org_id'));

COMMENT ON TABLE public.sender_voice IS 'Per-user LinkedIn writing voice distilled from onboarding sender voice interviews.';
COMMENT ON COLUMN public.sender_voice.voice_profile IS 'Structured voice card used by LinkedIn/email copywriters.';
