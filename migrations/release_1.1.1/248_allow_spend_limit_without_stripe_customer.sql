-- Allow billing_customers rows to exist before Stripe customer setup.
-- Spend limits are stored on billing_customers, and invoice generation
-- already skips rows where stripe_customer_id is NULL.
ALTER TABLE billing_customers
ALTER COLUMN stripe_customer_id DROP NOT NULL;

ALTER TABLE billing_customers
ALTER COLUMN billing_email DROP NOT NULL;
