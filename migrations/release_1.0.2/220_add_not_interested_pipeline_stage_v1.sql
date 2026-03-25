-- Add NOT_INTERESTED to contacts pipeline stage constraint
-- Migration: 220_add_not_interested_pipeline_stage_v1.sql
-- Release: v1.0.2

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
