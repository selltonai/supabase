# debug-next-route

Use this skill when a task involves a `selltonai` Next.js page, server action, or route handler that appears broken or inconsistent with a backend contract.

## Scope

- `selltonai/src/app/**`
- `selltonai/src/components/**`
- `selltonai/src/services/**`
- related backend contract files only if explicitly required

## Workflow

1. Read `selltonai/AGENTS.md`.
2. Identify whether the failing flow is page rendering, route handler behavior, auth, or upstream contract mismatch.
3. Trace the request path from UI trigger to route handler to downstream service call.
4. Check shared types, payload shaping, and response assumptions.
5. Add or update a regression test when the bug is reproducible in code.
6. Document any backend contract dependency in the handoff.

## Verification

- `cd selltonai && npm run test`
- `cd selltonai && npm run lint`

## Escalation

If the issue is caused by a service contract from `selltonai-modal`, `selltonai-vector-api`, or `selltonai-gmail-api`, split ownership and hand off the backend side instead of patching around it in the frontend.
