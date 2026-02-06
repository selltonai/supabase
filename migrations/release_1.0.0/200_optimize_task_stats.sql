-- Create optimized function for task statistics
-- This avoids fetching all records and uses database aggregation

CREATE OR REPLACE FUNCTION get_task_status_counts(org_id UUID)
RETURNS JSON AS $$
DECLARE
  result JSON;
BEGIN
  WITH status_counts AS (
    SELECT 
      COUNT(*) FILTER (WHERE status = 'pending') as pending_tasks,
      COUNT(*) FILTER (WHERE status = 'in_progress') as in_progress_tasks,
      COUNT(*) FILTER (WHERE status = 'completed') as completed_tasks,
      COUNT(*) FILTER (WHERE status = 'cancelled') as cancelled_tasks,
      COUNT(*) FILTER (WHERE status = 'scheduled') as scheduled_tasks,
      COUNT(*) as total_tasks
    FROM tasks
    WHERE organization_id = org_id
  ),
  type_counts AS (
    SELECT 
      COUNT(*) FILTER (WHERE task_type = 'review_draft' AND status = 'pending') as review_draft_tasks,
      COUNT(*) FILTER (WHERE task_type = 'meeting' AND status = 'pending') as meeting_tasks,
      COUNT(*) FILTER (WHERE task_type = 'company_verification' AND status = 'pending') as company_verification_tasks,
      COUNT(*) FILTER (WHERE task_type = 'send_email') as send_email_tasks,
      COUNT(*) FILTER (WHERE task_type = 'follow_up') as follow_up_tasks,
      COUNT(*) FILTER (WHERE task_type = 'custom') as custom_tasks
    FROM tasks
    WHERE organization_id = org_id
  ),
  meeting_counts AS (
    SELECT 
      COUNT(*) FILTER (WHERE task_type = 'meeting' AND status IN ('pending', 'scheduled')) as meetings_scheduled,
      COUNT(*) FILTER (WHERE task_type = 'meeting' AND status = 'completed') as meetings_completed
    FROM tasks
    WHERE organization_id = org_id
  ),
  entity_counts AS (
    SELECT 
      COUNT(*) FILTER (WHERE company_id IS NOT NULL) as tasks_with_company,
      COUNT(*) FILTER (WHERE campaign_id IS NOT NULL) as tasks_with_campaign,
      COUNT(*) FILTER (WHERE contact_id IS NOT NULL) as tasks_with_contact,
      COUNT(*) FILTER (WHERE task_type = 'company_verification' AND status = 'completed') as company_verification_completed
    FROM tasks
    WHERE organization_id = org_id
  ),
  date_counts AS (
    SELECT 
      COUNT(*) FILTER (WHERE due_date < NOW() AND status NOT IN ('completed', 'cancelled')) as overdue_tasks,
      COUNT(*) FILTER (WHERE DATE(due_date) = CURRENT_DATE AND status NOT IN ('completed', 'cancelled')) as due_today_tasks,
      COUNT(*) FILTER (WHERE due_date BETWEEN NOW() AND NOW() + INTERVAL '7 days' AND status NOT IN ('completed', 'cancelled')) as due_this_week_tasks,
      COUNT(*) FILTER (WHERE DATE(created_at) = CURRENT_DATE) as created_today,
      COUNT(*) FILTER (WHERE DATE(completed_at) = CURRENT_DATE) as completed_today
    FROM tasks
    WHERE organization_id = org_id
  )
  SELECT json_build_object(
    'totalTasks', COALESCE(s.total_tasks, 0),
    'pendingTasks', COALESCE(s.pending_tasks, 0),
    'inProgressTasks', COALESCE(s.in_progress_tasks, 0),
    'completedTasks', COALESCE(s.completed_tasks, 0),
    'cancelledTasks', COALESCE(s.cancelled_tasks, 0),
    'scheduledTasks', COALESCE(s.scheduled_tasks, 0),
    'reviewDraftTasks', COALESCE(t.review_draft_tasks, 0),
    'meetingTasks', COALESCE(t.meeting_tasks, 0),
    'companyVerificationTasks', COALESCE(t.company_verification_tasks, 0),
    'sendEmailTasks', COALESCE(t.send_email_tasks, 0),
    'followUpTasks', COALESCE(t.follow_up_tasks, 0),
    'customTasks', COALESCE(t.custom_tasks, 0),
    'meetingsScheduled', COALESCE(m.meetings_scheduled, 0),
    'meetingsCompleted', COALESCE(m.meetings_completed, 0),
    'tasksWithCompany', COALESCE(e.tasks_with_company, 0),
    'tasksWithCampaign', COALESCE(e.tasks_with_campaign, 0),
    'tasksWithContact', COALESCE(e.tasks_with_contact, 0),
    'companyVerificationPending', COALESCE(t.company_verification_tasks, 0),
    'companyVerificationCompleted', COALESCE(e.company_verification_completed, 0),
    'overdueTasks', COALESCE(d.overdue_tasks, 0),
    'dueTodayTasks', COALESCE(d.due_today_tasks, 0),
    'dueThisWeekTasks', COALESCE(d.due_this_week_tasks, 0),
    'createdToday', COALESCE(d.created_today, 0),
    'completedToday', COALESCE(d.completed_today, 0),
    -- Priority counts would require fetching records for calculation, so set to 0
    'urgentPriorityTasks', 0,
    'highPriorityTasks', 0,
    'normalPriorityTasks', 0,
    'lowPriorityTasks', 0
  ) INTO result
  FROM status_counts s
  CROSS JOIN type_counts t
  CROSS JOIN meeting_counts m
  CROSS JOIN entity_counts e
  CROSS JOIN date_counts d;
  
  RETURN result;
END;
$$ LANGUAGE plpgsql STABLE;

-- Create indexes to speed up task queries
CREATE INDEX IF NOT EXISTS idx_tasks_org_status ON tasks(organization_id, status);
CREATE INDEX IF NOT EXISTS idx_tasks_org_type_status ON tasks(organization_id, task_type, status);
CREATE INDEX IF NOT EXISTS idx_tasks_org_due_date ON tasks(organization_id, due_date) WHERE due_date IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_tasks_org_created ON tasks(organization_id, created_at);
CREATE INDEX IF NOT EXISTS idx_tasks_org_completed ON tasks(organization_id, completed_at) WHERE completed_at IS NOT NULL;

-- Create indexes to speed up company queries
CREATE INDEX IF NOT EXISTS idx_companies_org_status ON companies(organization_id, processing_simple_status);
CREATE INDEX IF NOT EXISTS idx_companies_org_name ON companies(organization_id, name);
CREATE INDEX IF NOT EXISTS idx_companies_org_updated ON companies(organization_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_companies_org_created ON companies(organization_id, created_at);

-- Index for company_contacts to speed up contact counts
CREATE INDEX IF NOT EXISTS idx_company_contacts_company ON company_contacts(company_id);

-- Composite index for task verification lookups
CREATE INDEX IF NOT EXISTS idx_tasks_company_verification ON tasks(company_id, task_type, created_at) 
WHERE task_type = 'company_verification';

COMMENT ON FUNCTION get_task_status_counts(UUID) IS 'Optimized function to get task statistics without loading all records';


