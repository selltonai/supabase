-- Reverses 410. The Modal code tolerates the missing column (it logs and goes on); review cards
-- then fall back to the scorer text.
ALTER TABLE public.companies
  DROP COLUMN IF EXISTS discovery_gate;
