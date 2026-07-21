-- 344 — Lifecycle email audience mode.
--
-- What changed:
--   Adds an explicit audience strategy to backoffice lifecycle email steps.
--   Existing and new rows use not_activated by default so reminders target every
--   workspace without activation/payment, independent of its funnel stage.
--
-- Affected projects:
--   - backoffice reads/writes audience_mode and branches candidate selection.
--   - selltonai remains the producer of organization, membership, and funnel data.
--
-- Deploy together: apply this additive migration in every environment before
-- deploying the Wave 3 backoffice build. A rolled-back build ignores the column.

ALTER TABLE public.email_sequence_steps
  ADD COLUMN IF NOT EXISTS audience_mode text NOT NULL DEFAULT 'not_activated';

ALTER TABLE public.email_sequence_steps
  ALTER COLUMN audience_mode SET DEFAULT 'not_activated';

UPDATE public.email_sequence_steps
SET audience_mode = 'not_activated'
WHERE audience_mode IS NULL;

ALTER TABLE public.email_sequence_steps
  ALTER COLUMN audience_mode SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'email_sequence_steps_audience_mode_check'
      AND conrelid = 'public.email_sequence_steps'::regclass
  ) THEN
    ALTER TABLE public.email_sequence_steps
      ADD CONSTRAINT email_sequence_steps_audience_mode_check
      CHECK (audience_mode IN ('not_activated', 'funnel_stage'));
  END IF;
END $$;

COMMENT ON COLUMN public.email_sequence_steps.audience_mode IS
  'not_activated: all orgs without activation/card, gated by org age >= delay. funnel_stage: legacy find_funnel_dropouts targeting.';

-- Verify:
--   SELECT audience_mode, count(*)
--   FROM public.email_sequence_steps
--   GROUP BY audience_mode
--   ORDER BY audience_mode;
