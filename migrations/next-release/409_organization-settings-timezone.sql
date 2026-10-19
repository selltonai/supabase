-- KAN-322 FR-C8b (D89): the workspace's time zone, an IANA name such as Europe/Berlin.
--
-- Owners/consumers:
--   - selltonai writes it from Settings (the workspace section) and, when it is empty, from the browser's zone during
--     onboarding. The wizard prefills each new play's campaign_timezone with it (today 'UTC').
--   - The dashboard keeps the viewer's own day (tz_offset, FR-C4d); this column does not change it.
--   - selltonai-modal does not read it yet. Its Cal.com settings read api_credentials.cal_com_timezone (a JSON key, not
--     this column), so nothing there changes.
--
-- NULL means "not set": every reader keeps today's behaviour (the wizard prefills 'UTC'). No backfill: a workspace's
-- zone cannot be guessed from its data, and onboarding or Settings fill it.
--
-- The shape check only keeps out text that cannot be a zone name; the BFF validates real names with Intl before it
-- writes. Postgres' own zone list is not used, so a name the browser knows and this server's tzdata does not is never
-- refused. Additive and safe to drop (rollback/409_organization-settings-timezone.rollback.sql). Row-level security is
-- the table's own and is unchanged.

alter table public.organization_settings
    add column if not exists timezone text;

do $$
begin
    if not exists (
        select 1 from pg_constraint
        where conname = 'organization_settings_timezone_shape'
          and conrelid = 'public.organization_settings'::regclass
    ) then
        alter table public.organization_settings
            add constraint organization_settings_timezone_shape
            check (
                timezone is null
                or (char_length(timezone) between 1 and 64
                    and timezone ~ '^[A-Za-z][A-Za-z0-9_+-]*(/[A-Za-z0-9_+-]+)*$')
            );
    end if;
end $$;

comment on column public.organization_settings.timezone is
    'The workspace''s IANA time zone (Europe/Berlin). Prefills each new play''s campaign_timezone; NULL = not set (today''s UTC prefill).';

-- Verify:
-- select column_name, data_type, is_nullable, column_default
--   from information_schema.columns
--  where table_schema = 'public' and table_name = 'organization_settings' and column_name = 'timezone';
--   -> timezone | text | YES | (null)
-- select pg_get_constraintdef(oid) from pg_constraint where conname = 'organization_settings_timezone_shape';
-- select count(*) filter (where timezone is not null) as set, count(*) as workspaces from public.organization_settings;
