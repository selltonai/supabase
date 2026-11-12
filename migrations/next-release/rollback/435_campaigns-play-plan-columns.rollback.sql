-- Reverses 435: drops the two play plan columns of campaigns. The keys campaign_goal.conversation_plan and
-- campaign_goal.note_lines were never removed by the migration, so rows the backend has not rewritten since keep their
-- data there; data written only to the columns after 435 is lost. Run it only after the backend and the app that read
-- the columns are rolled back first.
SET LOCAL lock_timeout = '10s';
ALTER TABLE public.campaigns
  DROP COLUMN IF EXISTS conversation_plan,
  DROP COLUMN IF EXISTS note_lines;
