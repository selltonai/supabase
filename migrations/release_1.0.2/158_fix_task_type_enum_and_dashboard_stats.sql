-- Migration: Fix task_type enum and dashboard stats function
-- Description: 
--   1. Ensure all required task_type enum values exist
--   2. Update get_dashboard_stats to handle enum values correctly
-- Author: System
-- Date: 2025-11-13

-- First, ensure all required enum values exist
DO $$ 
BEGIN
    -- Add review_draft if it doesn't exist
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_enum e
        JOIN pg_type t ON e.enumtypid = t.oid
        WHERE t.typname = 'task_type' 
        AND e.enumlabel = 'review_draft'
    ) THEN
        -- If enum doesn't exist at all, create it
        IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_type') THEN
            CREATE TYPE task_type AS ENUM ('review_draft', 'meeting');
        ELSE
            ALTER TYPE task_type ADD VALUE 'review_draft';
        END IF;
        RAISE NOTICE 'Added review_draft to task_type enum';
    END IF;

    -- Add meeting if it doesn't exist
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_enum e
        JOIN pg_type t ON e.enumtypid = t.oid
        WHERE t.typname = 'task_type' 
        AND e.enumlabel = 'meeting'
    ) THEN
        ALTER TYPE task_type ADD VALUE 'meeting';
        RAISE NOTICE 'Added meeting to task_type enum';
    END IF;

    -- Add company_verification if it doesn't exist
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_enum e
        JOIN pg_type t ON e.enumtypid = t.oid
        WHERE t.typname = 'task_type' 
        AND e.enumlabel = 'company_verification'
    ) THEN
        ALTER TYPE task_type ADD VALUE 'company_verification';
        RAISE NOTICE 'Added company_verification to task_type enum';
    END IF;

    -- Add email_generation_processing if it doesn't exist
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_enum e
        JOIN pg_type t ON e.enumtypid = t.oid
        WHERE t.typname = 'task_type' 
        AND e.enumlabel = 'email_generation_processing'
    ) THEN
        ALTER TYPE task_type ADD VALUE 'email_generation_processing';
        RAISE NOTICE 'Added email_generation_processing to task_type enum';
    END IF;
EXCEPTION
    WHEN duplicate_object THEN
        RAISE NOTICE 'Enum values already exist - skipping';
    WHEN OTHERS THEN
        RAISE WARNING 'Error ensuring task_type enum values: %', SQLERRM;
END $$;

-- Update the dashboard stats function with explicit enum casts
DROP FUNCTION IF EXISTS get_dashboard_stats(text);

CREATE OR REPLACE FUNCTION get_dashboard_stats(p_org_id text)
RETURNS jsonb AS $$
DECLARE
  result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'tasks', (
      SELECT jsonb_build_object(
        'totalTasks', count(*),
        'pendingTasks', count(*) FILTER (WHERE status = 'pending'),
        'inProgressTasks', count(*) FILTER (WHERE status = 'in_progress'),
        'completedTasks', count(*) FILTER (WHERE status = 'completed'),
        'cancelledTasks', count(*) FILTER (WHERE status = 'cancelled'),
        'scheduledTasks', 0,
        'reviewDraftTasks', count(*) FILTER (WHERE task_type::text = 'review_draft'),
        'meetingTasks', count(*) FILTER (WHERE task_type::text = 'meeting'),
        'companyVerificationTasks', count(*) FILTER (WHERE task_type::text = 'company_verification'),
        'overdueTasks', count(*) FILTER (WHERE status IN ('pending', 'in_progress') AND due_date < now()),
        'dueTodayTasks', count(*) FILTER (WHERE status IN ('pending', 'in_progress') AND due_date >= date_trunc('day', now()) AND due_date < date_trunc('day', now()) + interval '1 day'),
        'dueThisWeekTasks', count(*) FILTER (WHERE status IN ('pending', 'in_progress') AND due_date >= date_trunc('week', now()) AND due_date < date_trunc('week', now()) + interval '1 week')
      )
      FROM tasks
      WHERE organization_id = p_org_id
    ),
    'contacts', (
      SELECT jsonb_build_object(
        'all_leads', count(*) FILTER (WHERE analysis->>'source' = 'campaign_lead_selection'),
        'all_customers', count(*) FILTER (WHERE analysis->>'campaign_id' IS NOT NULL),
        'hot_leads', count(*) FILTER (WHERE CASE WHEN analysis->>'score' ~ '^[0-9]+$' THEN (analysis->>'score')::integer >= 80 ELSE false END),
        'new', count(*) FILTER (WHERE created_at >= now() - interval '7 days'),
        'prospects', count(*) FILTER (WHERE linkedin_url IS NOT NULL),
        'total_contacts', count(*),
        'active_this_week', count(*) FILTER (WHERE updated_at >= now() - interval '7 days'),
        'high_fit_score', count(*) FILTER (WHERE CASE WHEN analysis->>'score' ~ '^[0-9]+$' THEN (analysis->>'score')::integer >= 80 ELSE false END)
      )
      FROM contacts
      WHERE organization_id = p_org_id
    ),
    'companies', (
      SELECT jsonb_build_object(
        'all_companies', count(*),
        'cancelled', (
          -- Count companies where the latest company_verification task is cancelled
          SELECT count(DISTINCT company_id)
          FROM (
            SELECT DISTINCT ON (company_id)
              company_id,
              status
            FROM tasks
            WHERE organization_id = p_org_id
              AND task_type::text = 'company_verification'
              AND company_id IS NOT NULL
            ORDER BY company_id, created_at DESC
          ) latest_tasks
          WHERE status = 'cancelled'
        ),
        'processed', count(*) FILTER (WHERE processing_simple_status = 'processed'),
        'completed', count(*) FILTER (WHERE used_for_outreach = true),
        'blocked_by_icp', count(*) FILTER (WHERE blocked_by_icp = true)
      )
      FROM companies
      WHERE organization_id = p_org_id
    )
  ) INTO result;

  RETURN result;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_dashboard_stats(text) IS 'Provides unified dashboard statistics including tasks, contacts, and companies counts. Updated to use explicit enum casts to avoid enum value errors.';

