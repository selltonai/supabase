-- ============================================================
-- Migration: 427_backoffice-cs-agent-commercial (stage: next-release/427; renumber at promotion if 427 is taken)
-- Date:      2026-11-11
-- Purpose:   The backoffice's customer-success agent, its commercial tables: the money controls staff set per
--            workspace, the policies the agent proposes them from, and the company data it reads.
--            1. workspace_plans: one commercial plan per workspace (self_serve, pilot, deployment) with its own
--               fee, included usage, term, seats and success criteria. At most one active plan per workspace.
--            2. workspace_price_overrides: a price per workspace (or per person, for a seat) for any priced item,
--               as an amount or a percent off the list price. The item is a billing_settings key.
--            3. workspace_allowances: a usage limit (an amount, an end time, or both) that the backoffice enforces
--               through the work-access override, with the spend as last computed by its 15-minute job and that
--               job's claim. At most one active allowance per workspace.
--            4. seat_discounts: a time-boxed percent off a seat (per workspace or per person); never on usage.
--            5. trial_policies, discount_policies: one current row per door, segment (and product), with every
--               change kept as a row. The caps are CHECKs on each row; default terms are proposed later and
--               confirmed by a person. The seed has caps and mode 'manual' only: no default terms.
--            6. connection_ledger: who held which provider account from when to when, and its monthly cost.
--            7. workspace_company_profile: the company data the backoffice holds per workspace, and its
--               watchlist (watch, watch_reason).
--            8. cs_customer_signals: Brain signals on watched companies, one row per Brain signal id;
--               cs_brain_cursor: the backoffice's own place in the signals feed, one row per environment.
-- Projects:  selltonai-database/supabase (owner). backoffice is the only writer of all of it and the only reader
--            today. selltonai-modal may read workspace_plans, workspace_price_overrides and seat_discounts in a
--            later billing release; until then nothing outside the backoffice reads these tables, and nothing
--            here changes what is billed. selltonai, the mobile service and the engine: none.
-- Contract:  Additive. Ten new tables and three seeded policy rows (caps and mode only); no other object changes.
--            No price value changes and no row is written to billing_settings. Service role only: RLS on with no
--            policies, and anon and authenticated get no table privileges.
--            A plan, price override, allowance or seat discount is active (or ended, spent, expired, converted)
--            only with approved_by and approved_at set; a policy row is current (or superseded) only with
--            confirmed_by and confirmed_at set, and grants automatically only with default terms set.
--            Writers make an insert single with dedupe_key (unique when set), as cs_recommendations does.
--            The backoffice treats a missing table as "feature not deployed", so this file and the backoffice
--            build can ship in either order. Application code: none must ship together with this file.
-- Depends:   public.organization (release_1.0.0), public.cs_recommendations (422),
--            public.update_updated_at_column() (release_1.0.0; last re-declared by 300). billing_settings (382) is
--            not read or written; workspace_price_overrides.item holds its keys as text.
-- Rollback:  rollback/427_backoffice-cs-agent-commercial.rollback.sql
--
-- Definitions:
--   Actor           set_by, created_by, approved_by, confirmed_by, handled_by: 'agent', or the staff user's sign-in
--                   email. Staff users live in the backoffice's own store, so no key.
--   Person          user_id: the Clerk user id (text, no key), as linkedin_accounts and org_seats hold it.
--   Effective price the workspace_price_overrides row with status 'active' and starts_at <= now() < ends_at (or no
--                   ends_at) for the item and person (a per-person row wins over the workspace row); among several,
--                   the latest starts_at. No such row: the list price.
--   Door            'web' or 'mobile', the way the workspace signed up (organization.signup_source).
--   Segment         'all' for the whole door, else the backoffice's segment key.
-- ============================================================

-- organization is read on every request; fail fast instead of queueing behind a long transaction (the runner rolls
-- the file back and it can be re-run).
SET LOCAL lock_timeout = '10s';

