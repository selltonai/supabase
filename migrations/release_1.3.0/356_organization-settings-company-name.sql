-- H-7: add a dedicated public sender-company identity for generated outreach.
--
-- Owners/consumers:
--   - selltonai writes this field from General Settings.
--   - selltonai-modal reads it for email/LinkedIn sender context.
--   - Existing workspaces remain NULL and fall back to organization.name.
--
-- No backfill is attempted because a workspace label may contain a person's
-- name or internal qualifier and is not necessarily the public company name.

alter table public.organization_settings
    add column if not exists company_name text;

comment on column public.organization_settings.company_name is
    'Public company name used as sender identity in generated outreach; falls back to organization.name when NULL or blank.';
