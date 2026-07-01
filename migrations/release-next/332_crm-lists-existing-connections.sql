-- 332 — Phase 1 (LinkedIn connections campaigns): let an operator declare a CSV
-- import / CRM list as "my LinkedIn connections" at import time. Campaigns built
-- from a flagged list auto-default to the message-first (no-invite) connections
-- sequence (campaigns.metadata.is_existing_connections), so the campaign skips
-- the invitation and messages the existing connection directly.
--
-- Additive + non-breaking: defaults false, so existing lists and campaigns are
-- unchanged. Safe to drop while empty.

ALTER TABLE public.crm_lists
  ADD COLUMN IF NOT EXISTS is_existing_connections boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.crm_lists.is_existing_connections IS
  'Operator-declared: this list is their existing 1st-degree LinkedIn connections. Campaigns built from it default to the message-first connections sequence (no invitation).';

-- Verify:
--   select column_name, data_type, column_default
--   from information_schema.columns
--   where table_name = 'crm_lists' and column_name = 'is_existing_connections';
