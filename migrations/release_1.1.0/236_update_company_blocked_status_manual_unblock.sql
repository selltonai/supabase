-- Respect manual ICP unblock overrides when icp_score is updated.
-- Without this, writing a stored icp_score with blocked=true can re-set
-- companies.blocked_by_icp even after a user explicitly unblocked the company.

CREATE OR REPLACE FUNCTION public.update_company_blocked_status()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF COALESCE(NEW.manually_unblocked, FALSE) = TRUE THEN
        NEW.blocked_by_icp := FALSE;
        RETURN NEW;
    END IF;

    IF NEW.icp_score IS NOT NULL THEN
        IF COALESCE((NEW.icp_score->>'blocked')::boolean, FALSE) = TRUE OR
           COALESCE((NEW.icp_score->'llm_analysis'->>'blocked')::boolean, FALSE) = TRUE THEN
            NEW.blocked_by_icp := TRUE;
        ELSE
            NEW.blocked_by_icp := FALSE;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;
