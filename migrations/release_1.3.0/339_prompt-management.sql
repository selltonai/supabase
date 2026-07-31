-- 339 — Prompt management for Modal Jinja templates.
--
-- Why: prompt text currently lives in selltonai-modal template files. Operators
-- need a backoffice-managed master prompt catalog that applies to every
-- workspace/campaign, with optional per-workspace overrides when support needs
-- to tune behavior without forking code.
--
-- Model:
--   • prompts — global master templates, keyed by template_path. These are
--     independent of workspaces and are the default for all campaigns.
--   • org_prompt_overrides — optional active replacement content for a single
--     organization + prompt. Modal resolves override -> master -> file fallback.
--   • prompt_revisions — lightweight immutable snapshots for rollback/audit UI.
--
-- Affected projects:
--   - backoffice: CRUD UI for master prompts and org overrides.
--   - selltonai-modal: DB-backed Jinja prompt loader with file fallback.
--
-- Deploy:
--   1. Apply this migration.
--   2. Deploy backoffice + Modal code.
--   3. Run the Modal prompt sync script to seed masters from existing files.
--
-- Additive + non-breaking. Safe to deploy before app code; Modal falls back to
-- file templates if these tables or rows are not present.

CREATE TABLE IF NOT EXISTS public.prompts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL,
  template_path text NOT NULL,
  title text NOT NULL,
  category text NOT NULL DEFAULT 'general',
  description text,
  template_engine text NOT NULL DEFAULT 'jinja2' CHECK (template_engine IN ('jinja2', 'plain_text')),
  content text NOT NULL,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('draft', 'active', 'archived')),
  version text NOT NULL DEFAULT '1',
  source_project text NOT NULL DEFAULT 'selltonai-modal',
  source_checksum text,
  variables jsonb NOT NULL DEFAULT '[]'::jsonb,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_by text,
  updated_by text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT prompts_slug_format CHECK (slug = lower(slug) AND slug ~ '^[a-z0-9][a-z0-9._/-]*$')
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_prompts_slug
  ON public.prompts(slug);
CREATE UNIQUE INDEX IF NOT EXISTS uq_prompts_template_path
  ON public.prompts(template_path);
CREATE INDEX IF NOT EXISTS idx_prompts_category_status
  ON public.prompts(category, status, updated_at DESC);

CREATE TABLE IF NOT EXISTS public.org_prompt_overrides (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  prompt_id uuid NOT NULL REFERENCES public.prompts(id) ON DELETE CASCADE,
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  content text NOT NULL,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('draft', 'active', 'archived')),
  version text NOT NULL DEFAULT '1',
  notes text,
  created_by text,
  updated_by text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_org_prompt_overrides_prompt_org
  ON public.org_prompt_overrides(prompt_id, organization_id);
CREATE INDEX IF NOT EXISTS idx_org_prompt_overrides_org_status
  ON public.org_prompt_overrides(organization_id, status, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_org_prompt_overrides_prompt_status
  ON public.org_prompt_overrides(prompt_id, status, updated_at DESC);

CREATE TABLE IF NOT EXISTS public.prompt_revisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  prompt_id uuid NOT NULL REFERENCES public.prompts(id) ON DELETE CASCADE,
  org_prompt_override_id uuid REFERENCES public.org_prompt_overrides(id) ON DELETE CASCADE,
  organization_id text REFERENCES public.organization(id) ON DELETE CASCADE,
  scope text NOT NULL CHECK (scope IN ('master', 'organization')),
  revision_number integer NOT NULL DEFAULT 1,
  content text NOT NULL,
  status text NOT NULL,
  version text,
  changed_by text,
  change_reason text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_prompt_revisions_prompt_time
  ON public.prompt_revisions(prompt_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_prompt_revisions_org_time
  ON public.prompt_revisions(organization_id, created_at DESC)
  WHERE organization_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.update_prompt_management_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS prompts_updated_at ON public.prompts;
CREATE TRIGGER prompts_updated_at
  BEFORE UPDATE ON public.prompts
  FOR EACH ROW
  EXECUTE FUNCTION public.update_prompt_management_updated_at();

DROP TRIGGER IF EXISTS org_prompt_overrides_updated_at ON public.org_prompt_overrides;
CREATE TRIGGER org_prompt_overrides_updated_at
  BEFORE UPDATE ON public.org_prompt_overrides
  FOR EACH ROW
  EXECUTE FUNCTION public.update_prompt_management_updated_at();

ALTER TABLE public.prompts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.org_prompt_overrides ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prompt_revisions ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.prompts IS
  'Global master prompt templates used by selltonai-modal. Independent of workspaces; Modal resolves active org override, then active master, then file fallback.';
COMMENT ON TABLE public.org_prompt_overrides IS
  'Per-workspace prompt override content. One row per prompt + organization; only active rows are used by Modal.';
COMMENT ON TABLE public.prompt_revisions IS
  'Immutable snapshots of master prompt and organization override edits for backoffice rollback/audit UI.';
COMMENT ON COLUMN public.prompts.template_path IS
  'Path relative to sellton_api/services/templates, e.g. email_generation/system_prompt_initial_v5.0.0.jinja.';

-- Verify:
--   select table_name from information_schema.tables
--   where table_schema = 'public'
--     and table_name in ('prompts','org_prompt_overrides','prompt_revisions')
--   order by table_name;
