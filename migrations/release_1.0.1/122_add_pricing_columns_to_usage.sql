-- Migration: Add pricing columns to usage table
-- Date: 2025-10-31
-- Description: Adds columns to track original provider pricing and Sellton pricing for cost analysis

-- Add pricing columns to usage table
ALTER TABLE usage ADD COLUMN IF NOT EXISTS original_pricing JSONB DEFAULT '{}'::jsonb;
ALTER TABLE usage ADD COLUMN IF NOT EXISTS sellton_pricing JSONB DEFAULT '{}'::jsonb;

-- Add comment for documentation
COMMENT ON COLUMN usage.original_pricing IS 'Original provider pricing at time of usage (JSONB with model pricing info)';
COMMENT ON COLUMN usage.sellton_pricing IS 'Sellton pricing applied at time of usage (JSONB with model pricing info)';

-- Add index for pricing queries (if needed for cost analysis)
CREATE INDEX IF NOT EXISTS idx_usage_pricing ON usage USING GIN (original_pricing, sellton_pricing);

