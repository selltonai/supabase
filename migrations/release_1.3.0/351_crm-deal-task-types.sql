-- ============================================================
-- Migration: 346_crm-deal-task-types
-- Date:      2026-07-17
-- Purpose:   Extend the shared task enum for CRM deal workflows.
-- Projects:  selltonai-database/supabase (owner), selltonai-modal and
--            selltonai (writers/readers), backoffice (generic reader).
-- Contract:  Additive, forward-only enum values. Apply and commit this
--            migration before 347, which uses the values in indexes/triggers.
-- ============================================================

ALTER TYPE public.task_type ADD VALUE IF NOT EXISTS 'nurture_reminder';
ALTER TYPE public.task_type ADD VALUE IF NOT EXISTS 'linkedin_connect';
ALTER TYPE public.task_type ADD VALUE IF NOT EXISTS 'manual_outreach';

COMMENT ON TYPE public.task_type IS
  'Shared task workflow enum. CRM additions: nurture_reminder, linkedin_connect, manual_outreach.';

-- Verify after apply:
-- SELECT enumlabel FROM pg_enum
-- WHERE enumtypid = 'public.task_type'::REGTYPE
-- ORDER BY enumsortorder;
--
-- Rollback: PostgreSQL cannot remove enum values in place. Stop application
-- writers; unused values may remain safely as an additive contract.
