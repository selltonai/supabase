-- ============================================================
-- Billing setup: tables + usage table user_id column
-- ============================================================

-- One Stripe customer per organization
CREATE TABLE IF NOT EXISTS billing_customers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id TEXT NOT NULL UNIQUE REFERENCES organization(id) ON DELETE CASCADE,
    stripe_customer_id TEXT NOT NULL UNIQUE,
    stripe_payment_method_id TEXT,
    billing_email TEXT NOT NULL,
    billing_name TEXT,
    card_last4 TEXT,
    card_brand TEXT,
    plan TEXT NOT NULL DEFAULT 'pay_as_you_go',
    status TEXT NOT NULL DEFAULT 'active',  -- 'active', 'past_due', 'suspended'
    monthly_spend_limit DECIMAL(10,2),
    auto_charge_enabled BOOLEAN NOT NULL DEFAULT true,  -- Phase 1: false, Phase 2: true
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_billing_customers_org ON billing_customers(organization_id);

-- Invoice records (one per org per week)
CREATE TABLE IF NOT EXISTS billing_invoices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id TEXT NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
    stripe_invoice_id TEXT UNIQUE,
    period_start TIMESTAMPTZ NOT NULL,
    period_end TIMESTAMPTZ NOT NULL,
    line_items JSONB NOT NULL DEFAULT '[]',
    -- line_items format:
    -- [{ "provider": "openai", "model_name": "gpt-4o",
    --    "api_calls": 340, "sellton_cost": 6.80,
    --    "user_breakdown": [{"user_id": "user_xxx", "cost": 3.40}] }]
    subtotal DECIMAL(10,2) NOT NULL DEFAULT 0,
    tax DECIMAL(10,2) NOT NULL DEFAULT 0,
    total DECIMAL(10,2) NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'draft',  -- 'draft', 'sent', 'paid', 'failed'
    paid_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_billing_invoices_org ON billing_invoices(organization_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_billing_invoices_status ON billing_invoices(status);
CREATE INDEX IF NOT EXISTS idx_billing_invoices_stripe_id ON billing_invoices(stripe_invoice_id) WHERE stripe_invoice_id IS NOT NULL;

-- RLS: service role bypasses RLS (Modal backend uses service role key)
ALTER TABLE billing_customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing_invoices ENABLE ROW LEVEL SECURITY;

-- Add user_id to usage table for per-user billing breakdown
ALTER TABLE usage ADD COLUMN IF NOT EXISTS user_id TEXT;
CREATE INDEX IF NOT EXISTS idx_usage_user_id ON usage(user_id) WHERE user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_usage_org_period ON usage(organization_id, created_at DESC);


  -- 1. Add invoice_id to usage table (tracks which invoice billed each row)                                                                                                       
  ALTER TABLE usage ADD COLUMN IF NOT EXISTS invoice_id UUID REFERENCES billing_invoices(id) ON DELETE SET NULL;
  CREATE INDEX IF NOT EXISTS idx_usage_invoice_id ON usage(invoice_id);                                                                                                            
                                                                                                                                                                                   
  -- 2. Prevent concurrent cron runs from creating duplicate invoice records
  ALTER TABLE billing_invoices
    ADD CONSTRAINT uq_billing_invoices_org_period
    UNIQUE (organization_id, period_start, period_end);
    
ALTER TABLE billing_invoices                                                                                                                                            
  ADD COLUMN stripe_invoice_url text;  