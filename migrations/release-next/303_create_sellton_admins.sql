-- ============================================================
-- Onboarding/admin foundation: sellton_admins
-- Projects:
--   - selltonai: protects /admin routes and internal admin API routes
-- App changes required together:
--   - Add src/lib/sellton-admin-check.ts and admin layout protection.
-- Notes:
--   - No bootstrap user is inserted here because the founder Clerk user_id is environment-specific.
--     Insert it manually after deploy:
--       INSERT INTO public.sellton_admins (clerk_user_id, notes) VALUES ('user_xxx', 'founder bootstrap');
-- ============================================================

CREATE TABLE IF NOT EXISTS public.sellton_admins (
  clerk_user_id TEXT PRIMARY KEY,
  added_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  added_by TEXT,
  notes TEXT,
  scope TEXT[] NOT NULL DEFAULT ARRAY['all']::TEXT[]
);

COMMENT ON TABLE public.sellton_admins IS 'Platform-level Sellton admin users. Sellton staff are not added to client Clerk organizations.';
COMMENT ON COLUMN public.sellton_admins.scope IS 'Permission scope placeholder for future restricted admin roles.';
