-- Migration: Add trigger to automatically update total_companies count
-- Description: Creates a trigger function to keep campaigns.total_companies in sync with campaign_companies table
-- Author: System
-- Date: 2025-01-20

-- Create function to update total_companies count
CREATE OR REPLACE FUNCTION update_campaign_total_companies()
RETURNS TRIGGER AS $$
BEGIN
    -- Update total_companies count for the affected campaign
    UPDATE campaigns 
    SET total_companies = (
        SELECT COUNT(DISTINCT company_id)
        FROM campaign_companies 
        WHERE campaign_id = COALESCE(NEW.campaign_id, OLD.campaign_id)
    )
    WHERE id = COALESCE(NEW.campaign_id, OLD.campaign_id);
    
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Create trigger for INSERT operations
CREATE TRIGGER trigger_campaign_companies_insert
    AFTER INSERT ON campaign_companies
    FOR EACH ROW
    EXECUTE FUNCTION update_campaign_total_companies();

-- Create trigger for DELETE operations  
CREATE TRIGGER trigger_campaign_companies_delete
    AFTER DELETE ON campaign_companies
    FOR EACH ROW
    EXECUTE FUNCTION update_campaign_total_companies();

-- Create trigger for UPDATE operations (in case campaign_id changes)
CREATE TRIGGER trigger_campaign_companies_update
    AFTER UPDATE ON campaign_companies
    FOR EACH ROW
    WHEN (OLD.campaign_id IS DISTINCT FROM NEW.campaign_id)
    EXECUTE FUNCTION update_campaign_total_companies();

-- Update existing campaigns to have correct counts
UPDATE campaigns 
SET total_companies = (
    SELECT COUNT(DISTINCT company_id)
    FROM campaign_companies cc
    WHERE cc.campaign_id = campaigns.id
);

-- Add comment for documentation
COMMENT ON FUNCTION update_campaign_total_companies() IS 'Automatically updates campaigns.total_companies when campaign_companies records are added, updated, or deleted';
