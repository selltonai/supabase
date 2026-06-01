# next-release — LinkedIn integration migrations

**Source repo**: `selltonai`
**Source path**: `selltonai/linkedin-integration/schema/`
**Imported**: 2026-05-28
**Files**: 32 SQL migrations (renumbered 254-285)

## Why these migrations need to live here

The LinkedIn integration work shipped on a long-running feature branch in
the `selltonai` repo. Its migration files were authored with the
numbering range 240-272 against a snapshot of the supabase schema at the
time the branch started.

In parallel, the supabase repo's main branch added unrelated migrations
in the **same number range** (230-253) for CRM, billing, notifications,
AI Ark enrollment, phantom-contact cleanup, etc. — see
`migrations/release_1.0.5/` through `migrations/release_1.1.2/`.

The number ranges collide. The linkedin work was never moved into the
supabase repo because doing so required deciding how to handle the
overlap. This MANIFEST resolves it: **the linkedin migrations are
renumbered to 254-285** (starting one above the latest existing
migration `253_add_crm_lists_column_mapping.sql` in
`release_1.1.2/`) and dropped into `next-release/`.

**File content is byte-identical** to the selltonai authoritative source.
Only the filename number changed.

## Old → new number mapping

| Original (selltonai) | New (next-release) | Description |
|---|---|---|
| 240 | 254 | create_linkedin_accounts |
| 243 | 255 | create_linkedin_action_log |
| 244 | 256 | alter_linkedin_accounts_caps |
| 245 | 257 | create_linkedin_messages |
| 246 | 258 | create_provider_event_log |
| 247 | 259 | create_linkedin_threads |
| 248 | 260 | create_campaign_contacts |
| 249 | 261 | create_campaign_sequence_actions |
| 250 | 262 | add_campaigns_channel_strategy |
| 251 | 263 | add_sequence_action_lease_columns |
| 252 | 264 | create_cron_config_table |
| 252b | 265 | schedule_sequence_claim_cron |
| 253 | 266 | create_provider_event_log_retention |
| 254 | 267 | fix_claim_rpc_null_scheduled_at |
| 255 | 268 | add_campaigns_linkedin_autopilot |
| 256 | 269 | add_linkedin_action_log_campaign_id |
| 257 | 270 | schedule_linkedin_auto_enroll_cron |
| 258 | 271 | add_linkedin_action_log_dispatch_columns |
| 259 | 272 | add_linkedin_enrichment_columns |
| 260 | 273 | contact_dedup_indexes |
| 261 | 274 | inbox_scope_and_avatar |
| 262 | 275 | add_campaigns_linkedin_account_id |
| 263 | 276 | add_linkedin_accounts_subscription_type |
| 264 | 277 | add_linkedin_action_log_idempotency |
| 265 | 278 | add_linkedin_threads_fk_constraints |
| 266 | 279 | add_campaign_pain_extraction_columns |
| 267 | 280 | add_campaign_goal_column |
| 268 | 281 | sprint5_inbound_foundation |
| 269 | 282 | sprint5_phasec_reply_drafts |
| 270 | 283 | sprint5_autopilot_reply_gate |
| 271 | 284 | reply_drafts_drafter_user_id |
| 272 | 285 | organization_files_user_id |

**32 files total. Apply in numeric order (254 → 285).**

> **Note on file content**: Each migration's internal comment header
> still references the ORIGINAL number (e.g. file `254_create_linkedin_accounts.sql`
> contains a comment `Migration: 240_create_linkedin_accounts`). These
> comments document provenance — they are not executable references.
> Inter-migration `Depends:` notes also use the original numbers. Refer
> to this table to translate. We intentionally did NOT rewrite those
> comments to keep the renumbering operation byte-identical to the
> authoritative source.

## Dependency order (apply this order is correct by filename sort)

These migrations have **internal cross-references** in comment headers.
Applying in numeric filename order (254→285) satisfies all dependencies.
Key dependencies:

- 254 (linkedin_accounts) is the foundation table
- 255-256, 257, 263, 275-278 all depend on 254
- 264-265 set up cron tables + scheduled jobs
- 281-283 (Sprint 5) depend on 257, 258, 259 being present
- 284-285 are user_id parity migrations (depend on parent tables existing)

## Which projects depend on these migrations

Per `AGENTS.md` convention, every migration should state cross-project
impact. Here is the consolidated impact assessment:

