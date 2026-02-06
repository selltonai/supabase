-- Create a unified function for all dashboard statistics
-- This avoids multiple round-trips and fetches all key metrics in one go.

CREATE OR REPLACE FUNCTION get_task_status_counts(org_id UUID)
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
    'sendEmailTasks', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND task_type = 'send_email'),
    'followUpTasks', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND task_type = 'follow_up'),
    'customTasks', (SELECT COUNT(*) FROM tasks WHERE organization_id = org_id AND task_type = 'custom'),
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

COMMENT ON FUNCTION get_task_status_counts(UUID) IS 'Optimized function to get task statistics without loading all records. Ensures a single JSON object is always returned.';


