# Billing invoice-link recovery

This release fixes both the invoice-link timeout and the false monthly cap total.
It does not require changing customer limits or creating replacement Stripe invoices.

## Verify and deploy

1. Run `tests/run-billing-link-recovery.sh` from this repository. It uses only a disposable local PostgreSQL container.
2. Run the billing-focused suite in `selltonai-modal`, including invoice linkage tests.
3. Review and commit migration 370 on the production `main` branch. The migration runner requires committed source at HEAD; do not bypass that guard.
4. Plan/apply the explicit migration with `operations/hetzner-migrations/migrate.sh`. The normal production command includes `--confirm-production`; the runner takes and validates a full rollback backup. The migration is also included in the deployment manifest. Verify `pending=0` afterward.
5. Deploy the reviewed `selltonai-modal/production` release to Modal `main` using `devops/deploy.prod`. No frontend or Backoffice deployment is required.
6. Verify live hashes/schema and call `BillingService.check_spend_limit(org_id)` followed by `sync_spend_limit_dispatch_state(org_id, spend_data=...)` in the normal production runtime. Do not call invoice generation/payment APIs as a verification step. For WeDo, once a successful calculation confirms it is below the cap, clear the obsolete `billing_customers.spend_limit_paused_at` marker; clear `spend_warning_sent_at` as well if the corrected percent is below 80, so the next legitimate warning/pause can notify normally. This normal synchronization clears only a spend-limit suspension when appropriate, preserving billing/manual blocks.

## Monthly accounting

The cap now counts billable usage occurring within `[UTC month start, now)`, regardless of whether invoice links exist. Add infrastructure/user fees already invoiced in the month and pending fees for the current week. Fees retain the existing invoice-period-end attribution. The exact-period RPC also fixes the old daily-view inclusion of the next day at weekly boundaries.

For the September 14 WeDo snapshot: `$180.01 usage + $24 invoiced fees + $12 pending fees = $216.01`. The earlier `$216.97` reconstruction preserved invoice-month usage attribution, including $0.96 from August. Future usage changes this snapshot.

## New invoice recovery

Weekly invoices persist `usage_link_state=pending` before linkage. Bill-now invoices persist `awaiting_payment` and are eligible only when paid. Each batch updates at most 250 unlinked rows with the same org and exact half-open invoice period. Completion sets `linked`; a timeout leaves recoverable state. The hourly cron processes up to 20 invoices, oldest attempted first with never-attempted first and at most 20 batches per invoice per pass, without touching Stripe. New overlapping invoices are blocked until unresolved linkage/payment is reconciled. Legacy invoices default to `legacy` and are never automatically swept.

## Legacy repair

Run `audit.sql` read-only with an explicit `org_id`. Validate invoice line items, status, exact periods, and existing row ownership. Only then run `repair-verified-invoice.sql` with explicit `org_id` and `invoice_id`, after a fresh backup. It locks and validates the invoice/candidate rows, rejects subtotal mismatches, and changes only invoice links and recovery metadata. It does not change amounts, charges, or suspension. Its transaction rolls back on any failure.

WeDo's invoice ending September 14 reconciled to $97.12 in the original audit. The invoice ending September 7 had $83.85 invoiced usage versus $83.73 in its exact period: the old inclusive-date query included usage from the next day. That discrepancy requires manual line-item reconciliation; do not force the repair or assign one usage row to two invoices. Correct monthly cap accounting is independent of this historical repair.

The legacy procedure is intentionally conservative: onboarding exclusions, late historical inserts, overlapping invoices, or missing/old-format line items can cause a mismatch. Resolve those explicitly; do not disable its validation.

## Rollback

Keep migration 370 installed if rolling Modal back: its default `legacy` preserves old-writer compatibility, and bypassing analytics for invoice-only updates remains safe. Rolling back the backend restores the previous incorrect cap calculation, so first assess falsely suspended customers. Do not delete invoice links as a rollback. Historical invoice amounts and Stripe state are never changed by this release.

## Verification limits

Local tests prove tenant isolation, exact boundaries, partial-batch retry, paid-state preservation, public-role RPC denial, and unchanged projection data/tuples on invoice-only writes. They do not reconcile historical Stripe payments. Production rollout, live performance checks, and legacy repairs must be recorded separately.
