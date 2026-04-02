-- Create simplified dashboard stats function for large organizations
-- This function returns only basic counts (total contacts and companies) for faster performance

DROP FUNCTION if exists get_dashboard_stats_simple(text);

create or replace function get_dashboard_stats_simple(p_org_id text)
returns jsonb as $$
declare
  result jsonb;
begin
  select jsonb_build_object(
    'contacts', (
      select jsonb_build_object(
        'total', count(*)
      )
      from contacts
      where organization_id = p_org_id
    ),
    'companies', (
      select jsonb_build_object(
        'total', count(*)
      )
      from companies
      where organization_id = p_org_id
    ),
    'tasks', (
      select jsonb_build_object(
        'total', count(*)
      )
      from tasks
      where organization_id = p_org_id
    )
  ) into result;

  return result;
end;
$$ language plpgsql;
