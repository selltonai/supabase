-- ============================================================
-- KAN-127: Xero billing integration + SLTN invoice numbering
-- Projects:
--   - selltonai-modal: generates SLTN invoice numbers and syncs paid invoices to Xero
--   - selltonai: displays invoice_number in billing history
-- Application code must be deployed with this migration.
-- ============================================================

-- App-controlled sequential invoice numbers for Sellton-generated invoices.
-- Starts at SLTN-0001 as agreed for Stripe-1 / Sellton app invoices.
CREATE SEQUENCE IF NOT EXISTS billing_invoice_number_seq
  START WITH 1
  INCREMENT BY 1
  MINVALUE 1
  NO CYCLE;

CREATE OR REPLACE FUNCTION next_billing_invoice_number()
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  next_number bigint;
BEGIN
  SELECT nextval('billing_invoice_number_seq') INTO next_number;
  RETURN 'SLTN-' || lpad(next_number::text, 4, '0');
END;
$$;

ALTER TABLE billing_invoices
  ADD COLUMN IF NOT EXISTS invoice_number text,
  ADD COLUMN IF NOT EXISTS accounting_breakdown jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS xero_invoice_id text,
  ADD COLUMN IF NOT EXISTS xero_payment_id text,
  ADD COLUMN IF NOT EXISTS xero_sync_status text NOT NULL DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS xero_sync_error text,
  ADD COLUMN IF NOT EXISTS xero_synced_at timestamptz;

CREATE UNIQUE INDEX IF NOT EXISTS idx_billing_invoices_invoice_number
  ON billing_invoices(invoice_number)
  WHERE invoice_number IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_billing_invoices_xero_sync_status
  ON billing_invoices(xero_sync_status)
  WHERE xero_sync_status IN ('pending', 'failed');

CREATE INDEX IF NOT EXISTS idx_billing_invoices_xero_invoice_id
  ON billing_invoices(xero_invoice_id)
  WHERE xero_invoice_id IS NOT NULL;

ALTER TABLE billing_customers
  ADD COLUMN IF NOT EXISTS xero_contact_id text;

CREATE INDEX IF NOT EXISTS idx_billing_customers_xero_contact_id
  ON billing_customers(xero_contact_id)
  WHERE xero_contact_id IS NOT NULL;

-- Xero refresh tokens rotate on every refresh. The first sync can seed this
-- row from XERO_REFRESH_TOKEN, but after that the app must persist the rotated
-- token here so future syncs keep working without manual secret updates.
CREATE TABLE IF NOT EXISTS billing_xero_tokens (
  id text PRIMARY KEY DEFAULT 'default' CHECK (id = 'default'),
  tenant_id text NOT NULL,
  access_token text,
  refresh_token text NOT NULL,
  expires_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE billing_xero_tokens ENABLE ROW LEVEL SECURITY;
