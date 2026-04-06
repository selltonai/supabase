---
description: Sellton workspace routing and multi-project guardrails
globs:
alwaysApply: true
---
Use `/home/systempro/source/repo/systempro/sellton/AGENTS.md` as the workspace entrypoint.

This repository is multi-project:

- `selltonai`
- `backoffice`
- `sellton-onboard`
- `selltonai-modal`
- `selltonai-vector-api`
- `selltonai-gmail-api`
- `selltonai-crawler`
- `localserver`
- `supabase`

Choose the target project first, then read that project's `AGENTS.md`.

Run commands from the relevant project directory. Do not assume that patterns, env vars, tests, or architecture from one project apply to another.

For cross-project work, split ownership by directory and leave a handoff note if another agent will continue.
