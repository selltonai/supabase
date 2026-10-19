-- KAN-322 FR-C8b: after the rollback the column and its constraint are gone, and the migration applies again.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'organization_settings' AND column_name = 'timezone') THEN
    RAISE EXCEPTION 'timezone still there after the rollback';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'organization_settings_timezone_shape') THEN
    RAISE EXCEPTION 'shape constraint still there after the rollback';
  END IF;
END $$;
