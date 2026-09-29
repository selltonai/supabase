-- AC-13 — companies of a cancelled campaign are usable again.
-- The filter_companies_for_campaign function previously checked the sticky
-- used_for_outreach flag, which nothing clears on cancel. Now it checks
-- whether the company is linked to a campaign that is active or paused.
-- A company whose only campaigns are cancelled or completed is available.

CREATE OR REPLACE FUNCTION filter_companies_for_campaign(
    p_organization_id TEXT,
    p_company_data JSONB
)
RETURNS TABLE (
    company_data JSONB,
    is_already_used BOOLEAN,
    existing_company_id UUID
) AS $$
DECLARE
    company_item JSONB;
    existing_company RECORD;
    active_link_count INTEGER;
BEGIN
    FOR company_item IN SELECT * FROM jsonb_array_elements(p_company_data)
    LOOP
        SELECT id, name, used_for_outreach INTO existing_company
        FROM companies
        WHERE organization_id = p_organization_id
        AND (
            (company_item->>'linkedin_url' IS NOT NULL AND linkedin_url = company_item->>'linkedin_url') OR
            (company_item->>'name' IS NOT NULL AND LOWER(name) = LOWER(company_item->>'name')) OR
            (company_item->>'domain' IS NOT NULL AND domain = company_item->>'domain')
        );

        IF FOUND THEN
            -- AC-13: check if the company is linked to an active or paused campaign,
            -- not the sticky used_for_outreach flag.
            SELECT COUNT(*) INTO active_link_count
            FROM campaign_companies cc
            JOIN campaigns c ON c.id = cc.campaign_id
            WHERE cc.company_id = existing_company.id
            AND cc.organization_id = p_organization_id
            AND c.status IN ('active', 'paused');

            RETURN QUERY SELECT
                company_item,
                active_link_count > 0,
                existing_company.id;
        ELSE
            RETURN QUERY SELECT
                company_item,
                FALSE,
                NULL::UUID;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION filter_companies_for_campaign IS 'Filters company data to identify which companies are linked to active or paused campaigns (AC-13: cancelled campaigns do not block reuse)';
