-- ============================================================================
-- FOLLOW-UP ELIGIBLE CONTACTS QUERY (30 HOUR INTERVAL)
-- ============================================================================
-- This query finds contacts eligible for follow-up emails based on:
--   1. Active campaign only
--   2. At least 1 email sent (initial outreach done)
--   3. Less than max_emails_per_contact emails sent (default: 5)
--   4. No pending/in_review tasks
--   5. No rejected/cancelled tasks
--   6. Last email > min_hours_between_emails ago (30h)
--   7. Contact NOT unsubscribed (unsubscribed_at IS NULL)
--   8. Contact NOT opted out (do_not_contact = false)
--   9. Contact drafts NOT stopped (stop_drafts = false)
--  10. Contact pipeline_stage = PROSPECT
--  11. Contact has NOT replied (last_incoming_email_at < last_sent_at)
--  12. Contact has thread_id from previous sent email (last_thread_id IS NOT NULL)
-- ============================================================================

-- Configuration variables (adjust as needed)
-- max_emails_per_contact: 5
-- min_hours_between_emails: 30

SELECT 
    t.organization_id,
    camp.name AS campaign_name,
    c.name AS contact_name,
    c.email AS contact_email,
    c.last_thread_id,
    c.last_incoming_email_at,
    comp.name AS company_name,
    t.campaign_id,
    t.contact_id,
    cc_link.company_id,
    COUNT(*) FILTER (WHERE t.status = 'completed' AND t.sent_at IS NOT NULL) AS sent_email_count,
    COUNT(*) FILTER (WHERE t.status = 'completed' AND t.sent_at IS NOT NULL) + 1 AS next_sequence_number,
    COUNT(*) FILTER (WHERE t.status IN ('pending', 'in_review')) AS pending_tasks,
    COUNT(*) FILTER (WHERE t.status IN ('rejected', 'cancelled')) AS declined_tasks,
    COUNT(*) AS total_tasks,
    MAX(t.sent_at) AS last_sent_at,
    ROUND(EXTRACT(EPOCH FROM (NOW() - MAX(t.sent_at))) / 3600, 1) AS hours_since_last_email,
    -- Check if contact has replied (incoming email after last sent)
    CASE 
        WHEN c.last_incoming_email_at IS NOT NULL AND c.last_incoming_email_at > MAX(t.sent_at) 
        THEN TRUE 
        ELSE FALSE 
    END AS has_replied
FROM tasks t
LEFT JOIN contacts c ON c.id = t.contact_id
LEFT JOIN company_contacts cc_link ON cc_link.contact_id = t.contact_id AND cc_link.organization_id = t.organization_id
LEFT JOIN companies comp ON comp.id = cc_link.company_id
INNER JOIN campaigns camp ON camp.id = t.campaign_id
WHERE t.task_type = 'review_draft'
  AND camp.status = 'active'
  AND c.pipeline_stage = 'PROSPECT'
  AND c.unsubscribed_at IS NULL
  AND (c.stop_drafts IS NULL OR c.stop_drafts = false)
  AND (c.do_not_contact IS NULL OR c.do_not_contact = false)
  -- 🔴 CRITICAL: Must have thread_id from previous sent email
  AND c.last_thread_id IS NOT NULL
  AND c.last_thread_id != ''
GROUP BY 
    t.organization_id, 
    t.campaign_id, 
    t.contact_id, 
    camp.name,
    c.name, 
    c.email,
    c.last_thread_id,
    c.last_incoming_email_at,
    comp.name,
    cc_link.company_id
HAVING 
    -- At least 1 email sent
    COUNT(*) FILTER (WHERE t.status = 'completed' AND t.sent_at IS NOT NULL) > 0
    -- Less than 5 emails sent (adjust max_emails_per_contact here)
    AND COUNT(*) FILTER (WHERE t.status = 'completed' AND t.sent_at IS NOT NULL) < 5
    -- No pending or in_review tasks
    AND COUNT(*) FILTER (WHERE t.status IN ('pending', 'in_review')) = 0
    -- No rejected or cancelled tasks
    AND COUNT(*) FILTER (WHERE t.status IN ('rejected', 'cancelled')) = 0
    -- Last email was sent more than 30 hours ago (adjust min_hours_between_emails here)
    AND MAX(t.sent_at) < NOW() - INTERVAL '30 hours'
    -- 🔴 CRITICAL: Contact has NOT replied (no incoming email after last sent)
    AND (c.last_incoming_email_at IS NULL OR c.last_incoming_email_at <= MAX(t.sent_at))
