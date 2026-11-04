-- Reverses 414. Readers treat a missing column as "not set" (today's windows), so this can run while the app is live;
-- workspaces then lose the hours and days they set.
alter table public.organization_settings
    drop constraint if exists organization_settings_send_window_check;
alter table public.organization_settings
    drop column if exists send_days;
alter table public.organization_settings
    drop column if exists send_window_end;
alter table public.organization_settings
    drop column if exists send_window_start;
