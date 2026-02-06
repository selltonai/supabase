-- Migration: Drop scheduled_date column from tasks table
-- Description: scheduled_date column is being removed. Meeting tasks will use metadata.meeting_details.scheduled_date instead.
-- Email tasks use scheduled (boolean) + sent_at (timestamptz) instead.
-- Date: 2025-11-17

DO $$
BEGIN
  -- Step 1: Check if scheduled_date column exists, and if so, migrate meeting tasks
  IF EXISTS (
    SELECT 1 
    FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'tasks' 
    AND column_name = 'scheduled_date'
  ) THEN
    -- Ensure meeting tasks have scheduled_date in metadata if it exists in the column
    -- First ensure meeting_details object exists, then set scheduled_date
    UPDATE public.tasks
    SET metadata = jsonb_set(
      jsonb_set(
        COALESCE(metadata, '{}'::jsonb),
        '{meeting_details}',
        COALESCE(metadata->'meeting_details', '{}'::jsonb)
      ),
      '{meeting_details,scheduled_date}',
      to_jsonb(scheduled_date::text)
    )
    WHERE task_type = 'meeting'
      AND scheduled_date IS NOT NULL
      AND (metadata->'meeting_details'->>'scheduled_date' IS NULL OR metadata->'meeting_details'->>'scheduled_date' = '');
    
    RAISE NOTICE 'Migrated scheduled_date from column to metadata for meeting tasks';
  ELSE
    RAISE NOTICE 'scheduled_date column does not exist, skipping migration step';
  END IF;

  -- Step 2: Drop the index on scheduled_date (if it exists)
  DROP INDEX IF EXISTS public.idx_tasks_scheduled_date;

  -- Step 3: Drop the scheduled_date column (if it exists)
  IF EXISTS (
    SELECT 1 
    FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'tasks' 
    AND column_name = 'scheduled_date'
  ) THEN
    ALTER TABLE public.tasks DROP COLUMN scheduled_date;
    RAISE NOTICE 'Dropped scheduled_date column';
  ELSE
    RAISE NOTICE 'scheduled_date column does not exist, skipping drop';
  END IF;
END $$;

