# Phone invoice audit

Run the read-only SQL from this repository's `supabase` directory with the
campaign UUID. The Hetzner host and SSH key follow the migration runbook;
choose `supabase-db` for production or `supabase-stage-db` for stage:

```bash
ssh -F /dev/null -i /home/systempro/.ssh/hetzner-api \
  -o BatchMode=yes -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile=operations/hetzner-migrations/known_hosts \
  root@46.224.151.84 \
  "docker exec -i supabase-db psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres -v campaign_id='<campaign-uuid>'" \
  < operations/phone-invoice-audit/audit.sql
```

The contact count shows how many campaign contacts currently have a phone. It
does not prove those numbers came from Airscale. The usage result separates
successful Airscale lookups from telemetry-only failed attempts and shows their
stored customer cost and invoice link. Legacy paid invoices can have null
`usage.invoice_id`; `paid_period_unlinked` means the lookup occurred within a
paid invoice period and must not be treated as an unpaid charge. Compare usage
with the invoice line-item result. Do not infer a charge from the contact count
or change a paid invoice without reconciling Airscale success records and any
amount already charged under Contact enrichment.

Application dependencies: `selltonai-modal` writes `usage`; `selltonai` reads
stored invoice line items. The audit has no application-code dependency.

## IGA production findings, September 25, 2026

- September 7–14 invoice `c32c073f-00a3-4585-b815-6dd3bc7f511b` is paid for
  $82.70. Its usage subtotal is $63.20, matching usage in that exact period.
- The period contains 60 distinct successful Airscale phone finder rows at
  $0.60 each, totaling $36. They were recorded under
  `metadata.service=company_contact_service` and included in the $40.0905
  Contact enrichment line. Their `invoice_id` values are null because the
  paid invoice has legacy link state; do not charge them again.
- September 14–21 paid invoice has zero Airscale phone finder rows in its
  period, so its $0 Phones display is correct for recorded lookup usage.
- Production currently has 75 contacts with phone values in IGA's workspace.
  A phone value alone does not establish a billable Airscale lookup.
- Of those, 35 have no matching Airscale usage row. All 35 were created at the
  same September 23 timestamp; 33 have not changed since insertion, and 33 are
  not linked to a campaign. This is consistent with a bulk import. It is not
  evidence of additional billable lookups, so no extra charge was made.
- Stage has no IGA workspace. Across stage, 35 Airscale phone rows ($21) use
  `company_contact_service`, while 15 ($9) use `phone_discovery_service`.

`iga-2026-09-07-relabel.sql` is the invoice-specific correction for the
category shown in SelltonAI for the paid September 7–14 invoice.
It changes `billing_invoices.line_items` only, splitting $36 to Phone discovery
and leaving Contact enrichment at $4.0905. It keeps subtotal, total, Stripe
invoice, and usage rows unchanged. Its identity, usage, line-item, and amount
guards abort if live data has changed. The script passed once in a disposable
PostgreSQL 15 fixture; a second application correctly failed. It was applied
to production on September 25, 2026 after a verified full migration backup and
a fresh `billing_invoices` backup at
`/opt/sellton/backups/database-migrations/production/iga-phone-invoices-20260925T093713Z.dump`.
Post-change read-only checks confirmed the $36.00 Phones line, $4.0905 Contact
enrichment line, unchanged $63.20 subtotal/$82.70 total, unchanged paid/Stripe
state, and unchanged 60 Airscale usage rows. Do not run the relabel script again.
