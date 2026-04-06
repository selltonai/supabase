# Sellton Workspace Summary

## What This Repository Is

Sellton is organized as a multi-project workspace. The main user-facing app is `selltonai`, supported by several service repositories and operational tools in sibling directories.

## Projects

- `selltonai`: Next.js 15 frontend and internal API routes
- `backoffice`: AdonisJS back office
- `sellton-onboard`: Vite onboarding UI
- `selltonai-modal`: Python AI backend with provider orchestration
- `selltonai-vector-api`: OCR, document screening, embeddings, Pinecone search
- `selltonai-gmail-api`: Gmail integration and sync service
- `selltonai-crawler`: crawling, enrichment, scoring, search
- `localserver`: Docker-based local integration environment
- `supabase`: shared local Supabase config and migrations

## Working Rule

Always identify the target project first. Run commands from that project directory, then read the nearest `AGENTS.md`.

## Important Paths

- Workspace guide: `/home/systempro/source/repo/systempro/sellton/AGENTS.md`
- Claude memory: `/home/systempro/source/repo/systempro/sellton/CLAUDE.md`
- Persistent project memory: `/home/systempro/source/repo/systempro/sellton/task/persistent context - project memory.md`

## Multi-Agent Guidance

- Split ownership by directory, not vague role labels.
- Use `task/active/` for task briefs and `task/handoffs/` for continuation notes.
- Document cross-project impact whenever contracts, migrations, webhooks, or queues change.
