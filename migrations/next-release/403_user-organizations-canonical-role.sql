-- ============================================================
-- Migration: 403_user-organizations-canonical-role (next-release; the same bytes on main and stage)
-- Date:      2026-10-19
-- Purpose:   KAN-309 / KAN-283 P0a. user_organizations.role gets ONE spelling, Clerk's own:
--            "org:admin", "org:member", "org:owner" (decision B2; the column default since 246 is 'org:member').
-- Why:       The Clerk webhook (selltonai src/app/api/clerk/route.ts) stripped the "org:" prefix, so the table
--            holds "admin" next to "org:admin" (2026-10-15: prod org:member 63, org:admin 17, admin 10; stage
--            member 17, org:member 19, org:admin 1, admin 5). A reader comparing one spelling misses the other:
--            selltonai organization-settings/notifications answered 403 to the "admin" rows, and backoffice
--            (listOrgAdmins, the lifecycle-email admins, the Org 360 total) saw only "admin".
-- Readers:   Re-checked 2026-10-19. No SQL function, policy or trigger in this repo reads the role (only 246's
--            default and index). Modal ADMIN_ROLES = ["org:admin", "admin"] (production + stage) keeps working.
--            selltonai and backoffice readers accept every spelling from fix/kan309-roles-credentials and
--            fix/kan309-admin-role-spellings.
-- Order:     Deploy AFTER those two BFF/backoffice fixes are live on this line. Backoffice on master compares
--            role = 'admin' only: run this before it ships and lifecycle emails lose every admin recipient.
--            Until the BFF writer fix is live, the Clerk webhook keeps writing stripped spellings; re-running
--            this file's UPDATEs by hand later is safe.
-- Contract:  Data only, idempotent (a second run changes no row). (user_id, organization_id) is the primary key,
--            so there are no rows to merge. Unknown spellings are left as they are and reported by a NOTICE.
--            No CHECK constraint on purpose: a writer still stripping the prefix would fail its insert and drop
--            the membership mirror (plan §4).
-- Rollback:  Not needed: every reader accepts both spellings. rollback/403_user-organizations-canonical-role.rollback.sql
--            puts the stripped spelling back if asked (lossy: it cannot tell which rows were stripped before).
-- ============================================================

-- "admin" / "member" / "owner", any case or padding -> "org:<role>".
UPDATE public.user_organizations
SET role = 'org:' || lower(btrim(role))
WHERE role IS NOT NULL
  AND lower(btrim(role)) IN ('admin', 'member', 'owner');

-- Already prefixed but not in canonical form ("ORG:Admin", " org:member ").
UPDATE public.user_organizations
SET role = lower(btrim(role))
WHERE role IS NOT NULL
  AND lower(btrim(role)) IN ('org:admin', 'org:member', 'org:owner')
  AND role <> lower(btrim(role));

-- No role: the column default.
UPDATE public.user_organizations
SET role = 'org:member'
WHERE role IS NULL OR btrim(role) = '';

DO $$
DECLARE
  leftover integer;
BEGIN
  SELECT count(*) INTO leftover
  FROM public.user_organizations
  WHERE role NOT IN ('org:admin', 'org:member', 'org:owner');
  IF leftover > 0 THEN
    RAISE NOTICE '403: % user_organizations rows have a role outside org:admin/org:member/org:owner (left as is)', leftover;
  END IF;
END $$;

-- Verify (read-only):
-- SELECT role, count(*) FROM public.user_organizations GROUP BY role ORDER BY 2 DESC;
--   -- expect only org:admin, org:member, org:owner
-- SELECT migration_path, applied_at FROM sellton_migrations.applied_migrations
--   WHERE migration_path LIKE '%403_user-organizations-canonical-role%';   -- one row
