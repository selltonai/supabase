DROP FUNCTION if exists get_dashboard_stats(text);

create or replace function get_dashboard_stats(p_org_id text)
returns jsonb as $$
declare
  result jsonb;
begin
  select jsonb_build_object(
    'tasks', (
      select jsonb_build_object(
        'totalTasks', count(*),
        'pendingTasks', count(*) filter (where status = 'pending'),
        'inProgressTasks', count(*) filter (where status = 'in_progress'),
        'completedTasks', count(*) filter (where status = 'completed'),
        'cancelledTasks', count(*) filter (where status = 'cancelled'),
        'scheduledTasks', count(*) filter (where status = 'scheduled'),
        'reviewDraftTasks', count(*) filter (where task_type = 'review_draft'),
        'meetingTasks', count(*) filter (where task_type = 'meeting'),
        'companyVerificationTasks', count(*) filter (where task_type = 'company_verification'),
        'overdueTasks', count(*) filter (where status in ('pending', 'in_progress') and due_date < now()),
        'dueTodayTasks', count(*) filter (where status in ('pending', 'in_progress') and due_date >= date_trunc('day', now()) and due_date < date_trunc('day', now()) + interval '1 day'),
        'dueThisWeekTasks', count(*) filter (where status in ('pending', 'in_progress') and due_date >= date_trunc('week', now()) and due_date < date_trunc('week', now()) + interval '1 week')
      )
      from tasks
      where organization_id = p_org_id
    ),
    'contacts', (
      select jsonb_build_object(
        'all_leads', count(*) filter (where analysis->>'source' = 'campaign_lead_selection'),
        'all_customers', count(*) filter (where analysis->>'campaign_id' is not null),
        'hot_leads', count(*) filter (where case when analysis->>'score' ~ '^[0-9]+$' then (analysis->>'score')::integer >= 80 else false end),
        'new', count(*) filter (where created_at >= now() - interval '7 days'),
        'prospects', count(*) filter (where linkedin_url is not null),
        'total_contacts', count(*),
        'active_this_week', count(*) filter (where updated_at >= now() - interval '7 days'),
        'high_fit_score', count(*) filter (where case when analysis->>'score' ~ '^[0-9]+$' then (analysis->>'score')::integer >= 80 else false end)
      )
      from contacts
      where organization_id = p_org_id
    ),
    'companies', (
      select jsonb_build_object(
        'all_companies', count(*),
        'cancelled', (
          select count(distinct company_id) 
          from tasks 
          where organization_id = p_org_id 
            and task_type = 'company_verification' 
            and status = 'cancelled' 
            and company_id is not null
        ),
        'processed', count(*) filter (where processing_simple_status = 'processed'),
        'completed', count(*) filter (where used_for_outreach = true)
      )
      from companies
      where organization_id = p_org_id
    )
  ) into result;

  return result;
end;
$$ language plpgsql;
