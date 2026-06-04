-- Allow workspace billing settings before Stripe customer setup.
-- Depends on: selltonai-modal billing service stores monthly spend limits in billing_customers.
-- Application impact: selltonai can save a monthly spend limit for a workspace that has not completed Stripe setup.
ALTER TABLE billing_customers
ALTER COLUMN stripe_customer_id DROP NOT NULL;

ALTER TABLE billing_customers
ALTER COLUMN billing_email DROP NOT NULL;
