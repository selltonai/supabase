-- Align reply-runtime enum/check constraints with deployed Modal code.
--
-- Projects depending on this:
-- - selltonai-modal writes contacts.pipeline_stage = 'NOT_INTERESTED' for explicit no-interest replies.
-- - selltonai-modal may read/write task statuses used by campaign/reply background flows.
--
-- Application compatibility:
-- - Safe/idempotent. This only broadens accepted values and preserves existing data.

ALTER TABLE public.contacts
  DROP CONSTRAINT IF EXISTS contacts_pipeline_stage_chk;

ALTER TABLE public.contacts
  ADD CONSTRAINT contacts_pipeline_stage_chk CHECK (
    pipeline_stage IS NULL OR pipeline_stage = ANY (ARRAY[
      'PROSPECT',
      'LEAD',
      'APPOINTMENT_REQUESTED',
      'APPOINTMENT_SCHEDULED',
      'APPOINTMENT_CANCELLED',
      'PRESENTATION_SCHEDULED',
      'CONTRACT_NEGOTIATIONS',
      'AGREEMENT_IN_PRINCIPLE',
      'CLOSED_WON',
      'CLOSED_LOST',
      'REENGAGEMENT',
      'NOT_INTERESTED'
    ]::text[])
  );

COMMENT ON COLUMN public.contacts.pipeline_stage IS
  'Enum-like stage: PROSPECT | LEAD | APPOINTMENT_REQUESTED | APPOINTMENT_SCHEDULED | APPOINTMENT_CANCELLED | PRESENTATION_SCHEDULED | CONTRACT_NEGOTIATIONS | AGREEMENT_IN_PRINCIPLE | CLOSED_WON | CLOSED_LOST | REENGAGEMENT | NOT_INTERESTED';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_enum e
    JOIN pg_type t ON e.enumtypid = t.oid
    WHERE t.typname = 'task_status' AND e.enumlabel = 'in_review'
  ) THEN
    ALTER TYPE public.task_status ADD VALUE 'in_review';
  END IF;
END $$;
