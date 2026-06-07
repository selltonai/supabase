-- Migration: Add organization work access override controls
-- Date: 2026-06-07
-- Description:
--   Adds durable admin override fields for allowing or blocking billable/outbound
--   workspace work independently from billing/payment status.
-- Affected services:
--   backoffice reads/writes these fields, selltonai-modal enforces them in
--   billing and cron flows, and selltonai dispatch guards read them.
-- Application code:
--   Deploy backoffice with legacy fallback first, then this migration per
--   environment, then updated selltonai-modal and selltonai guards.

ALTER TABLE organization
  ADD COLUMN IF NOT EXISTS work_access_mode TEXT NOT NULL DEFAULT 'auto',
  ADD COLUMN IF NOT EXISTS work_access_reason TEXT,
  ADD COLUMN IF NOT EXISTS work_access_until TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS work_access_updated_by TEXT,
  ADD COLUMN IF NOT EXISTS work_access_updated_at TIMESTAMPTZ;

UPDATE organization
SET work_access_mode = 'auto'
WHERE work_access_mode IS NULL
   OR work_access_mode NOT IN ('auto', 'force_allow', 'force_block');

ALTER TABLE organization
  ALTER COLUMN work_access_mode SET DEFAULT 'auto',
  ALTER COLUMN work_access_mode SET NOT NULL;

DO $$
BEGIN
  ALTER TABLE organization
    ADD CONSTRAINT organization_work_access_mode_check
    CHECK (work_access_mode IN ('auto', 'force_allow', 'force_block'));
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_organization_work_access_mode
  ON organization(work_access_mode)
  WHERE work_access_mode <> 'auto';

COMMENT ON COLUMN organization.work_access_mode IS
  'Admin work-access override: auto, force_allow, or force_block. Separate from billing/payment status.';
COMMENT ON COLUMN organization.work_access_reason IS
  'Internal admin reason for the current work-access override.';
COMMENT ON COLUMN organization.work_access_until IS
  'Optional expiry for force_allow/force_block work-access overrides.';
COMMENT ON COLUMN organization.work_access_updated_by IS
  'Backoffice actor or service that last changed the work-access override.';
COMMENT ON COLUMN organization.work_access_updated_at IS
  'Timestamp of the last work-access override change.';
