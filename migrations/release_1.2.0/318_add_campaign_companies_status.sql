-- Migration: 318_add_campaign_companies_status
-- Description: Re-add `campaign_companies.status` (per-campaign approval status:
--   pending | approved | rejected). It is read by the campaign Companies tab and the
--   approved-company counts, and written by the company-verification route on approve/decline.
--
--   This column was first introduced in `release_1.0.0/125_add_status_to_campaign_companies.sql`,
--   but that migration NEVER reached production (schema drift). Symptoms in prod:
--     - company-verification route logged PGRST204 "Could not find the 'status' column
--       of 'campaign_companies' in the schema cache" on every approve/decline, and
--     - the Companies tab showed "N total / 0 shown" (filter on a non-existent column).
--   This forward, idempotent migration brings prod/stage/dev back into sync so it stops drifting.
--
--   Backfill differs from migration 125: 125 blanket-set everything to 'approved' (that
--   predated the verification flow and would mark unverified/declined companies approved).
--   Here we derive from the company's authoritative `companies.processing_status`.
-- Author: reconciliation (prod drift fix)
-- Date: 2026-06-02

-- 1. Column — idempotent, identical shape to release_1.0.0/125 (no-op where 125 already ran).
ALTER TABLE campaign_companies
  ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'pending'
  CHECK (status IN ('pending', 'approved', 'rejected'));

-- 2. Backfill from the company's real processing_status so existing approved/declined
--    companies render with the correct badge (and pass the approved filter) immediately.
--    Verification route values ('approved'/'rejected') are preserved; in-flight / other
--    states map to 'pending' (no approval decision yet).
UPDATE campaign_companies cc
SET status = CASE
    WHEN co.processing_status = 'approved' THEN 'approved'
    WHEN co.processing_status = 'declined' THEN 'rejected'
    ELSE 'pending'
  END
FROM companies co
WHERE co.id = cc.company_id;

-- 3. Index for .eq('status', ...) filters / approved counts.
CREATE INDEX IF NOT EXISTS idx_campaign_companies_status ON campaign_companies(status);

COMMENT ON COLUMN campaign_companies.status IS 'Approval status of company in campaign: pending, approved, rejected';

-- 4. Reload the PostgREST schema cache so the API sees the column immediately
--    (prod was failing with PGRST204 until the cache reloaded). Harmless where current.
NOTIFY pgrst, 'reload schema';
