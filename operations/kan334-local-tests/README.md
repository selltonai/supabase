# KAN-334 local function test (migrations 400 and 401)

A throwaway check that 400/401 apply and that the three functions do what the plan says, before stage.
It is not part of the deploy: the workflow only runs files listed in `deploy-manifest.txt`.

Never point it at stage or production: it inserts and deletes rows.

## Run

```bash
docker run -d --name kan334-pg -e POSTGRES_PASSWORD=postgres public.ecr.aws/supabase/postgres:15.8.1.100
P="docker exec -i -e PGPASSWORD=postgres kan334-pg psql -h localhost -U supabase_admin -d postgres -X -q"
cd migrations
$P < full_schema.sql
for d in release_1.1.0 release_1.1.1 release_1.1.2 release_1.2.0 release_1.3.0 release_1.4.0 next-release; do
  for f in $(ls $d/*.sql | sort -V); do $P < $f; done   # older files print errors on the old snapshot; expected
done
$P < ../operations/kan334-local-tests/local_schema_fixups.sql
$P < ../operations/kan334-local-tests/kan334_functions_test.sql   # ends with: ALL KAN-334 FUNCTION CHECKS PASSED
docker rm -f kan334-pg
```

The loop applies 400 and 401 with the rest. To check that they apply as the runner applies them, run
each one with `-v ON_ERROR_STOP=1 --single-transaction` on a database loaded without them.

## What it checks

- Delete: 251 companies (250 owned by the list plus 1 existing company matched at import) go in 3 batches of 100, then the list's people with no company in a fourth; a fifth returns 0. People who also belong to a company outside the list stay, with that link. Another organization's rows are never touched. Journeys and open sequence actions of deleted people are cancelled (executed ones kept), their draft replies rejected, their open tasks and the companies' pending reviews cancelled with a reason, deals and campaign links go with the cascade.
- Preview: the counts for the dialog.
- Move: success into a paused campaign, and every refusal code (`already_moved`, `in_other_campaign`, `target_not_allowed`, `same_campaign`, `not_found` for another organization, `declined_in_target`, `company_busy`, `source_not_pending`); a review already pending in the target is withdrawn from the source without rescoring; a refusal writes nothing.
- Grants: anon and authenticated cannot execute the functions or read the job table; service_role can.
- One open delete job per list.

## Races (run by hand, two sessions)

Result on 2026-10-14:
- two moves of one review at the same time: the second waits for the first and returns `already_moved`; one target link
- a move holding its locks while an approval runs `UPDATE tasks … WHERE status = 'pending'` and `UPDATE campaign_companies … WHERE status = 'pending'`: both update 0 rows after the move commits (the approval route answers 409)

What this cannot show: timings against production-sized data and the production statement timeout. That is T0 on stage.
