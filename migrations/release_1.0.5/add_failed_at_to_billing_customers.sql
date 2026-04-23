-- Add failed_at timestamp to track when payment first failed
ALTER TABLE billing_customers
ADD COLUMN IF NOT EXISTS failed_at TIMESTAMPTZ DEFAULT NULL;

-- Update default for auto_charge_enabled to true
ALTER TABLE billing_customers
ALTER COLUMN auto_charge_enabled SET DEFAULT true;
