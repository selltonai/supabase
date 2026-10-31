-- Part D (PLAN_REP_VOICE_AND_WRITING_FIXES_2026_10_30, D10/D10b): the workspace's operating hours and days.
--
-- send_window_start / send_window_end are minutes after midnight (07:30 = 450), end EXCLUSIVE (18:00 = 1080 means the
-- last send minute is 17:59). send_days are weekdays, 0 = Sunday ... 6 = Saturday (the JavaScript and moment.day()
-- numbering the mail service already uses).
--
-- The clock is the campaign's timezone (campaigns.campaign_timezone); the workspace says which hours and which days.
--
-- Owners/consumers:
--   - selltonai writes all three from Settings (admin-only keys in api/organization-settings); LinkedIn dispatch and
--     approved LinkedIn replies wait for the window; email sends pass it to the mail service as businessHours.
--   - selltonai-modal reads it for the email autopilot's working-hours flag and the weekend skip.
--
-- NULL (all three) means "not set": every channel keeps today's window (email 09:00-18:00 Mon-Fri in Modal, the mail
-- service's own defaults, LinkedIn 08:00-19:00 weekdays). The three are set and cleared together. No backfill.
-- Additive and safe to drop (rollback/414_organization-settings-send-window.rollback.sql). Row-level security is the
-- table's own and is unchanged.

alter table public.organization_settings
    add column if not exists send_window_start smallint;
alter table public.organization_settings
    add column if not exists send_window_end smallint;
alter table public.organization_settings
    add column if not exists send_days smallint[];

do $$
begin
    if not exists (
        select 1 from pg_constraint
        where conname = 'organization_settings_send_window_check'
          and conrelid = 'public.organization_settings'::regclass
    ) then
        alter table public.organization_settings
            add constraint organization_settings_send_window_check
            check (
                (send_window_start is null and send_window_end is null and send_days is null)
                or (
                    send_window_start is not null
                    and send_window_end is not null
                    and send_days is not null
                    and send_window_start between 0 and 1439
                    and send_window_end between 1 and 1440
                    and send_window_end > send_window_start
                    and cardinality(send_days) between 1 and 7
                    and send_days <@ array[0, 1, 2, 3, 4, 5, 6]::smallint[]
                )
            );
    end if;
end $$;

comment on column public.organization_settings.send_window_start is
    'Workspace sending window start, minutes after midnight in the campaign timezone (07:30 = 450); NULL = not set.';
comment on column public.organization_settings.send_window_end is
    'Workspace sending window end, minutes after midnight, exclusive (18:00 = 1080); NULL = not set.';
comment on column public.organization_settings.send_days is
    'Workspace sending days, 0 = Sunday ... 6 = Saturday; NULL = not set (today''s windows apply).';

-- Verify:
-- select column_name, data_type, is_nullable, column_default
--   from information_schema.columns
--  where table_schema = 'public' and table_name = 'organization_settings' and column_name like 'send_%';
--   -> send_days | ARRAY | YES | (null); send_window_end | smallint | YES | (null); send_window_start | smallint | YES | (null)
-- select pg_get_constraintdef(oid) from pg_constraint where conname = 'organization_settings_send_window_check';
-- select count(*) filter (where send_days is not null) as set, count(*) as workspaces from public.organization_settings;
