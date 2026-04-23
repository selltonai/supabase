-- Add manually_unblocked column to companies table
-- Used to mark companies that were manually unblocked by the user after ICP blocking
-- This allows the processing pipeline to skip ICP hard filter checks for such companies

ALTER TABLE companies
ADD COLUMN IF NOT EXISTS manually_unblocked boolean NOT NULL DEFAULT false;

-- Add comment for documentation
COMMENT ON COLUMN companies.manually_unblocked IS 'Whether this company was manually unblocked by the user after being blocked by ICP hard filters';
