-- Reverses 429. The backoffice treats the missing table as "feature not deployed": the margin panel, the Billing
-- margin column, the negative-contribution card and the agent's economics facts show nothing, and the margin floor
-- check passes proposals through unchecked (it says so).
-- Lossy only for history: every row is a snapshot the nightly job recomputes from usage, billing and the connection
-- ledger, so re-applying 429 and running it again restores the recent cycles. Copy the table first to keep older ones.
DROP TABLE IF EXISTS public.workspace_economics;
