-- ============================================================
-- Backoffice lifecycle email sequences
-- Projects:
--   - backoffice: manages sequence steps and drains onboarding drip sends
--   - selltonai: continues to write onboarding_funnel_events
-- Notes:
--   - Uses onboarding_reengagement_sends from migration 308 as the idempotent send ledger.
--   - Sequence steps stop at payment/card progress when stop_when_payment_required is true.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.email_sequence_steps (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  step_key TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  position INTEGER NOT NULL DEFAULT 0,
  from_status TEXT NOT NULL DEFAULT 'pending',
  excluded_to_statuses TEXT[] NOT NULL DEFAULT ARRAY['approved','launched','kb_built']::TEXT[],
  delay_hours NUMERIC NOT NULL DEFAULT 24 CHECK (delay_hours >= 0),
  subject TEXT NOT NULL,
  body TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT FALSE,
  stop_when_payment_required BOOLEAN NOT NULL DEFAULT TRUE,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_by TEXT,
  updated_by TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_email_sequence_steps_active_position
  ON public.email_sequence_steps(is_active, position, delay_hours);

CREATE INDEX IF NOT EXISTS idx_email_sequence_steps_from_status
  ON public.email_sequence_steps(from_status, position);

INSERT INTO public.email_sequence_steps (
  step_key,
  name,
  position,
  from_status,
  excluded_to_statuses,
  delay_hours,
  subject,
  body,
  is_active,
  stop_when_payment_required,
  metadata
)
VALUES
  (
    'pending-24h',
    'Pending setup after 24h',
    10,
    'pending',
    ARRAY['approved','launched','kb_built']::TEXT[],
    24,
    'Can I help finish your Sellton setup?',
    'Hi {{ first_name }},

Your Sellton workspace {{ organization_name }} is still waiting in setup. You can continue here: {{ onboarding_url }}

If you are at the card step, add your card here: {{ billing_url }}

Best,
Sellton',
    FALSE,
    TRUE,
    '{"seeded_by":"340_lifecycle-email-sequences"}'::jsonb
  ),
  (
    'pending-72h',
    'Pending setup after 72h',
    20,
    'pending',
    ARRAY['approved','launched','kb_built']::TEXT[],
    72,
    'Still setting up Sellton?',
    'Hi {{ first_name }},

Your Sellton setup is still open. If you want to continue, use this link: {{ onboarding_url }}

If the only thing left is adding a card, you can do that here: {{ billing_url }}

Best,
Sellton',
    FALSE,
    TRUE,
    '{"seeded_by":"340_lifecycle-email-sequences"}'::jsonb
  ),
  (
    'v2-complete-card-24h',
    'Ready but card missing after 24h',
    30,
    'v2_complete',
    ARRAY['approved','launched','kb_built']::TEXT[],
    24,
    'Your Sellton setup is ready for the next step',
    'Hi {{ first_name }},

Your workspace {{ organization_name }} has completed the setup work. To keep moving, finish the card step here: {{ billing_url }}

Best,
Sellton',
    FALSE,
    TRUE,
    '{"seeded_by":"340_lifecycle-email-sequences"}'::jsonb
  )
ON CONFLICT (step_key) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.email_suppressions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT NOT NULL,
  organization_id TEXT REFERENCES public.organization(id) ON DELETE CASCADE,
  scope TEXT NOT NULL DEFAULT 'onboarding_lifecycle',
  reason TEXT,
  created_by TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (email, scope, organization_id)
);

CREATE INDEX IF NOT EXISTS idx_email_suppressions_scope_email
  ON public.email_suppressions(scope, email);

CREATE UNIQUE INDEX IF NOT EXISTS uq_email_suppressions_global
  ON public.email_suppressions(email, scope)
  WHERE organization_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_email_suppressions_org
  ON public.email_suppressions(email, scope, organization_id)
  WHERE organization_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.email_broadcasts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  subject TEXT NOT NULL,
  body TEXT NOT NULL,
  audience_filter JSONB NOT NULL DEFAULT '{}'::jsonb,
  status TEXT NOT NULL DEFAULT 'draft',
  recipient_count INTEGER NOT NULL DEFAULT 0,
  pending_count INTEGER NOT NULL DEFAULT 0,
  sent_count INTEGER NOT NULL DEFAULT 0,
  failed_count INTEGER NOT NULL DEFAULT 0,
  scheduled_at TIMESTAMPTZ,
  sent_at TIMESTAMPTZ,
  created_by TEXT,
  updated_by TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (status IN ('draft','scheduled','sending','sent','cancelled','failed'))
);

CREATE INDEX IF NOT EXISTS idx_email_broadcasts_status_schedule
  ON public.email_broadcasts(status, scheduled_at);

CREATE TABLE IF NOT EXISTS public.email_broadcast_sends (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  broadcast_id UUID NOT NULL REFERENCES public.email_broadcasts(id) ON DELETE CASCADE,
  organization_id TEXT REFERENCES public.organization(id) ON DELETE SET NULL,
  user_email TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  provider_message_id TEXT,
  error_message TEXT,
  sent_at TIMESTAMPTZ,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  CHECK (status IN ('pending','sent','failed','suppressed')),
  UNIQUE (broadcast_id, user_email)
);

CREATE INDEX IF NOT EXISTS idx_email_broadcast_sends_broadcast
  ON public.email_broadcast_sends(broadcast_id, sent_at DESC);

CREATE INDEX IF NOT EXISTS idx_email_broadcast_sends_email
  ON public.email_broadcast_sends(user_email, sent_at DESC);

CREATE OR REPLACE FUNCTION public.update_backoffice_email_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS email_sequence_steps_updated_at ON public.email_sequence_steps;
CREATE TRIGGER email_sequence_steps_updated_at
  BEFORE UPDATE ON public.email_sequence_steps
  FOR EACH ROW
  EXECUTE FUNCTION public.update_backoffice_email_updated_at();

DROP TRIGGER IF EXISTS email_broadcasts_updated_at ON public.email_broadcasts;
CREATE TRIGGER email_broadcasts_updated_at
  BEFORE UPDATE ON public.email_broadcasts
  FOR EACH ROW
  EXECUTE FUNCTION public.update_backoffice_email_updated_at();

ALTER TABLE public.email_sequence_steps ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.email_suppressions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.email_broadcasts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.email_broadcast_sends ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.email_sequence_steps IS
  'Backoffice-managed onboarding lifecycle email steps. Backoffice drains active rows through SendGrid and records idempotency in onboarding_reengagement_sends.';
COMMENT ON COLUMN public.email_sequence_steps.stop_when_payment_required IS
  'When true, skip the step after activation is paid or a billing card is on file so the drip stops at the payment/card requirement.';
COMMENT ON TABLE public.email_suppressions IS
  'Manual email suppressions for lifecycle/broadcast sends.';
COMMENT ON TABLE public.email_broadcasts IS
  'Backoffice broadcast definitions reserved for operator-triggered outbound notices.';
COMMENT ON TABLE public.email_broadcast_sends IS
  'Idempotent send ledger for backoffice broadcasts.';
