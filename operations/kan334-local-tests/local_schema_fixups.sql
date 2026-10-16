-- Local-only gaps between full_schema.sql (2026-03 snapshot) plus later migrations and the live schema.
-- Applied to the throwaway test database only; never a migration.
ALTER TABLE public.contacts ADD COLUMN IF NOT EXISTS user_id text;
ALTER TABLE public.companies ADD COLUMN IF NOT EXISTS user_id text;
