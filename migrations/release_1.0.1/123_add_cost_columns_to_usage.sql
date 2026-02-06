-- Migration: Add cost columns to usage table
-- Date: 2025-10-31
-- Description: Adds columns to store calculated costs (original and Sellton) for easier cost tracking and reporting

-- Add cost columns to usage table
ALTER TABLE usage ADD COLUMN IF NOT EXISTS original_cost NUMERIC(12, 6) DEFAULT 0;
ALTER TABLE usage ADD COLUMN IF NOT EXISTS sellton_cost NUMERIC(12, 6) DEFAULT 0;

-- Add comment for documentation
COMMENT ON COLUMN usage.original_cost IS 'Calculated cost using original provider pricing at time of usage';
COMMENT ON COLUMN usage.sellton_cost IS 'Calculated cost using Sellton pricing at time of usage';

-- Add index for cost-based queries
CREATE INDEX IF NOT EXISTS idx_usage_cost ON usage(organization_id, original_cost, sellton_cost);

