-- Reverses 409. The BFF tolerates the missing column (it saves the other settings, logs loudly and prefills 'UTC'), so
-- this can run while the app is live; workspaces then lose the time zone they set.
alter table public.organization_settings
    drop constraint if exists organization_settings_timezone_shape;
alter table public.organization_settings
    drop column if exists timezone;
