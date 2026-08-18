# CRM rollout gate (migration 360) — how to enable CRM flags for an org

Migration 360 installs a guard on `organization_settings`: CRM automation cannot
be switched on without the CRM pipeline flag, and neither can be switched on
until that organization's deals have been reconciled. It enables nothing by
itself.

**Consequence to know before applying it:** after 360 is live, the deal-settings
screen can no longer turn CRM automation on by itself — the upsert hits the
guard. The app now reports that clearly (KAN-275: a 409 naming the failed
precondition instead of a blank 500), but the enable itself is a service-role
operation and lives here.

Deploy order is therefore: **BFF fix first, then this migration.** Applying the
gate before the app can explain it reproduces the blank-500 experience.

## Enabling an organization (service role, in order)

```sql
-- 1. Is this org ready? Read-only, safe to run any time.
select public.crm_deal_reconciliation_readiness('<organization_id>');

-- 2. Dry run the reconciliation and read what it WOULD change.
select public.reconcile_crm_deals_for_rollout('<organization_id>', true);

-- 3. Apply it for real.
select public.reconcile_crm_deals_for_rollout('<organization_id>', false);

-- 4. Enable. Second argument also switches CRM automation on; leave it false
--    to enable only the pipeline flag.
select public.enable_crm_pipeline_after_reconciliation('<organization_id>', true);
```

Step 4 re-checks readiness and refuses with `23514` plus the readiness JSON in
DETAIL if anything regressed between steps 3 and 4, so it is safe to re-run.

## Notes

- Nothing in the application writes `crm_pipeline_enabled`. Today this sequence
  is the only way it gets set. Whether that flag deserves an admin surface is a
  product decision, not a gap to patch silently.
- All four functions are `REVOKE`d from `anon` and `authenticated` and granted
  only to `service_role`.
- Reconciliation runs are silent by design — they emit no notifications and
  create no tasks.
