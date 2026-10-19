-- KAN-309 / KAN-283 P0a: migration 403's contract. Run by tests/run-user-organizations-canonical-role-contract.sh
-- on a disposable database, after the migration has been applied twice (idempotency).
DO $$
DECLARE
  got jsonb;
  expected jsonb := jsonb_build_object(
    'u_admin', 'org:admin',
    'u_member', 'org:member',
    'u_owner', 'org:owner',
    'u_padded', 'org:admin',
    'u_upper', 'org:admin',
    'u_clerk_admin', 'org:admin',
    'u_clerk_member', 'org:member',
    'u_clerk_owner', 'org:owner',
    'u_null', 'org:member',
    'u_empty', 'org:member',
    -- Unknown spellings are left alone (the migration reports them with a NOTICE).
    'u_unknown', 'basic_member'
  );
BEGIN
  SELECT jsonb_object_agg(user_id, role) INTO got FROM public.user_organizations;
  IF got IS DISTINCT FROM expected THEN
    RAISE EXCEPTION 'roles after 403: % (expected %)', got, expected;
  END IF;
  IF (SELECT count(*) FROM public.user_organizations) <> 11 THEN
    RAISE EXCEPTION '403 added or removed membership rows';
  END IF;
END $$;

-- A second run (the runner re-plans; an operator may re-run it after the writer fix) changes no row.
DO $$
DECLARE
  changed integer;
BEGIN
  UPDATE public.user_organizations SET role = 'org:' || lower(btrim(role))
  WHERE role IS NOT NULL AND lower(btrim(role)) IN ('admin', 'member', 'owner');
  GET DIAGNOSTICS changed = ROW_COUNT;
  IF changed <> 0 THEN RAISE EXCEPTION 'the stripped-spelling UPDATE is not idempotent (% rows)', changed; END IF;
END $$;

-- The rollback strips only admin and owner rows and keeps org:member (the column default).
BEGIN;
\ir ../migrations/next-release/rollback/403_user-organizations-canonical-role.rollback.sql
DO $$
BEGIN
  IF (SELECT role FROM public.user_organizations WHERE user_id = 'u_clerk_admin') <> 'admin'
     OR (SELECT role FROM public.user_organizations WHERE user_id = 'u_clerk_owner') <> 'owner'
     OR (SELECT role FROM public.user_organizations WHERE user_id = 'u_member') <> 'org:member' THEN
    RAISE EXCEPTION 'the 403 rollback did not restore the stripped spelling';
  END IF;
END $$;
ROLLBACK;
SELECT '403 user_organizations canonical role contract passed' AS result;
