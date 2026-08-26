-- KAN-282 Stage validation only: opt every existing organization into the
-- nurture scheduler so Stage exercises the complete automation path.
-- Do not promote this migration to production without an explicit rollout decision.
UPDATE public.organization_settings
SET crm_automation_enabled = TRUE,
    updated_at = NOW()
WHERE crm_automation_enabled IS DISTINCT FROM TRUE;
