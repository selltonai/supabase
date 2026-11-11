-- Reverses 431. Lossy once rows exist: the table is the record of which workspaces the new engine serves.
-- Copy public.workspace_switch first if it has rows, and do not roll back while the engine reads it to decide
-- which workspaces to serve (after E-M0 step 3).
SET LOCAL lock_timeout = '10s';
DROP TABLE IF EXISTS public.workspace_switch;
