# CRM Deals reconciliation rollout

CRM contact projection remains active while both organization flags default to `false`. A pipeline rollout must be organization-scoped and follow three separate operations:

1. Call `crm_deal_reconciliation_readiness(organization_id)` or `reconcile_crm_deals_for_rollout(organization_id, false)` for a read-only preview.
2. Call `reconcile_crm_deals_for_rollout(organization_id, true)`. This runs the existing silent projection backfill, resolves failure-ledger rows only when current state proves them fixed, and returns a second readiness report.
3. Only when `ready_for_flag_enablement=true`, call `enable_crm_pipeline_after_reconciliation(organization_id, enable_automation)`.

The migration never enables a flag. Direct inserts or updates that turn on `crm_pipeline_enabled` or `crm_automation_enabled` run the same readiness check and fail with `23514` while deals are missing, lagging behind contact stages, tied to the wrong primary contact, duplicated, or represented by unresolved projection failures. Automation also requires the pipeline flag.

Readiness is scoped to one organization. It compares the highest active mapped contact stage per company with the authoritative open deal, verifies the deterministic primary contact, and reports all blocking counts. `CLOSED_WON` remains manual-only and is not introduced by reconciliation.

Service-role operator sequence:

```sql
SELECT public.reconcile_crm_deals_for_rollout('<organization-id>', FALSE);
SELECT public.reconcile_crm_deals_for_rollout('<organization-id>', TRUE);
SELECT public.enable_crm_pipeline_after_reconciliation('<organization-id>', FALSE);
```

The final `FALSE` keeps CRM automation disabled while enabling pipeline visibility/notifications. Automation should be enabled separately only after its task backlog and operational checks are approved.
