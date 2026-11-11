-- Reverses 428. The backoffice treats the missing table as "feature not deployed": archive and delete are not offered.
-- Lossy once rows exist: dropping the table drops every request and its receipts, which are the only record of what
-- was archived or deleted where. Copy public.workspace_deletions first if it has rows, and do not roll back while a
-- request is open (status pending, running or failed): a service may be draining it.
DROP TABLE IF EXISTS public.workspace_deletions;
