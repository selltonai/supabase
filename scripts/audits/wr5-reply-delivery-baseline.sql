-- WR5 G-2: aggregate reply-task lifecycle against actual email delivery state.
-- Read-only. Output contains organization ids and aggregate counts only.
-- Do not paste task ids, contact ids, message bodies, or send_error_message into Git.

WITH reply_tasks AS (
  SELECT
    organization_id,
    task_type::text AS task_type,
    status::text AS task_status,
    COALESCE(send_status, 'not_sent') AS delivery_status,
    sent_at,
    created_at
  FROM public.tasks
  WHERE created_at >= now() - interval '30 days'
    AND (
      task_type::text = 'review_reply'
      OR (
        task_type::text = 'review_draft'
        AND COALESCE(metadata->>'email_type', '') IN (
          'reply',
          'timeslots',
          'booking_confirmation',
          'inquiry_response',
          'information_response',
          'general_response',
          'not_interested_response',
          'slot_reminder_1',
          'slot_reminder_2',
          'case_study_followup_1',
          'case_study_followup_2',
          'positive_follow_up_1',
          'positive_follow_up_2'
        )
      )
    )
),
aggregated AS (
  SELECT
    organization_id,
    task_type,
    task_status,
    delivery_status,
    count(*) AS task_count,
    count(*) FILTER (
      WHERE task_status = 'completed'
        AND (delivery_status <> 'sent_success' OR sent_at IS NULL)
    ) AS completed_but_not_sent,
    count(*) FILTER (
      WHERE task_status NOT IN ('cancelled', 'failed')
        AND delivery_status = 'not_sent'
    ) AS open_or_completed_not_sent
  FROM reply_tasks
  GROUP BY organization_id, task_type, task_status, delivery_status
)
SELECT
  organization_id,
  task_type,
  task_status,
  delivery_status,
  task_count,
  completed_but_not_sent,
  open_or_completed_not_sent
FROM aggregated
ORDER BY organization_id, task_type, task_status, delivery_status;
