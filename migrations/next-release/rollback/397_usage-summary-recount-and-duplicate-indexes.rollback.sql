-- Reverses 397: restores the recounting update_usage_summary() as it was live on stage on 2026-10-14 and recreates the
-- two duplicate indexes. unique_sessions values written while 397 was live stay 0 / frozen.
CREATE INDEX IF NOT EXISTS idx_usage_org_created_desc ON public.usage USING btree (organization_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_usage_org_period ON public.usage USING btree (organization_id, created_at DESC);
COMMENT ON COLUMN public.usage_summary.unique_sessions IS NULL;

CREATE OR REPLACE FUNCTION public.update_usage_summary()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    INSERT INTO usage_summary (
        organization_id,
        provider,
        model_name,
        date,
        total_api_calls,
        total_input_tokens,
        total_output_tokens,
        total_tokens,
        unique_sessions
    ) VALUES (
        NEW.organization_id,
        NEW.provider,
        NEW.model_name,
        DATE(NEW.created_at),
        NEW.api_calls,
        NEW.input_tokens,
        NEW.output_tokens,
        NEW.total_tokens,
        1  -- This will be recalculated in the conflict resolution
    )
    ON CONFLICT (organization_id, provider, model_name, date)
    DO UPDATE SET
        total_api_calls = usage_summary.total_api_calls + NEW.api_calls,
        total_input_tokens = usage_summary.total_input_tokens + NEW.input_tokens,
        total_output_tokens = usage_summary.total_output_tokens + NEW.output_tokens,
        total_tokens = usage_summary.total_tokens + NEW.total_tokens,
        unique_sessions = (
            SELECT COUNT(DISTINCT session_id) 
            FROM usage 
            WHERE organization_id = NEW.organization_id 
            AND provider = NEW.provider 
            AND COALESCE(model_name, '') = COALESCE(NEW.model_name, '')
            AND DATE(created_at) = DATE(NEW.created_at)
        ),
        updated_at = NOW();
    
    RETURN NEW;
END;
$function$;
