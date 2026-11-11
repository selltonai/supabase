-- Reverses 427. The backoffice treats the missing tables as "feature not deployed": the commercial panel, the
-- policies, the connection costs, the company profiles and the customer signals show nothing.
-- Lossy once rows exist: dropping the tables drops every plan, price override, allowance, seat discount, policy
-- change, connection period, company profile and signal written after 427. Copy them first if any are set.
-- An active allowance holds the workspace's work-access override: end it in the backoffice before rolling back,
-- or the override stays as it was last set.
DROP TABLE IF EXISTS public.cs_customer_signals;
DROP TABLE IF EXISTS public.cs_brain_cursor;
DROP TABLE IF EXISTS public.workspace_company_profile;
DROP TABLE IF EXISTS public.connection_ledger;
DROP TABLE IF EXISTS public.discount_policies;
DROP TABLE IF EXISTS public.trial_policies;
DROP TABLE IF EXISTS public.seat_discounts;
DROP TABLE IF EXISTS public.workspace_allowances;
DROP TABLE IF EXISTS public.workspace_price_overrides;
DROP TABLE IF EXISTS public.workspace_plans;
