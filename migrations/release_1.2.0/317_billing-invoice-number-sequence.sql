-- Billing invoice numbering sequence
--
-- What changed:
--   - Adds a year-scoped billing invoice sequence table.
--   - Adds reserve_billing_invoice_number(...) for atomically reserving
--     Stripe invoice numbers such as SLTN-2026/100001.
--
-- Projects depending on this:
--   - selltonai-modal calls reserve_billing_invoice_number before creating
--     Stripe invoices in weekly cron and bill-now flows.
--   - selltonai reads Stripe-hosted invoice links; no frontend payload change.
--
-- Application code update:
--   - Required together with selltonai-modal billing_service.py changes that
--     pass the reserved number to Stripe Invoice.create(number=...).

CREATE TABLE IF NOT EXISTS public.billing_invoice_sequences (
  invoice_year integer PRIMARY KEY,
  next_number integer NOT NULL DEFAULT 100001,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT billing_invoice_sequences_year_check CHECK (invoice_year >= 2000),
  CONSTRAINT billing_invoice_sequences_next_number_check CHECK (next_number > 0)
);

COMMENT ON TABLE public.billing_invoice_sequences IS
  'Year-scoped sequence used by selltonai-modal to reserve explicit Stripe invoice numbers.';

COMMENT ON COLUMN public.billing_invoice_sequences.invoice_year IS
  'Calendar year embedded in Sellton invoice numbers, e.g. 2026 in SLTN-2026/100001.';

COMMENT ON COLUMN public.billing_invoice_sequences.next_number IS
  'Next numeric suffix to reserve for this year. First generated invoice starts at 100001.';

CREATE OR REPLACE FUNCTION public.reserve_billing_invoice_number(
  p_invoice_year integer,
  p_prefix text DEFAULT 'SLTN',
  p_start_number integer DEFAULT 100001,
  p_separator text DEFAULT '/'
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  normalized_prefix text := COALESCE(NULLIF(BTRIM(p_prefix), ''), 'SLTN');
  normalized_separator text := COALESCE(p_separator, '/');
  reserved_number integer;
  formatted_number text;
BEGIN
  IF p_invoice_year IS NULL OR p_invoice_year < 2000 THEN
    RAISE EXCEPTION 'invoice year must be >= 2000';
  END IF;

  IF p_start_number IS NULL OR p_start_number < 1 THEN
    RAISE EXCEPTION 'start number must be >= 1';
  END IF;

  INSERT INTO public.billing_invoice_sequences (invoice_year, next_number)
  VALUES (p_invoice_year, p_start_number)
  ON CONFLICT (invoice_year) DO NOTHING;

  UPDATE public.billing_invoice_sequences
  SET next_number = next_number + 1,
      updated_at = now()
  WHERE invoice_year = p_invoice_year
  RETURNING next_number - 1 INTO reserved_number;

  formatted_number := format(
    '%s-%s%s%s',
    normalized_prefix,
    p_invoice_year,
    normalized_separator,
    lpad(reserved_number::text, 6, '0')
  );

  IF length(formatted_number) > 26 THEN
    RAISE EXCEPTION 'invoice number % exceeds Stripe maximum length of 26 characters', formatted_number;
  END IF;

  RETURN formatted_number;
END;
$$;

COMMENT ON FUNCTION public.reserve_billing_invoice_number(integer, text, integer, text) IS
  'Atomically reserves the next explicit Stripe invoice number for a calendar year.';

REVOKE ALL ON TABLE public.billing_invoice_sequences FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.reserve_billing_invoice_number(integer, text, integer, text) FROM PUBLIC;

GRANT SELECT, INSERT, UPDATE ON TABLE public.billing_invoice_sequences TO service_role;
GRANT EXECUTE ON FUNCTION public.reserve_billing_invoice_number(integer, text, integer, text) TO service_role;
