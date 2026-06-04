-- What changed:
--   Dashboard and task stat RPCs no longer count tasks linked to deleted campaign rows.
--   They also keep the existing exclusions for do-not-contact contacts and cancelled campaigns.
-- Dependent projects:
--   selltonai dashboard/task stats routes.
-- Application code:
--   selltonai also applies the same visibility rule in route-level fallbacks.

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
        'scheduledTasks', count(*) FILTER (WHERE t.status = 'scheduled'),
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
        AND t.task_type::text != 'email_generation_processing'
        AND (c.do_not_contact IS NULL OR c.do_not_contact = false)
        AND (t.campaign_id IS NULL OR (camp.id IS NOT NULL AND camp.status != 'cancelled'))
    )
  )
  INTO result
  FROM companies
  WHERE organization_id = p_organization_id;

  RETURN result;
END;
$$;

COMMENT ON FUNCTION get_dashboard_stats(text) IS 'Dashboard statistics. Excludes do-not-contact contacts, cancelled campaigns, orphaned campaign tasks, and internal processing tasks.';

CREATE OR REPLACE FUNCTION get_task_status_counts(org_id text)
RETURNS json
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  result json;
BEGIN
  WITH visible_tasks AS (
    SELECT t.*
    FROM tasks t
    LEFT JOIN contacts c ON t.contact_id = c.id
    LEFT JOIN campaigns camp ON t.campaign_id = camp.id
    WHERE t.organization_id = org_id
      AND t.task_type::text != 'email_generation_processing'
      AND (c.do_not_contact IS NULL OR c.do_not_contact = false)
      AND (t.campaign_id IS NULL OR (camp.id IS NOT NULL AND camp.status != 'cancelled'))
  )
  SELECT json_build_object(
    'totalTasks', COUNT(*),
    'pendingTasks', COUNT(*) FILTER (WHERE status = 'pending'),
    'inProgressTasks', COUNT(*) FILTER (WHERE status = 'in_progress'),
    'completedTasks', COUNT(*) FILTER (WHERE status = 'completed'),
    'cancelledTasks', COUNT(*) FILTER (WHERE status = 'cancelled'),
    'scheduledTasks', COUNT(*) FILTER (WHERE status = 'scheduled'),
    'reviewDraftTasks', COUNT(*) FILTER (WHERE task_type::text = 'review_draft' AND status = 'pending'),
    'meetingTasks', COUNT(*) FILTER (WHERE task_type::text = 'meeting' AND status = 'pending'),
    'companyVerificationTasks', COUNT(*) FILTER (WHERE task_type::text = 'company_verification' AND status = 'pending'),
    'meetingsScheduled', COUNT(*) FILTER (WHERE task_type::text = 'meeting' AND status IN ('pending', 'scheduled')),
    'meetingsCompleted', COUNT(*) FILTER (WHERE task_type::text = 'meeting' AND status = 'completed'),
    'tasksWithCompany', COUNT(*) FILTER (WHERE company_id IS NOT NULL),
    'tasksWithCampaign', COUNT(*) FILTER (WHERE campaign_id IS NOT NULL),
    'tasksWithContact', COUNT(*) FILTER (WHERE contact_id IS NOT NULL),
    'companyVerificationPending', COUNT(*) FILTER (WHERE task_type::text = 'company_verification' AND status = 'pending'),
    'companyVerificationCompleted', COUNT(*) FILTER (WHERE task_type::text = 'company_verification' AND status = 'completed'),
    'overdueTasks', COUNT(*) FILTER (WHERE due_date < now() AND status NOT IN ('completed', 'cancelled')),
    'dueTodayTasks', COUNT(*) FILTER (WHERE date(due_date) = current_date AND status NOT IN ('completed', 'cancelled')),
    'dueThisWeekTasks', COUNT(*) FILTER (WHERE due_date BETWEEN now() AND now() + interval '7 days' AND status NOT IN ('completed', 'cancelled')),
    'createdToday', COUNT(*) FILTER (WHERE date(created_at) = current_date),
    'completedToday', COUNT(*) FILTER (WHERE date(completed_at) = current_date),
    'urgentPriorityTasks', 0,
    'highPriorityTasks', 0,
    'normalPriorityTasks', 0,
    'lowPriorityTasks', 0
  )
  INTO result
  FROM visible_tasks;

  RETURN result;
END;
$$;

COMMENT ON FUNCTION get_task_status_counts(text) IS 'Task statistics excluding do-not-contact contacts, cancelled campaigns, orphaned campaign tasks, and internal processing tasks.';
