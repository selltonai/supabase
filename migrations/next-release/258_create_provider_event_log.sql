-- ============================================================
--  Migration: 246_create_provider_event_log
--  Date:      2026-05-05
--  Author:    Sellton AI — LinkedIn integration V3 / Phase B
--  Plan ref:  /Ground Truth/LINKEDIN_INTEGRATION_EXECUTION_PLAN_V3.md  §6.2
--  Build log: /Ground Truth/LINKEDIN_V3_BUILD_LOG.md  §4 → Phase B
--  Depends:   none
-- ============================================================
--
--  Purpose
--  -------
--  Append-only ingress ledger for every webhook payload received from any
--  provider (Unipile is the only one today; others may follow). This table
--  is the foundation for V3's webhook hardening:
--
--    • Dedup anchor — UNIQUE(dedup_key) makes Unipile retries no-ops via
--      ON CONFLICT DO NOTHING. Without this, a network blip or replayed
--      delivery doubles every notification we fire and every row we write.
--
--    • Forensic record — full raw payload preserved even after the
--      account it belongs to is disconnected. Lesson learned from the
--      prior cycle: linkedin_messages CASCADEd on disconnect, so we lost
--      every captured payload the moment the test account went away.
--      THIS TABLE DELIBERATELY HAS NO FOREIGN KEYS so cascade can't
--      delete history.
--
--    • Channel gate substrate — Step 5 of the V3 §8.4 ingress order
--      ("reject or ignore non-LinkedIn events for LinkedIn business
--      logic") reads from the normalized `channel` column on this row.
--      Webhook handlers do not infer channel from route name (V3 §8.5).
--
--  Scope rules
--  -----------
--    • account_id is the PROVIDER's account identifier (Unipile-side
--      string). Denormalized so the row is self-sufficient.
--    • organization_id and owner_user_id are looked up from
--      linkedin_accounts AT INGRESS TIME. They may be NULL when the event
--      arrives for an account we don't have a row for yet (e.g. a stale
--      webhook from a previously-deleted account). Handlers must
--      tolerate NULLs and either ignore or log appropriately.
--
--  Idempotency
--  -----------
--  Fully re-runnable. CREATE TABLE IF NOT EXISTS, CREATE INDEX IF NOT
--  EXISTS, DROP POLICY IF EXISTS. NOTIFY pgrst at end.
--
--  Verify (after apply)
--  --------------------
--    SELECT * FROM provider_event_log LIMIT 0;                                  -- columns load
--    SELECT relrowsecurity FROM pg_class WHERE relname='provider_event_log';    -- t
--    SELECT count(*) FROM pg_indexes WHERE tablename='provider_event_log';      -- 5 (PK + 4)
--
--  Rollback (safe while empty)
--  ---------------------------
--    DROP TABLE IF EXISTS public.provider_event_log CASCADE;
-- ============================================================


CREATE TABLE IF NOT EXISTS public.provider_event_log (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Provider identification (V3 §6.2)
  provider              TEXT NOT NULL DEFAULT 'UNIPILE'
                        CHECK (provider IN ('UNIPILE', 'NATIVE_LINKEDIN', 'OTHER')),
  channel               TEXT NOT NULL
                        CHECK (channel IN ('LINKEDIN', 'WHATSAPP', 'MESSENGER',
                                           'TWITTER', 'INSTAGRAM', 'TIKTOK',
                                           'EMAIL', 'UNKNOWN')),
  account_type          TEXT,                    -- raw provider-side type when known

  -- Event identifiers
  external_event_id     TEXT,                    -- provider's own event ID (when present)
  event_type            TEXT NOT NULL,           -- normalized event type, e.g. 'message.received'
  dedup_key             TEXT NOT NULL UNIQUE,    -- (provider, external_event_id) or fallback hash

  -- Provider-side account identification (denormalized, NOT a FK)
  -- This is intentionally TEXT and not a FK so disconnect/re-delete of
  -- linkedin_accounts cannot CASCADE-delete this audit row. The audit
  -- ledger outlives the account row.
  account_id            TEXT,                    -- provider's account identifier

  -- Sellton-side attribution (best-effort at ingress; nullable)
  organization_id       TEXT,
  owner_user_id         TEXT,

  -- Processing pipeline state
  processing_status     TEXT NOT NULL DEFAULT 'received'
                        CHECK (processing_status IN ('received', 'ignored', 'processed',
                                                     'failed', 'duplicate')),
  error_message         TEXT,

  -- Timestamps
  received_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),    -- when we got it
  occurred_at           TIMESTAMPTZ,                            -- provider's claimed event time

  -- Full raw body — bytes-level fidelity for forensics and replay.
  -- JSONB rather than TEXT so we can query into it without parsing,
  -- but the application MUST always parse the original body bytes
  -- before HMAC/auth verification — never round-trip raw_payload
  -- through JSON.stringify and treat it as the same bytes.
  raw_payload           JSONB
);


