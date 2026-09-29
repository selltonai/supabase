\set ON_ERROR_STOP on
-- Run against an isolated PostgreSQL test database containing public.contacts.
BEGIN;
\ir ../migrations/next-release/373_contacts-professional-summary.sql
\ir ../migrations/next-release/373_contacts-professional-summary.sql
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'contacts'
          AND column_name = 'professional_summary' AND data_type = 'jsonb'
          AND column_default = '''{}''::jsonb'
    ) THEN
        RAISE EXCEPTION 'professional_summary must be JSONB with empty object default';
    END IF;
END $$;
ROLLBACK;
