# DB read/write scaling playbook — keeping queries fast as orgs grow

> Written 2026-06-16 off a concrete incident: `GET /api/tasks` timing out (Postgres `57014`,
> statement timeout) on the completed-tasks view for a data-heavy org. The fix is migration 329;
> this doc generalizes the lesson into a reusable playbook grounded in Sellton's actual code.

## The incident, briefly

The Tasks list orders the completed/cancelled/declined branch by `completed_at DESC, …` but had
**no index pairing `(organization_id, status)` with `completed_at`** — while the pending branch
*did* have its matching index (`idx_tasks_org_status_priority_created`). So pending stayed fast and
completed degraded to "fetch all matching rows → sort them" once an org had enough completed tasks,
blowing past the ~8s statement timeout. One index (migration 329) restores an index-ordered scan +
early `LIMIT`. The asymmetry (pending fast / completed slow, same SELECT and joins) is the proof the
index — not the payload — was the cause.

## The five anti-patterns to hunt for (all present in this codebase today)

1. **ORDER BY without a covering index.** *The* highest-leverage rule. For every hot list query,
   the index must be `(…equality-filter cols…, …ORDER BY cols in order…)`. Audit each endpoint's
   `ORDER BY` against the indexes in `full_schema.sql`. A filter-only index (e.g.
   `idx_tasks_org_type_status`) still forces a full sort if it doesn't carry the sort column.

2. **`SELECT *` on list endpoints.** `GET /api/tasks` non-slim select pulls every wide column
   (`metadata`, `pre_generated_copy`, `body`, `conversation_summary`, `generation_log` jsonb) for
   every row, then three embedded joins (`contacts`, `campaigns`, `companies`). Lists need ~10
   display fields; heavy columns belong only on the detail/review view. Even the existing `slim`
   select still carries the heavy text/jsonb — tighten list projections to display fields only.

3. **Over-fetch then filter in app memory.** `GET /api/tasks` scans up to **20,000 rows** in
   500-row chunks and applies `isVisibleOperationalTask` (contact `do_not_contact`, campaign
   `cancelled`/orphaned) in JS because those predicates live on joined tables. This is O(rows) and
   moves work + bandwidth to the Node function. Two ways out:
   - **Push the predicate to SQL** via `!inner` embeds + filters where the relation is mandatory.
   - **Denormalize a visibility flag** onto `tasks` (e.g. `is_hidden` maintained on write / by
     trigger when a campaign is cancelled or a contact goes DNC), so the list is one indexed scan
     `WHERE … AND is_hidden = false` + `LIMIT` — no scan-and-filter loop at all. (Same pattern the
     CRM `.in()` chunking fix used: do the work where the data lives, not in the app.)

4. **Offset/range pagination for deep pages.** `.range(rawFrom, rawTo)` with a growing offset
   re-walks every skipped row. Past the first page or two, switch to **keyset (cursor) pagination**:
   `WHERE (completed_at, id) < (:lastCompletedAt, :lastId) ORDER BY completed_at DESC, id DESC
   LIMIT n`. Constant cost per page regardless of depth; pairs perfectly with the migration-329
   index.

5. **Exact `COUNT` on big tables.** Exact counts scan the whole filtered set. Prefer a "hasMore"
   cursor (fetch `limit + 1`) or an estimated count (`pg_class.reltuples` / planner estimate) for
   "~N results". The tasks route already avoids `count: exact`, but it pays for it with the 20k-row
   scan in #3 — fixing #3 with keyset + `hasMore` removes both problems at once.

## Operational guardrails (not fixes — they bound the blast radius)

- **`statement_timeout` is a safety net, not a tuning knob.** Raising it hides slow queries until
  they get slower. The client `x-request-timeout` header does **not** change the Postgres timeout.
  Fix the query (index/projection/keyset); keep the timeout low enough to fail fast.
- **Use the Supabase transaction pooler** for serverless routes (short-lived connections); avoid
  long-held sessions in Vercel functions.
- **Keep the slow-query log.** `QueryOptimizer.measureQuery` already logs `>5s` — keep it, and add
  the org id + row count (as the CRM fix did) so a slow line is self-diagnosing. Periodically review
  `pg_stat_statements` for the top mean-time queries and back-fill indexes the same way as 329.
- **Build indexes `CONCURRENTLY`** on very large prod tables so an index addition never locks
  writes — but note the Supabase SQL editor wraps statements in a transaction, where CONCURRENTLY
  fails (`ERROR 25001`). For editor-applied migrations use plain `CREATE INDEX` (brief SHARE lock,
  blocks writes not reads — what migrations 327 and 329 do); for zero write-block run CONCURRENTLY
  via a direct `psql`/pooler connection instead.

## Triage order when a query is slow

1. `EXPLAIN (ANALYZE, BUFFERS)` it — look for `Seq Scan` on a big table or a `Sort` node feeding a
   `Limit`. A `Sort` under a `Limit` = missing ORDER-BY index (the 329 case).
2. Add/extend the composite index to `(equality cols, order cols)`; re-EXPLAIN — the `Sort` should
   become an `Index Scan` and rows-removed-by-filter should drop.
3. Narrow the projection (kill `SELECT *`), then push residual filters into SQL.
4. Only then consider keyset pagination / denormalized flags for the deep-scan endpoints.

## Concrete follow-ups for THIS repo (beyond migration 329)

- `GET /api/tasks`: replace the 20k-row scan-and-filter loop with keyset pagination + a
  SQL/denormalized visibility predicate; tighten the list projection off `SELECT *`.
- Audit the other high-traffic lists (campaigns, contacts, inbox/threads, dashboard stats) the same
  way: match each `ORDER BY` to a covering composite index; the contacts list already chunks `.in()`
  (see the 2026-06-16 CRM fix) — apply the same discipline to its sorts.
