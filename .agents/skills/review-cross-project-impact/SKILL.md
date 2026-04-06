# review-cross-project-impact

Use this skill before merging or handing off any change that may affect more than one project.

## Check

- request payload fields
- response payload fields
- enum values
- auth requirements
- DB schema and migrations
- cron, queue, or webhook behavior
- environment variables

## Workflow

1. List the owning project.
2. List direct consumers and producers.
3. Confirm whether contracts changed.
4. Record affected paths and verification commands.
5. Add a short impact note to the handoff or task brief.

## Output

Produce a compact summary:

- owning project
- affected projects
- contract impact
- verification performed
- residual risk