-- 1. Plans ---------------------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.workspace_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  plan text NOT NULL CHECK (plan IN ('self_serve', 'pilot', 'deployment')),
  -- The deal's own numbers (free per deal). NULL: none.
  fee_usd numeric(12, 2) CHECK (fee_usd IS NULL OR fee_usd >= 0),
  included_usage_usd numeric(12, 2) CHECK (included_usage_usd IS NULL OR included_usage_usd >= 0),
  term_start date,
  term_end date,
  seats_included integer CHECK (seats_included IS NULL OR seats_included >= 0),
  -- What the pilot or deployment must reach (for example meetings booked by a date), as the backoffice writes it.
  success_criteria jsonb NOT NULL DEFAULT '{}'::jsonb,
  -- The staff member who runs the account.
  owner text CHECK (owner IS NULL OR char_length(owner) <= 320),
  status text NOT NULL DEFAULT 'proposed'
    CHECK (status IN ('proposed', 'active', 'converted', 'ended', 'cancelled')),
  -- The plan this one turned into (a pilot converted to a deployment). That plan cannot be deleted on its own.
  converted_to uuid REFERENCES public.workspace_plans(id),
  notes text CHECK (notes IS NULL OR char_length(notes) <= 4000),
  recommendation_id uuid REFERENCES public.cs_recommendations(id) ON DELETE SET NULL,
  dedupe_key text CHECK (dedupe_key IS NULL OR char_length(dedupe_key) <= 300),
  created_by text NOT NULL CHECK (char_length(created_by) BETWEEN 1 AND 320),
  updated_by text,
  approved_by text,
  approved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT workspace_plans_term_check CHECK (term_start IS NULL OR term_end IS NULL OR term_end >= term_start),
  CONSTRAINT workspace_plans_approval_check CHECK (
    status NOT IN ('active', 'converted', 'ended')
    OR (approved_by IS NOT NULL AND approved_at IS NOT NULL)
  ),
  CONSTRAINT workspace_plans_converted_check CHECK (
    (status <> 'converted' OR converted_to IS NOT NULL) AND (converted_to IS NULL OR converted_to <> id)
  ),
  -- A pilot is time-boxed: it is not active without its term.
  CONSTRAINT workspace_plans_pilot_term_check CHECK (
    plan <> 'pilot' OR status <> 'active' OR (term_start IS NOT NULL AND term_end IS NOT NULL)
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS workspace_plans_one_active_unique
  ON public.workspace_plans (organization_id)
  WHERE status = 'active';
CREATE UNIQUE INDEX IF NOT EXISTS workspace_plans_dedupe_unique
  ON public.workspace_plans (dedupe_key)
  WHERE dedupe_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS workspace_plans_org_idx
  ON public.workspace_plans (organization_id, created_at DESC);
CREATE INDEX IF NOT EXISTS workspace_plans_status_idx
  ON public.workspace_plans (plan, status);

-- 2. Price overrides -----------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.workspace_price_overrides (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  -- A billing_settings key (the price list), or a key the price list adds later. Lower case, digits, underscores.
  item text NOT NULL CHECK (item ~ '^[a-z][a-z0-9_]{0,79}$'),
  -- Exactly one: the price itself, or a percent off the list price.
  value_usd numeric(12, 2) CHECK (value_usd IS NULL OR value_usd >= 0),
  percent numeric(5, 2) CHECK (percent IS NULL OR (percent >= 0 AND percent <= 100)),
  -- NULL: the whole workspace. Set: this person's seat.
  user_id text CHECK (user_id IS NULL OR char_length(user_id) BETWEEN 1 AND 200),
  starts_at timestamptz NOT NULL DEFAULT now(),
  ends_at timestamptz,
  reason text NOT NULL CHECK (char_length(reason) BETWEEN 1 AND 2000),
  set_by text NOT NULL CHECK (char_length(set_by) BETWEEN 1 AND 320),
  status text NOT NULL DEFAULT 'proposed' CHECK (status IN ('proposed', 'active', 'ended', 'dismissed')),
  approved_by text,
  approved_at timestamptz,
  ended_by text,
  ended_at timestamptz,
  recommendation_id uuid REFERENCES public.cs_recommendations(id) ON DELETE SET NULL,
  dedupe_key text CHECK (dedupe_key IS NULL OR char_length(dedupe_key) <= 300),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT workspace_price_overrides_value_check CHECK ((value_usd IS NULL) <> (percent IS NULL)),
  CONSTRAINT workspace_price_overrides_window_check CHECK (ends_at IS NULL OR ends_at > starts_at),
  CONSTRAINT workspace_price_overrides_approval_check CHECK (
    status NOT IN ('active', 'ended')
    OR (approved_by IS NOT NULL AND approved_at IS NOT NULL)
  ),
  CONSTRAINT workspace_price_overrides_ended_check CHECK (
    status <> 'ended' OR (ended_by IS NOT NULL AND ended_at IS NOT NULL)
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS workspace_price_overrides_dedupe_unique
  ON public.workspace_price_overrides (dedupe_key)
  WHERE dedupe_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS workspace_price_overrides_active_idx
  ON public.workspace_price_overrides (organization_id, item, starts_at DESC)
  WHERE status = 'active';
CREATE INDEX IF NOT EXISTS workspace_price_overrides_org_idx
  ON public.workspace_price_overrides (organization_id, created_at DESC);

-- 3. Allowances ----------------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.workspace_allowances (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('trial', 'prepaid', 'pilot', 'goodwill')),
  -- At least one of the two: an amount at customer prices, an end time, or both.
  amount_usd numeric(12, 2) CHECK (amount_usd IS NULL OR amount_usd > 0),
  expires_at timestamptz,
  starts_at timestamptz NOT NULL DEFAULT now(),
  -- When the amount is spent or the time is up: work pauses, or continues on normal billing.
  on_end text NOT NULL DEFAULT 'pause' CHECK (on_end IN ('pause', 'continue_billed')),
  -- The plan whose included usage this is (pilot, deployment), when there is one.
  plan_id uuid REFERENCES public.workspace_plans(id) ON DELETE SET NULL,
  -- Prepaid: the Stripe invoice it was paid on, or invoiced = true when it is invoiced another way.
  stripe_invoice_id text CHECK (stripe_invoice_id IS NULL OR char_length(stripe_invoice_id) BETWEEN 1 AND 200),
  invoiced boolean NOT NULL DEFAULT false,
  reason text NOT NULL CHECK (char_length(reason) BETWEEN 1 AND 2000),
  set_by text NOT NULL CHECK (char_length(set_by) BETWEEN 1 AND 320),
  approved_by text,
  approved_at timestamptz,
  status text NOT NULL DEFAULT 'proposed'
    CHECK (status IN ('proposed', 'active', 'spent', 'expired', 'ended', 'dismissed')),
  -- Usage at customer prices since starts_at, as the 15-minute job last computed it.
  spent_usd numeric(12, 2) NOT NULL DEFAULT 0 CHECK (spent_usd >= 0),
  last_computed_at timestamptz,
  -- The highest alert already raised (50, 80, 100 percent of the amount), so each is raised once.
  last_alert_percent smallint NOT NULL DEFAULT 0 CHECK (last_alert_percent IN (0, 50, 80, 100)),
  -- The 15-minute job claims the row; another run skips it until the claim is stale (a crash).
  claimed_at timestamptz,
  ended_by text,
  ended_at timestamptz,
  recommendation_id uuid REFERENCES public.cs_recommendations(id) ON DELETE SET NULL,
  dedupe_key text CHECK (dedupe_key IS NULL OR char_length(dedupe_key) <= 300),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT workspace_allowances_bound_check CHECK (amount_usd IS NOT NULL OR expires_at IS NOT NULL),
  CONSTRAINT workspace_allowances_window_check CHECK (expires_at IS NULL OR expires_at > starts_at),
  CONSTRAINT workspace_allowances_approval_check CHECK (
    status NOT IN ('active', 'spent', 'expired', 'ended')
    OR (approved_by IS NOT NULL AND approved_at IS NOT NULL)
  ),
  CONSTRAINT workspace_allowances_prepaid_invoice_check CHECK (
    kind <> 'prepaid' OR status IN ('proposed', 'dismissed') OR stripe_invoice_id IS NOT NULL OR invoiced
  ),
  CONSTRAINT workspace_allowances_ended_check CHECK (
    status NOT IN ('spent', 'expired', 'ended') OR (ended_by IS NOT NULL AND ended_at IS NOT NULL)
  ),
  CONSTRAINT workspace_allowances_spent_check CHECK (status <> 'spent' OR amount_usd IS NOT NULL),
  CONSTRAINT workspace_allowances_expired_check CHECK (status <> 'expired' OR expires_at IS NOT NULL)
);

-- One active allowance per workspace: it holds the workspace's single work-access override.
CREATE UNIQUE INDEX IF NOT EXISTS workspace_allowances_one_active_unique
  ON public.workspace_allowances (organization_id)
  WHERE status = 'active';
CREATE UNIQUE INDEX IF NOT EXISTS workspace_allowances_dedupe_unique
  ON public.workspace_allowances (dedupe_key)
  WHERE dedupe_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS workspace_allowances_job_idx
  ON public.workspace_allowances (claimed_at NULLS FIRST)
  WHERE status = 'active';
CREATE INDEX IF NOT EXISTS workspace_allowances_org_idx
  ON public.workspace_allowances (organization_id, created_at DESC);

-- 4. Seat discounts ------------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.seat_discounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  -- NULL: every seat of the product in the workspace. Set: this person's seat.
  user_id text CHECK (user_id IS NULL OR char_length(user_id) BETWEEN 1 AND 200),
  product text NOT NULL CHECK (product IN ('mobile_seat', 'web_seat')),
  -- Percent off the seat's list price, within the cap.
  percent numeric(5, 2) NOT NULL CHECK (percent > 0 AND percent <= 50),
  -- How many 4-week cycles, within the cap. NULL: until removed (staff only).
  cycles integer CHECK (cycles IS NULL OR cycles BETWEEN 1 AND 3),
  starts_at timestamptz NOT NULL DEFAULT now(),
  ends_at timestamptz,
  reason text NOT NULL CHECK (char_length(reason) BETWEEN 1 AND 2000),
  set_by text NOT NULL CHECK (char_length(set_by) BETWEEN 1 AND 320),
  approved_by text,
  approved_at timestamptz,
  status text NOT NULL DEFAULT 'proposed' CHECK (status IN ('proposed', 'active', 'ended', 'dismissed')),
  ended_by text CHECK (ended_by IS NULL OR ended_by IN ('web_activation', 'staff', 'expiry')),
  ended_at timestamptz,
  recommendation_id uuid REFERENCES public.cs_recommendations(id) ON DELETE SET NULL,
  dedupe_key text CHECK (dedupe_key IS NULL OR char_length(dedupe_key) <= 300),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT seat_discounts_window_check CHECK (ends_at IS NULL OR ends_at > starts_at),
  CONSTRAINT seat_discounts_agent_cycles_check CHECK (set_by <> 'agent' OR cycles IS NOT NULL),
  CONSTRAINT seat_discounts_approval_check CHECK (
    status NOT IN ('active', 'ended')
    OR (approved_by IS NOT NULL AND approved_at IS NOT NULL)
  ),
  CONSTRAINT seat_discounts_ended_check CHECK (
    status <> 'ended' OR (ended_by IS NOT NULL AND ended_at IS NOT NULL)
  )
);

-- One active discount per workspace, product and person (or the workspace-wide one): discounts never stack.
CREATE UNIQUE INDEX IF NOT EXISTS seat_discounts_one_active_unique
  ON public.seat_discounts (organization_id, product, (coalesce(user_id, '')))
  WHERE status = 'active';
CREATE UNIQUE INDEX IF NOT EXISTS seat_discounts_dedupe_unique
  ON public.seat_discounts (dedupe_key)
  WHERE dedupe_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS seat_discounts_org_idx
  ON public.seat_discounts (organization_id, created_at DESC);

-- 5. Policies: trials and seat discounts ---------------------------------------------------------------
-- Every change is a row: the agent or staff proposes one, a person confirms it, it becomes current and the row
-- before it is superseded. A door and segment with no current row grants nothing automatically.

CREATE TABLE IF NOT EXISTS public.trial_policies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  door text NOT NULL CHECK (door IN ('web', 'mobile')),
  segment text NOT NULL DEFAULT 'all' CHECK (char_length(segment) BETWEEN 1 AND 80),
  status text NOT NULL DEFAULT 'proposed' CHECK (status IN ('proposed', 'current', 'superseded', 'dismissed')),
  mode text NOT NULL DEFAULT 'manual' CHECK (mode IN ('auto', 'manual', 'off')),
  autonomy_enabled boolean NOT NULL DEFAULT false,
  -- The default terms. NULL: none; the agent proposes them and a person confirms.
  default_days integer,
  default_credit_usd numeric(10, 2),
  default_fees_waived text[] NOT NULL DEFAULT '{}'::text[],
  -- The caps: the bounds on any terms, default or per workspace.
  cap_days_min integer NOT NULL CHECK (cap_days_min >= 3),
  cap_days_max integer NOT NULL CHECK (cap_days_max <= 14),
  cap_credit_usd numeric(10, 2) NOT NULL CHECK (cap_credit_usd >= 0),
  cap_extensions integer NOT NULL DEFAULT 1 CHECK (cap_extensions BETWEEN 0 AND 1),
  reason text CHECK (reason IS NULL OR char_length(reason) <= 2000),
  set_by text NOT NULL CHECK (char_length(set_by) BETWEEN 1 AND 320),
  confirmed_by text,
  confirmed_at timestamptz,
  supersedes_id uuid REFERENCES public.trial_policies(id) ON DELETE SET NULL,
  recommendation_id uuid REFERENCES public.cs_recommendations(id) ON DELETE SET NULL,
  dedupe_key text CHECK (dedupe_key IS NULL OR char_length(dedupe_key) <= 300),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT trial_policies_days_cap_check CHECK (cap_days_min <= cap_days_max),
  CONSTRAINT trial_policies_credit_cap_check CHECK (
    (door = 'web' AND cap_credit_usd <= 100) OR (door = 'mobile' AND cap_credit_usd <= 20)
  ),
  CONSTRAINT trial_policies_default_days_check CHECK (
    default_days IS NULL OR default_days BETWEEN cap_days_min AND cap_days_max
  ),
  CONSTRAINT trial_policies_default_credit_check CHECK (
    default_credit_usd IS NULL OR (default_credit_usd >= 0 AND default_credit_usd <= cap_credit_usd)
  ),
  -- Nothing is granted automatically without confirmed default terms.
  CONSTRAINT trial_policies_auto_terms_check CHECK (
    (mode <> 'auto' AND NOT autonomy_enabled)
    OR (default_days IS NOT NULL AND default_credit_usd IS NOT NULL)
  ),
  CONSTRAINT trial_policies_confirmation_check CHECK (
    status NOT IN ('current', 'superseded')
    OR (confirmed_by IS NOT NULL AND confirmed_at IS NOT NULL)
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS trial_policies_one_current_unique
  ON public.trial_policies (door, segment)
  WHERE status = 'current';
CREATE UNIQUE INDEX IF NOT EXISTS trial_policies_dedupe_unique
  ON public.trial_policies (dedupe_key)
  WHERE dedupe_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS trial_policies_history_idx
  ON public.trial_policies (door, segment, created_at DESC);

CREATE TABLE IF NOT EXISTS public.discount_policies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  door text NOT NULL CHECK (door IN ('web', 'mobile')),
  segment text NOT NULL DEFAULT 'all' CHECK (char_length(segment) BETWEEN 1 AND 80),
  product text NOT NULL CHECK (product IN ('mobile_seat', 'web_seat')),
  status text NOT NULL DEFAULT 'proposed' CHECK (status IN ('proposed', 'current', 'superseded', 'dismissed')),
  mode text NOT NULL DEFAULT 'manual' CHECK (mode IN ('auto', 'manual', 'off')),
  autonomy_enabled boolean NOT NULL DEFAULT false,
  -- The default terms. NULL: none; the agent proposes them and a person confirms.
  default_percent numeric(5, 2),
  default_cycles integer,
  -- The caps: the bounds on any seat discount proposed under this policy.
  cap_percent numeric(5, 2) NOT NULL CHECK (cap_percent > 0 AND cap_percent <= 50),
  cap_cycles integer NOT NULL CHECK (cap_cycles BETWEEN 1 AND 3),
  -- At most one discount per workspace in this many months.
  cap_months_between integer NOT NULL CHECK (cap_months_between >= 6),
  reason text CHECK (reason IS NULL OR char_length(reason) <= 2000),
  set_by text NOT NULL CHECK (char_length(set_by) BETWEEN 1 AND 320),
  confirmed_by text,
  confirmed_at timestamptz,
  supersedes_id uuid REFERENCES public.discount_policies(id) ON DELETE SET NULL,
  recommendation_id uuid REFERENCES public.cs_recommendations(id) ON DELETE SET NULL,
  dedupe_key text CHECK (dedupe_key IS NULL OR char_length(dedupe_key) <= 300),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT discount_policies_default_percent_check CHECK (
    default_percent IS NULL OR (default_percent > 0 AND default_percent <= cap_percent)
  ),
  CONSTRAINT discount_policies_default_cycles_check CHECK (
    default_cycles IS NULL OR default_cycles BETWEEN 1 AND cap_cycles
  ),
  CONSTRAINT discount_policies_auto_terms_check CHECK (
    (mode <> 'auto' AND NOT autonomy_enabled)
    OR (default_percent IS NOT NULL AND default_cycles IS NOT NULL)
  ),
  CONSTRAINT discount_policies_confirmation_check CHECK (
    status NOT IN ('current', 'superseded')
    OR (confirmed_by IS NOT NULL AND confirmed_at IS NOT NULL)
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS discount_policies_one_current_unique
  ON public.discount_policies (door, segment, product)
  WHERE status = 'current';
CREATE UNIQUE INDEX IF NOT EXISTS discount_policies_dedupe_unique
  ON public.discount_policies (dedupe_key)
  WHERE dedupe_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS discount_policies_history_idx
  ON public.discount_policies (door, segment, product, created_at DESC);

-- 6. Connections and their cost ------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.connection_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- The cost stays when the workspace is deleted, without the workspace (as cs_costs).
  organization_id text REFERENCES public.organization(id) ON DELETE SET NULL,
  user_id text CHECK (user_id IS NULL OR char_length(user_id) BETWEEN 1 AND 200),
  -- unipile, gmail_api, or a provider added later.
  provider text NOT NULL CHECK (char_length(provider) BETWEEN 1 AND 40),
  -- The provider's account id (for a mailbox without one, its address).
  account_id text NOT NULL CHECK (char_length(account_id) BETWEEN 1 AND 320),
  kind text NOT NULL CHECK (kind IN ('linkedin', 'mailbox', 'phone')),
  source text NOT NULL CHECK (source IN ('web', 'mobile')),
  connected_at timestamptz NOT NULL,
  disconnected_at timestamptz,
  monthly_cost_usd numeric(10, 2) CHECK (monthly_cost_usd IS NULL OR monthly_cost_usd >= 0),
  -- Set when staff corrected the row: the nightly fill leaves it as it is.
  corrected_by text,
  corrected_at timestamptz,
  notes text CHECK (notes IS NULL OR char_length(notes) <= 2000),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  -- The nightly fill's upsert key.
  CONSTRAINT connection_ledger_account_period_unique UNIQUE (provider, account_id, connected_at),
  CONSTRAINT connection_ledger_window_check CHECK (disconnected_at IS NULL OR disconnected_at >= connected_at),
  CONSTRAINT connection_ledger_corrected_check CHECK ((corrected_by IS NULL) = (corrected_at IS NULL))
);

-- One open period per provider account.
CREATE UNIQUE INDEX IF NOT EXISTS connection_ledger_one_open_unique
  ON public.connection_ledger (provider, account_id)
  WHERE disconnected_at IS NULL;
CREATE INDEX IF NOT EXISTS connection_ledger_org_idx
  ON public.connection_ledger (organization_id, connected_at DESC)
  WHERE organization_id IS NOT NULL;

-- 7. Company profile and the watchlist -----------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.workspace_company_profile (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  -- 'own': the workspace's own company (one per workspace); 'parent' or 'brand': a second company to watch.
  relation text NOT NULL DEFAULT 'own' CHECK (relation IN ('own', 'parent', 'brand')),
  -- Host only, lower case, no scheme and no www.
  domain text NOT NULL CHECK (char_length(domain) BETWEEN 3 AND 253 AND domain = lower(domain) AND domain LIKE '%.%'),
  brain_company_id bigint,
  profile jsonb NOT NULL DEFAULT '{}'::jsonb,
  signals jsonb NOT NULL DEFAULT '[]'::jsonb,
  -- NULL: not fetched yet.
  fetched_at timestamptz,
  -- Where the profile came from (for example the Brain's enrich, its names fallback, or staff).
  source text CHECK (source IS NULL OR char_length(source) BETWEEN 1 AND 60),
  watch boolean NOT NULL DEFAULT true,
  watch_reason text CHECK (watch_reason IS NULL OR char_length(watch_reason) <= 500),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT workspace_company_profile_org_domain_unique UNIQUE (organization_id, domain)
);

CREATE UNIQUE INDEX IF NOT EXISTS workspace_company_profile_one_own_unique
  ON public.workspace_company_profile (organization_id)
  WHERE relation = 'own';
CREATE INDEX IF NOT EXISTS workspace_company_profile_watch_idx
  ON public.workspace_company_profile (brain_company_id)
  WHERE watch AND brain_company_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS workspace_company_profile_fetched_idx
  ON public.workspace_company_profile (fetched_at NULLS FIRST);

-- 8. Customer signals and the backoffice's cursor ------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.cs_customer_signals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  -- The Brain's signal id: the poll's upsert key.
  brain_signal_id bigint NOT NULL,
  -- The watched company the signal is about.
  company_profile_id uuid REFERENCES public.workspace_company_profile(id) ON DELETE SET NULL,
  -- job_change, hiring, funding, news, or what the Brain adds.
  type text NOT NULL CHECK (char_length(type) BETWEEN 1 AND 60),
  occurred_at timestamptz,
  summary text CHECK (summary IS NULL OR char_length(summary) <= 2000),
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  people jsonb NOT NULL DEFAULT '[]'::jsonb,
  -- The agent's read. NULL: not graded yet.
  grade text CHECK (grade IS NULL OR grade IN ('expansion', 'risk', 'champion_change', 'noise')),
  status text NOT NULL DEFAULT 'new' CHECK (status IN ('new', 'seen', 'acted', 'dismissed')),
  handled_by text,
  handled_at timestamptz,
  recommendation_id uuid REFERENCES public.cs_recommendations(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT cs_customer_signals_brain_signal_unique UNIQUE (brain_signal_id),
  CONSTRAINT cs_customer_signals_handled_check CHECK (
    status NOT IN ('acted', 'dismissed') OR (handled_by IS NOT NULL AND handled_at IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS cs_customer_signals_org_idx
  ON public.cs_customer_signals (organization_id, occurred_at DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS cs_customer_signals_open_idx
  ON public.cs_customer_signals (created_at DESC)
  WHERE status IN ('new', 'seen');

CREATE TABLE IF NOT EXISTS public.cs_brain_cursor (
  -- local, stage, production: one row per environment.
  environment text PRIMARY KEY CHECK (char_length(environment) BETWEEN 1 AND 40),
  -- The Brain's opaque cursor, sent back unchanged. NULL: start from the beginning.
  next_after text,
  last_polled_at timestamptz,
  -- The hourly poll claims the row; another run skips it until the claim is stale (a crash).
  claimed_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- updated_at ---------------------------------------------------------------------------------------

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['workspace_plans', 'workspace_price_overrides', 'workspace_allowances', 'seat_discounts',
                           'trial_policies', 'discount_policies', 'connection_ledger', 'workspace_company_profile',
                           'cs_customer_signals', 'cs_brain_cursor'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', 'update_' || t || '_updated_at', t);
    EXECUTE format(
      'CREATE TRIGGER %I BEFORE UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column()',
      'update_' || t || '_updated_at', t);
  END LOOP;
END $$;

-- The policy seed: caps and mode only, no default terms ----------------------------------------------
-- One current row per door for trials; one for the phone seat discount. Re-running adds nothing, and a door that
-- already has any row (a later change by staff) is left alone.

INSERT INTO public.trial_policies
  (door, segment, status, mode, autonomy_enabled, cap_days_min, cap_days_max, cap_credit_usd, cap_extensions,
   reason, set_by, confirmed_by, confirmed_at)
SELECT s.door, 'all', 'current', 'manual', false, 3, 14, s.cap_credit_usd, 1,
       'Caps only; no default terms.', 'migration:427', 'migration:427', now()
FROM (VALUES ('web', 100.00::numeric), ('mobile', 20.00::numeric)) AS s(door, cap_credit_usd)
WHERE NOT EXISTS (SELECT 1 FROM public.trial_policies p WHERE p.door = s.door AND p.segment = 'all');

INSERT INTO public.discount_policies
  (door, segment, product, status, mode, autonomy_enabled, cap_percent, cap_cycles, cap_months_between,
   reason, set_by, confirmed_by, confirmed_at)
SELECT 'mobile', 'all', 'mobile_seat', 'current', 'manual', false, 50, 3, 6,
       'Caps only; no default terms.', 'migration:427', 'migration:427', now()
WHERE NOT EXISTS (
  SELECT 1 FROM public.discount_policies p WHERE p.door = 'mobile' AND p.segment = 'all' AND p.product = 'mobile_seat'
);

-- Access: the service role only ----------------------------------------------------------------------
-- Supabase grants new tables to anon and authenticated by default; take that away. RLS is on with no policies on
-- purpose: the backoffice reads and writes with the service role, and browser keys see nothing.

REVOKE ALL ON TABLE public.workspace_plans, public.workspace_price_overrides, public.workspace_allowances,
  public.seat_discounts, public.trial_policies, public.discount_policies, public.connection_ledger,
  public.workspace_company_profile, public.cs_customer_signals, public.cs_brain_cursor
  FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.workspace_plans, public.workspace_price_overrides, public.workspace_allowances,
  public.seat_discounts, public.trial_policies, public.discount_policies, public.connection_ledger,
  public.workspace_company_profile, public.cs_customer_signals, public.cs_brain_cursor
  TO service_role;

ALTER TABLE public.workspace_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workspace_price_overrides ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workspace_allowances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seat_discounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trial_policies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.discount_policies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.connection_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workspace_company_profile ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cs_customer_signals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cs_brain_cursor ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.workspace_plans IS
  'Backoffice customer-success agent: a workspace''s commercial plan (self_serve, pilot, deployment) with the deal''s own fee, included usage, term, seats and success criteria. At most one active per workspace; active, converted or ended only with approved_by and approved_at. Backoffice only.';
COMMENT ON TABLE public.workspace_price_overrides IS
  'Backoffice customer-success agent: a price per workspace (or per person, for a seat) for a price-list item (a billing_settings key), as value_usd or percent off the list price, exactly one. Active or ended only with approved_by and approved_at. The effective price is the active row in its window with the latest starts_at (a per-person row before the workspace row), else the list price. Backoffice only.';
COMMENT ON TABLE public.workspace_allowances IS
  'Backoffice customer-success agent: a usage limit for a workspace (amount_usd, expires_at, or both), enforced by the backoffice through the work-access override. spent_usd and last_computed_at are written by its 15-minute job, which claims the row with claimed_at. At most one active per workspace; a prepaid row is granted only with a Stripe invoice id or invoiced. Backoffice only.';
COMMENT ON TABLE public.seat_discounts IS
  'Backoffice customer-success agent: a time-boxed percent off a seat (mobile_seat or web_seat), per workspace or per person, within the caps; never on usage. One active per workspace, product and person. Active or ended only with approved_by and approved_at. Backoffice only.';
COMMENT ON TABLE public.trial_policies IS
  'Backoffice customer-success agent: the trial policy per door and segment, every change a row (proposed, current, superseded, dismissed); one current row per door and segment. Caps are CHECKs; default terms are confirmed by a person, and auto mode or autonomy needs them. Backoffice only.';
COMMENT ON TABLE public.discount_policies IS
  'Backoffice customer-success agent: the seat-discount policy per door, segment and product, every change a row; one current row per door, segment and product. Caps are CHECKs; default terms are confirmed by a person, and auto mode or autonomy needs them. Backoffice only.';
COMMENT ON TABLE public.connection_ledger IS
  'Backoffice customer-success agent: which person held which provider account (LinkedIn, mailbox, phone) from when to when, and its monthly cost. Filled nightly by the backoffice (upsert on provider, account_id, connected_at); rows with corrected_by set are kept as staff corrected them. Kept with organization_id NULL when the workspace is deleted. Backoffice only.';
COMMENT ON TABLE public.workspace_company_profile IS
  'Backoffice customer-success agent: the company data held per workspace (its own company, and a parent or brand to watch), refreshed by the backoffice; watch and watch_reason make it the signals watchlist. Backoffice only.';
COMMENT ON TABLE public.cs_customer_signals IS
  'Backoffice customer-success agent: a Brain signal on a watched company, one row per brain_signal_id, with the agent''s grade and the person who handled it. Backoffice only.';
COMMENT ON TABLE public.cs_brain_cursor IS
  'Backoffice customer-success agent: the backoffice''s own place in the Brain''s signals feed, one row per environment (separate from brain_signal_cursor). Backoffice only.';

-- Fail the file if a browser key can still reach a new table.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['workspace_plans', 'workspace_price_overrides', 'workspace_allowances', 'seat_discounts',
                           'trial_policies', 'discount_policies', 'connection_ledger', 'workspace_company_profile',
                           'cs_customer_signals', 'cs_brain_cursor'] LOOP
    IF has_table_privilege('anon', 'public.' || t, 'SELECT')
       OR has_table_privilege('authenticated', 'public.' || t, 'SELECT')
       OR has_table_privilege('anon', 'public.' || t, 'INSERT')
       OR has_table_privilege('authenticated', 'public.' || t, 'INSERT')
       OR has_table_privilege('anon', 'public.' || t, 'UPDATE')
       OR has_table_privilege('authenticated', 'public.' || t, 'UPDATE')
       OR has_table_privilege('anon', 'public.' || t, 'DELETE')
       OR has_table_privilege('authenticated', 'public.' || t, 'DELETE') THEN
      RAISE EXCEPTION '427: anon or authenticated can still read or write %', t;
    END IF;
  END LOOP;
END $$;

-- Verify (read-only):
-- select relname, relrowsecurity from pg_class
--  where relname in ('workspace_plans', 'workspace_price_overrides', 'workspace_allowances', 'seat_discounts',
--                    'trial_policies', 'discount_policies', 'connection_ledger', 'workspace_company_profile',
--                    'cs_customer_signals', 'cs_brain_cursor') order by 1;
--   -> ten rows, all true
-- select door, segment, status, mode, default_days, default_credit_usd from public.trial_policies order by 1;
--   -> mobile and web, all, current, manual, NULL, NULL
-- select door, product, status, mode, default_percent, default_cycles from public.discount_policies;
--   -> mobile, mobile_seat, current, manual, NULL, NULL
-- select has_table_privilege('anon', 'public.workspace_allowances', 'SELECT'),            -- false
--        has_table_privilege('service_role', 'public.workspace_allowances', 'INSERT');    -- true