ORDER BY 
    t.organization_id,
    camp.name,
    sent_email_count DESC, 
    c.name;


-- ============================================================================
-- QUERY FOR SPECIFIC ORGANIZATION (uncomment and replace org_id)
-- ============================================================================
-- Add this to the WHERE clause:
-- AND t.organization_id = 'your-organization-id-here'


-- ============================================================================
-- 🔍 DIAGNOSTIC QUERY - Run this to see WHY contacts are being excluded
-- ============================================================================
-- This shows all contacts with their filter status so you can identify the issue

SELECT 
    t.organization_id,
    camp.name AS campaign_name,
    camp.status AS campaign_status,
    c.name AS contact_name,
    c.email AS contact_email,
    c.pipeline_stage,
    c.last_thread_id,
    c.last_incoming_email_at,
    c.unsubscribed_at,
    c.stop_drafts,
    c.do_not_contact,
    COUNT(*) FILTER (WHERE t.status = 'completed' AND t.sent_at IS NOT NULL) AS sent_email_count,
    COUNT(*) FILTER (WHERE t.status IN ('pending', 'in_review')) AS pending_tasks,
    COUNT(*) FILTER (WHERE t.status IN ('rejected', 'cancelled')) AS declined_tasks,
    MAX(t.sent_at) AS last_sent_at,
    ROUND(EXTRACT(EPOCH FROM (NOW() - MAX(t.sent_at))) / 3600, 1) AS hours_since_last_email,
    -- Filter status checks
    CASE WHEN camp.status = 'active' THEN '✅' ELSE '❌ campaign not active' END AS chk_campaign_active,
    CASE WHEN c.pipeline_stage = 'PROSPECT' THEN '✅' ELSE '❌ not PROSPECT' END AS chk_pipeline,
    CASE WHEN c.unsubscribed_at IS NULL THEN '✅' ELSE '❌ unsubscribed' END AS chk_unsubscribed,
    CASE WHEN c.stop_drafts IS NULL OR c.stop_drafts = false THEN '✅' ELSE '❌ stop_drafts=true' END AS chk_stop_drafts,
    CASE WHEN c.do_not_contact IS NULL OR c.do_not_contact = false THEN '✅' ELSE '❌ do_not_contact' END AS chk_do_not_contact,
    CASE WHEN c.last_thread_id IS NOT NULL AND c.last_thread_id != '' THEN '✅' ELSE '❌ NO THREAD_ID' END AS chk_has_thread_id,
    CASE WHEN COUNT(*) FILTER (WHERE t.status = 'completed' AND t.sent_at IS NOT NULL) > 0 THEN '✅' ELSE '❌ no emails sent' END AS chk_has_sent,
    CASE WHEN COUNT(*) FILTER (WHERE t.status = 'completed' AND t.sent_at IS NOT NULL) < 5 THEN '✅' ELSE '❌ max emails reached' END AS chk_under_max,
    CASE WHEN COUNT(*) FILTER (WHERE t.status IN ('pending', 'in_review')) = 0 THEN '✅' ELSE '❌ has pending tasks' END AS chk_no_pending,
    CASE WHEN COUNT(*) FILTER (WHERE t.status IN ('rejected', 'cancelled')) = 0 THEN '✅' ELSE '❌ has declined tasks' END AS chk_no_declined,
    CASE WHEN MAX(t.sent_at) < NOW() - INTERVAL '30 hours' THEN '✅' ELSE '❌ too recent (<30h)' END AS chk_time_elapsed,
    CASE WHEN c.last_incoming_email_at IS NULL OR c.last_incoming_email_at <= MAX(t.sent_at) THEN '✅' ELSE '❌ CONTACT REPLIED' END AS chk_no_reply
FROM tasks t
LEFT JOIN contacts c ON c.id = t.contact_id
INNER JOIN campaigns camp ON camp.id = t.campaign_id
WHERE t.task_type = 'review_draft'
GROUP BY 
    t.organization_id, 
    t.campaign_id, 
    t.contact_id, 
    camp.name,
    camp.status,
    c.name, 
    c.email,
    c.pipeline_stage,
    c.last_thread_id,
    c.last_incoming_email_at,
    c.unsubscribed_at,
    c.stop_drafts,
    c.do_not_contact
ORDER BY 
    camp.name,
    c.name
LIMIT 50;

