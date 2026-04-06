# Global Rules

- Do not deploy without explicit permission.
- Do not commit file changes to git without explicit permission.
- Treat this repository as a multi-project workspace, not a single application.
- Start with [`AGENTS.md`](/home/systempro/source/repo/systempro/sellton/AGENTS.md) and then use the nearest project-level `AGENTS.md`.
- Prefer project-local test commands and keep changes scoped to the owning project.

# Coding Style Rules

## Paradigm

- Write in a functional, declarative style where it fits the project.
- Prefer expressions and small composable functions over large procedural blocks.
- Avoid mutation when practical.

## Review Checklist

- Is the change scoped to the correct project?
- Does it change a shared contract?
- Are downstream consumers affected?
- Were the correct project-native tests run?