| Migration | selltonai-modal | selltonai (BFF) | backoffice | gmail-api |
|---|---|---|---|---|
| 254 (linkedin_accounts) | reads/writes | reads/writes | reads | — |
| 255 (linkedin_action_log) | writes | reads | reads | — |
| 256 (linkedin_accounts caps) | reads | — | — | — |
| 257 (linkedin_messages) | reads/writes | reads/writes | reads | — |
| 258 (provider_event_log) | writes | — | reads | — |
| 259 (linkedin_threads) | reads/writes | reads/writes | reads | — |
| 260 (campaign_contacts) | reads/writes | reads | reads | — |
| 261 (campaign_sequence_actions) | reads/writes | reads | reads | — |
| 262 (campaigns channel_strategy) | reads/writes | reads/writes | reads | — |
| 263 (sequence_action_lease_columns) | reads/writes | — | reads | — |
| 264 (cron_config_table) | reads/writes | — | reads | — |
| 265 (sequence_claim_cron schedule) | infra | — | — | — |
| 266 (provider_event_log retention) | infra | — | — | — |
| 267 (fix claim_rpc) | reads/writes | — | — | — |
| 268 (campaigns linkedin_autopilot) | reads/writes | reads/writes | reads | — |
| 269-272 (action_log dispatch + enrichment) | reads/writes | reads | reads | — |
| 273 (contact_dedup_indexes) | reads (perf) | — | reads | — |
| 274 (inbox scope + avatar) | reads/writes | reads/writes | reads | — |
| 275-277 (campaigns/accounts cols) | reads/writes | reads | — | — |
| 278 (linkedin_threads FK) | infra | — | — | — |
| 279 (campaign_pain_extraction cols) | writes | reads | reads | — |
| 280 (campaign_goal column) | writes | reads | reads | — |
| 281 (sprint5 inbound foundation) | reads/writes | reads/writes | reads | — |
| 282 (reply_drafts table) | writes | reads | reads | — |
| 283 (autopilot reply gate) | reads/writes | reads/writes | reads | — |
| 284 (reply_drafts.drafter_user_id) | writes | reads | reads | — |
| 285 (organization_files.user_id) | writes | reads/writes | reads | — |

**Code that must deploy together with these migrations:**
- `selltonai-modal` stage commits 240-272 (Sprint 5, LinkedIn V3 P1+, KB grounding)
- `selltonai` stage commits for LinkedIn UI + reply-handler webhooks
- `backoffice` reads tables read-only — no code change required for these migrations specifically

## Apply instructions

### Option A — via supabase CLI (recommended)

```bash
cd "/path/to/supabase"
supabase db push   # applies any pending migrations from migrations/next-release/
```

### Option B — manual psql

```bash
cd "/path/to/supabase/migrations/next-release"
for f in $(ls *.sql | sort); do
  echo "Applying $f..."
  psql "$DATABASE_URL" -f "$f" || { echo "FAILED: $f"; exit 1; }
done
```

### Post-apply verification

After applying, run from selltonai-modal:

```bash
psql "$DATABASE_URL" -f "/path/to/selltonai-modal/sellton_api/scripts/SCHEMA_VERIFICATION.sql"
```

Expected: zero rows from any of the assertion queries.

## Release graduation

When ready to cut a new release (e.g. `release_1.2.0`):

1. `mv migrations/next-release migrations/release_1.2.0_linkedin`
2. Update `migrations/release_1.2.0_linkedin/MANIFEST.md` (this file) to reflect the new release name
3. Create a new empty `migrations/next-release/` for the next batch
4. Tag the supabase repo with `release_1.2.0`
5. Reference the release in the deploy runbook + `BUILD_LOG.md`

## Provenance: source SHAs

These migrations represent the consolidated LinkedIn integration work
across the following selltonai stage commits (most recent first):

- `1641601` chore(schema): queue migrations 271 + 272 (user_id parity)
- `592802f` feat(kb-userid): capture user_id on org file uploads
- Sprint 5 commits (Phase D + autopilot reply gate)
- Tier 1.4 LinkedinSignalsService work
- LinkedIn V3 P1-2b through P1-2g

The selltonai-side authoritative folder
`selltonai/linkedin-integration/schema/` should be considered a working
mirror — after these migrations are graduated into a release folder,
that selltonai-side folder can be archived or deleted in a follow-up PR.

## Companion docs

- `selltonai/linkedin-integration/schema/APPLY_PHASE_G.md` — runbook
  notes from the original linkedin-integration branch
- `Ground Truth/GO_LIVE_2026-05-29.md` — production launch checklist
  (these migrations are referenced under "Database / migrations" step)
- `Ground Truth/BILLING_AND_USAGE_TRACKING_STATE_2026-05-28.md` —
  references migration 285 (`organization_files.user_id`) for per-user
  attribution work

## Why renumber instead of preserve original numbers

Considered alternative: place files in `next-release/` keeping the
original 240-272 numbers, and document the collision separately. Rejected
because:

1. Supabase's `db push` applies migrations in filename-sort order across
   the entire `migrations/` tree. Keeping 240-272 names would cause
   `migrations/release_1.1.0/240_add_crm_tracking_columns.sql` and
   `migrations/next-release/240_create_linkedin_accounts.sql` to attempt
   to apply at the same logical step — Supabase's history table would
   likely reject the second.
2. The repo convention (visible from release_1.0.x → 1.1.2) is
   strictly-monotonic global numbering. Diverging from that convention
   would set bad precedent.
3. Renumbering is the minimal possible change — file CONTENT stays
   byte-identical, only the filename number is shifted by 14.
