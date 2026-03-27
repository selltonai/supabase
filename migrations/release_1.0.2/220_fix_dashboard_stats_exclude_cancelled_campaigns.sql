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
      'all_companies', count(*),
      'scheduled', count(*) FILTER (WHERE processing_status = 'scheduled'),
      'processing', count(*) FILTER (WHERE processing_status IN ('processing', 'pending')),
      'processed', count(*) FILTER (WHERE processing_status IN ('processed', 'approved', 'declined') OR blocked_by_icp = true),
      'approved', count(*) FILTER (WHERE processing_status = 'approved'),
      'declined', count(*) FILTER (WHERE processing_status = 'declined'),
      'blocked_by_icp', count(*) FILTER (WHERE blocked_by_icp = true),
      'failed', count(*) FILTER (WHERE processing_status = 'failed')
    ),
    'contacts', jsonb_build_object(
      'total', (SELECT count(*) FROM contacts WHERE organization_id = p_organization_id),
      'total_contacts', (SELECT count(*) FROM contacts WHERE organization_id = p_organization_id),
      'processing', (SELECT count(*) FROM contacts WHERE organization_id = p_organization_id AND processing_status IN ('pending', 'processing')),
      'completed', (SELECT count(*) FROM contacts WHERE organization_id = p_organization_id AND processing_status = 'completed')
    ),
    'tasks', (
      SELECT jsonb_build_object(
        'totalTasks', count(*),
        'pendingTasks', count(*) FILTER (WHERE t.status = 'pending'),
        'inProgressTasks', count(*) FILTER (WHERE t.status = 'in_progress'),
        'completedTasks', count(*) FILTER (WHERE t.status = 'completed'),
        'cancelledTasks', count(*) FILTER (WHERE t.status = 'cancelled'),
        'scheduledTasks', 0,
        'reviewDraftTasks', count(*) FILTER (WHERE t.task_type::text = 'review_draft' AND t.status = 'pending'),
        'meetingTasks', count(*) FILTER (WHERE t.task_type::text = 'meeting' AND t.status = 'pending'),
        'companyVerificationTasks', count(*) FILTER (WHERE t.task_type::text = 'company_verification' AND t.status = 'pending'),
        'overdueTasks', count(*) FILTER (WHERE t.status IN ('pending', 'in_progress') AND t.due_date < now()),
        'dueTodayTasks', count(*) FILTER (WHERE t.status IN ('pending', 'in_progress') AND t.due_date >= date_trunc('day', now()) AND t.due_date < date_trunc('day', now()) + interval '1 day'),
        'dueThisWeekTasks', count(*) FILTER (WHERE t.status IN ('pending', 'in_progress') AND t.due_date >= date_trunc('week', now()) AND t.due_date < date_trunc('week', now()) + interval '1 week')
      )
      FROM tasks t
      LEFT JOIN contacts c ON t.contact_id = c.id
      LEFT JOIN campaigns camp ON t.campaign_id = camp.id
      WHERE t.organization_id = p_organization_id
        AND (c.do_not_contact IS NULL OR c.do_not_contact = false)
        AND (camp.status IS NULL OR camp.status != 'cancelled')
    )
  )
  INTO result
  FROM companies
  WHERE organization_id = p_organization_id;
  
  RETURN result;
END;
$$;

COMMENT ON FUNCTION get_dashboard_stats(text) IS 'Dashboard statistics. Excludes tasks from cancelled campaigns and do_not_contact contacts to match the tasks API filtering.';
