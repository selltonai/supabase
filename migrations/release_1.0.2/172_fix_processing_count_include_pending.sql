-- Migration: Fix processing count to include pending status
-- Purpose: The API transforms 'pending' to 'processing' for display, so the count should match
-- Date: 2025-11-28

DROP FUNCTION IF EXISTS get_dashboard_stats(text);

CREATE OR REPLACE FUNCTION get_dashboard_stats(p_organization_id text)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'companies', jsonb_build_object(
      'total', count(*),
      'all_companies', count(*), -- Alias for compatibility
      'scheduled', count(*) FILTER (WHERE processing_status = 'scheduled'),
      'processing', count(*) FILTER (WHERE processing_status IN ('processing', 'pending')), -- Include pending as processing
      'processed', count(*) FILTER (WHERE processing_status IN ('processed', 'approved', 'declined') OR blocked_by_icp = true), -- Include all final states: processed (waiting for verification), approved, declined, and blocked_by_icp
      'approved', count(*) FILTER (WHERE processing_status = 'approved'),
      'declined', count(*) FILTER (WHERE processing_status = 'declined'),
      'blocked_by_icp', count(*) FILTER (WHERE blocked_by_icp = true),
      'failed', count(*) FILTER (WHERE processing_status = 'failed')
    ),
    'contacts', jsonb_build_object(
      'total', (SELECT count(*) FROM contacts WHERE organization_id = p_organization_id),
      'total_contacts', (SELECT count(*) FROM contacts WHERE organization_id = p_organization_id), -- Alias for compatibility
      'processing', (SELECT count(*) FROM contacts WHERE organization_id = p_organization_id AND processing_status IN ('pending', 'processing')),
      'completed', (SELECT count(*) FROM contacts WHERE organization_id = p_organization_id AND processing_status = 'completed')
    ),
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
      WHERE organization_id = p_organization_id
    )
  )
  INTO result
  FROM companies
  WHERE organization_id = p_organization_id;
  
  RETURN result;
END;
$$;

COMMENT ON FUNCTION get_dashboard_stats(text) IS 'Provides unified dashboard statistics including tasks, contacts, and companies counts. Processing count includes both processing and pending statuses to match API transformation logic.';

