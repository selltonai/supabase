-- Fix dashboard functions to use only valid task types
-- Current valid task types are: 'review_draft', 'meeting', 'company_verification'

DROP FUNCTION IF EXISTS get_task_status_counts(TEXT);
DROP FUNCTION IF EXISTS get_dashboard_stats(TEXT);

-- Recreate get_task_status_counts with valid task types only
CREATE OR REPLACE FUNCTION get_task_status_counts(org_id TEXT)
RETURNS JSON AS $$
DECLARE
  result JSON;
BEGIN
  SELECT json_build_object(
    'totalTasks', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id),
    'pendingTasks', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND status = 'pending'),
    'inProgressTasks', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND status = 'in_progress'),
    'completedTasks', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND status = 'completed'),
    'cancelledTasks', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND status = 'cancelled'),
    'scheduledTasks', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND status = 'scheduled'),
    'reviewDraftTasks', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND task_type = 'review_draft' AND status = 'pending'),
    'meetingTasks', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND task_type = 'meeting' AND status = 'pending'),
    'companyVerificationTasks', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND task_type = 'company_verification' AND status = 'pending'),
    'meetingsScheduled', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND task_type = 'meeting' AND status IN ('pending', 'scheduled')),
    'meetingsCompleted', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND task_type = 'meeting' AND status = 'completed'),
    'tasksWithCompany', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND company_id IS NOT NULL),
    'tasksWithCampaign', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND campaign_id IS NOT NULL),
    'tasksWithContact', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND contact_id IS NOT NULL),
    'companyVerificationPending', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND task_type = 'company_verification' AND status = 'pending'),
    'companyVerificationCompleted', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND task_type = 'company_verification' AND status = 'completed'),
    'overdueTasks', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND due_date < NOW() AND status NOT IN ('completed', 'cancelled')),
    'dueTodayTasks', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND DATE(due_date) = CURRENT_DATE AND status NOT IN ('completed', 'cancelled')),
    'dueThisWeekTasks', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND due_date BETWEEN NOW() AND NOW() + INTERVAL '7 days' AND status NOT IN ('completed', 'cancelled')),
    'createdToday', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND DATE(created_at) = CURRENT_DATE),
    'completedToday', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND DATE(completed_at) = CURRENT_DATE),
    'urgentPriorityTasks', 0,
    'highPriorityTasks', 0,
    'normalPriorityTasks', 0,
    'lowPriorityTasks', 0
  ) INTO result;

  RETURN result;
END;
$$ LANGUAGE plpgsql STABLE;

-- Recreate get_dashboard_stats
CREATE OR REPLACE FUNCTION get_dashboard_stats(org_id TEXT)
RETURNS JSON AS $$
DECLARE
  task_stats JSON;
  company_count INTEGER;
  contact_count INTEGER;
BEGIN
  -- Get task statistics using the existing function
  task_stats := get_task_status_counts(org_id);
  
  -- Get company count
  SELECT COUNT(*) INTO company_count
  FROM companies
  WHERE organization_id = org_id;
  
  -- Get contact count
  SELECT COUNT(*) INTO contact_count
  FROM company_contacts cc
  JOIN companies c ON cc.company_id = c.id
  WHERE c.organization_id = org_id;
  
  -- Combine all stats into a single JSON object
  RETURN json_build_object(
    'taskStats', task_stats,
    'companiesCount', company_count,
    'contactsCount', contact_count
  );
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION get_task_status_counts(TEXT) IS 'Task statistics function using only valid task types';
COMMENT ON FUNCTION get_dashboard_stats(TEXT) IS 'Unified dashboard statistics with valid task types';


