-- Add spend limit tracking columns to billing_customers
-- spend_warning_sent_at: tracks when 80% warning email was sent (prevents duplicate emails)
-- spend_limit_paused_at: tracks when campaigns were paused at 100% (prevents duplicate pauses)
-- Both should be reset when customer changes their spend limit or at new billing month.

ALTER TABLE billing_customers
ADD COLUMN IF NOT EXISTS spend_warning_sent_at TIMESTAMPTZ DEFAULT NULL;

ALTER TABLE billing_customers
ADD COLUMN IF NOT EXISTS spend_limit_paused_at TIMESTAMPTZ DEFAULT NULL;