-- ============================================================
--  INDEXES
-- ============================================================

-- Per-account chronological lookup ("show me what happened on this
-- LinkedIn account in the last hour"). Used by debug tooling and the
-- account-health surface in V3 §9.4.
CREATE INDEX IF NOT EXISTS idx_provider_event_log_account_recent
  ON public.provider_event_log(account_id, received_at DESC)
  WHERE account_id IS NOT NULL;

-- Channel + event-type chronological lookup ("show me all LinkedIn
-- relation.accepted events today"). Used by metrics dashboards.
CREATE INDEX IF NOT EXISTS idx_provider_event_log_channel_event
  ON public.provider_event_log(channel, event_type, received_at DESC);

-- Failure triage — "what events failed in the last 24h?". Partial index
-- keeps it cheap when the table grows.
CREATE INDEX IF NOT EXISTS idx_provider_event_log_failures
  ON public.provider_event_log(processing_status, received_at DESC)
  WHERE processing_status IN ('failed', 'duplicate');

-- Org-scope filter for admin views ("everything in this org").
CREATE INDEX IF NOT EXISTS idx_provider_event_log_org_recent
  ON public.provider_event_log(organization_id, received_at DESC)
  WHERE organization_id IS NOT NULL;


-- ============================================================
--  RLS — same shape as linkedin_accounts and linkedin_action_log
-- ============================================================

ALTER TABLE public.provider_event_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS provider_event_log_org_select ON public.provider_event_log;

-- SELECT — org members see their org's events. INSERT/UPDATE/DELETE
-- intentionally service-role only: the table is BFF-managed and
-- append-only. Users do not write.
CREATE POLICY provider_event_log_org_select
  ON public.provider_event_log
  FOR SELECT
  TO authenticated
  USING (organization_id = (auth.jwt() ->> 'org_id'));


-- ============================================================
--  COMMENTS — surface design intent in pg_dump and Studio
-- ============================================================

COMMENT ON TABLE public.provider_event_log IS
  'Append-only ingress ledger for every provider webhook payload. Forensic record and dedup anchor; survives account disconnects (no cascading FKs). V3 §6.2.';

COMMENT ON COLUMN public.provider_event_log.dedup_key IS
  'Unique key for deduplication. Format: "<provider>:<external_event_id>" when an external ID is present; otherwise a stable hash of (provider, account_id, occurred_at, body) so retries still dedup safely.';

COMMENT ON COLUMN public.provider_event_log.account_id IS
  'Provider-side account identifier (e.g. Unipile account_id). TEXT, not a FK. Denormalized so disconnect/cascade of linkedin_accounts cannot delete this audit row.';

COMMENT ON COLUMN public.provider_event_log.channel IS
  'Sellton-normalized channel. Set at ingress by the normalizer reading provider-specific fields. Webhook handlers MUST gate business logic on this column, never on the route name (V3 §8.5).';

COMMENT ON COLUMN public.provider_event_log.processing_status IS
  'Pipeline lifecycle: received → (ignored | processed | failed | duplicate). "duplicate" specifically means the dedup_key UNIQUE constraint was hit at insert; the row is the survivor, the duplicate was rejected.';

COMMENT ON COLUMN public.provider_event_log.raw_payload IS
  'Full provider body as JSONB. NEVER use JSON.stringify(raw_payload) for HMAC verification — auth must run against the original request bytes before any parse.';


-- ============================================================
--  PostgREST schema-cache reload
-- ============================================================
NOTIFY pgrst, 'reload schema';
