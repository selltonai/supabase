-- Reverses 425. The app ignores a missing accepted_at column (it logs once and goes on), so the relation state and
-- the accept wakeup work as before; only the per-line acceptance count loses its times.
DROP INDEX IF EXISTS public.idx_campaign_contacts_campaign_accepted_at;
ALTER TABLE public.campaign_contacts DROP COLUMN IF EXISTS accepted_at;
