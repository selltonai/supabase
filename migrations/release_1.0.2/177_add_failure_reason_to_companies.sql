-- Migration: Add failure_reason column to companies table
-- Purpose: Store the reason why a company failed processing (e.g., campaign link creation failed)

-- Step 1: Add failure_reason column
ALTER TABLE companies
ADD COLUMN IF NOT EXISTS failure_reason TEXT;

-- Step 2: Add comment for documentation
COMMENT ON COLUMN companies.failure_reason IS 'Stores the reason why a company failed processing. Set when processing_status is changed to failed. Examples: campaign_link_creation_failed, icp_check_failed, enrichment_failed';

-- Step 3: Create index for querying failed companies with reasons
CREATE INDEX IF NOT EXISTS idx_companies_failed_reason 
ON companies (organization_id, processing_status, failure_reason) 
WHERE processing_status = 'failed';

-- Step 4: Update the get_organization_summary function to include failure reasons breakdown
CREATE OR REPLACE FUNCTION get_organization_summary(p_organization_id TEXT)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'tasks', jsonb_build_object(
      'total', (SELECT count(*) FROM tasks WHERE organization_id = p_organization_id),
      'pending', (SELECT count(*) FROM tasks WHERE organization_id = p_organization_id AND status = 'pending'),
      'in_progress', (SELECT count(*) FROM tasks WHERE organization_id = p_organization_id AND status = 'in_progress'),
      'completed', (SELECT count(*) FROM tasks WHERE organization_id = p_organization_id AND status = 'completed'),
      'cancelled', (SELECT count(*) FROM tasks WHERE organization_id = p_organization_id AND status = 'cancelled')
    ),
    'companies', jsonb_build_object(
      'total', count(*),
      'all_companies', count(*),
      'scheduled', count(*) FILTER (WHERE processing_status = 'scheduled'),
      'processing', count(*) FILTER (WHERE processing_status IN ('processing', 'pending')),
      'processed', count(*) FILTER (WHERE processing_status = 'processed'),
      'approved', count(*) FILTER (WHERE processing_status = 'approved'),
      'declined', count(*) FILTER (WHERE processing_status = 'declined'),
      'blocked_by_icp', count(*) FILTER (WHERE blocked_by_icp = true),
      'failed', count(*) FILTER (WHERE processing_status = 'failed'),
      'failure_reasons', (
        SELECT jsonb_object_agg(COALESCE(failure_reason, 'unknown'), cnt)
        FROM (
          SELECT failure_reason, count(*) as cnt
          FROM companies
          WHERE organization_id = p_organization_id 
            AND processing_status = 'failed'
            AND failure_reason IS NOT NULL
          GROUP BY failure_reason
        ) sub
      )
    ),
    'contacts', jsonb_build_object(
      'total', (SELECT count(*) FROM contacts WHERE organization_id = p_organization_id),
      'total_contacts', (SELECT count(*) FROM contacts WHERE organization_id = p_organization_id),
      'processing', (SELECT count(*) FROM contacts WHERE organization_id = p_organization_id AND processing_status IN ('pending', 'processing')),
      'completed', (SELECT count(*) FROM contacts WHERE organization_id = p_organization_id AND processing_status = 'completed')
    )
  )
  INTO result
  FROM companies
  WHERE organization_id = p_organization_id;
  
  RETURN result;
END;
$$;

-- Step 5: Verification
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'companies' AND column_name = 'failure_reason'
  ) THEN
    RAISE EXCEPTION 'Column failure_reason was not added to companies table';
  ELSE
    RAISE NOTICE 'Successfully added failure_reason column to companies table';
  END IF;
END $$;

