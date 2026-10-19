-- Reverses 404. Modal (sender_calendar.py) and the BFF (/api/me/calendar) treat a missing table as "no
-- connection", so every sender falls back to the workspace calendar. Every person's own connection (and its sealed
-- key) is lost: they reconnect after a re-apply.
DROP TABLE IF EXISTS public.user_calendar_connections;
DROP FUNCTION IF EXISTS public.update_user_calendar_connections_updated_at();
