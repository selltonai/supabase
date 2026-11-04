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

## Quiet-deal tasks: migrations 415, 416, 417 (live on stage since 2026-11-02)

Plan of record: `PLAN_CRM_QUIET_DEALS_TASKS_2026_10_31.md` (sections 6, 11 and 12). The files are in `migrations/next-release/`.
Stage only; production has not received them.

| Migration | Merged in | What it does |
|---|---|---|
| `415_crm-deal-goal-and-note-clock.sql` | supabase #68 (9a90190) | Adds the nullable column `deals.goal` (check: at most 2000 characters). When set, it replaces the play's goal in CRM follow-ups and in the call note. NULL means the play goal. Also replaces `add_crm_deal_note` so that a deal note writes its activity row with `bumps_last_activity = FALSE`: a note no longer moves `deals.last_activity_at`. Calls, emails, LinkedIn messages and replies still do. Rollback: `rollback/415_crm-deal-goal-and-note-clock.rollback.sql`. |
| `416_crm-add-contact-task-type.sql` | supabase #69 (ce23b4f) | Adds the enum value `add_contact` to `public.task_type`, for the "Add a person" task. An enum value cannot be dropped, so there is no rollback. It is its own file because 417 uses the value and the value must be committed first. |
| `417_crm-add-contact-task-workflows.sql` | supabase #69 (ce23b4f) | `cancel_crm_deal_tasks_on_close` also cancels an open `add_contact` task when the deal closes (the body of `next-release/376` with one type added). `audit_crm_deal_task` still writes "Deal task completed" for an `add_contact` task but with `bumps_last_activity = FALSE`, so completing it does not move `last_activity_at` (the body of `release_1.3.0/352` with that one value changed). Rollback: `rollback/417_crm-add-contact-task-workflows.rollback.sql`; the enum value from 416 stays. |

How to check on stage (read-only):

- `SELECT id, name, goal FROM public.deals WHERE goal IS NOT NULL;`
- Task rows for the new type: `SELECT id, deal_id, status, metadata->>'closed_reason' FROM public.tasks WHERE task_type = 'add_contact';` A task closed by Modal has `closed_reason = 'contact_added'`.
- Deal activity rows: `SELECT activity_type, title, bumps_last_activity, metadata->>'reason' FROM public.deal_activities WHERE deal_id = '<deal>' ORDER BY created_at DESC;`

### Trap: never sync `main` into `stage`

`main` carries commit `5dfac28` ("prod fix"), which is on `main` only: `release_1.3.0/374_production-catch-up-usage-label-map.sql` and `release_1.3.0/375_production-catch-up-contact-canonical-pointer.sql`. File 374 runs `CREATE OR REPLACE FUNCTION public.analytics_usage_rollup` with the body from 249. The newer versions of that function (migrations 326, 345 and 396 each redefine it) live on stage. A merge of `main` into `stage` would apply 374 on stage and downgrade the function. Promote only `stage` into `main`. That direction is safe: `main` keeps both files and the manifest merge conflict is trivial.
