-- Reverses 433. The backoffice treats the missing table as "not deployed": the agent's daily model spend cap comes
-- from the environment again (CS_LLM_DAILY_USD_CAP, or no cap when that is unset), and /cs/settings says the setting
-- cannot be saved here.
-- Lossy: the saved settings and their whole history. Copy both tables first to keep who changed what and why.
DROP TABLE IF EXISTS public.cs_settings_history;
DROP TABLE IF EXISTS public.cs_settings;
DROP FUNCTION IF EXISTS public.cs_settings_history_append_only();
DROP FUNCTION IF EXISTS public.cs_settings_record_history();
DROP FUNCTION IF EXISTS public.cs_settings_touch();
