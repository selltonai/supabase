-- Migration: Fix company_activities table to use correct enum type
-- Date: 2025-01-30
-- Issue: The COMPLETE_DATABASE_SETUP script created company_activities with activity_type enum
--        instead of company_activity_type enum. This migration fixes that.

-- Step 1: Ensure company_activity_type enum exists with all required values
DO $$ 
BEGIN
    -- Check if the enum exists
    IF NOT EXISTS (
        SELECT 1 FROM pg_type WHERE typname = 'company_activity_type'
    ) THEN
        -- Create the enum if it doesn't exist
        CREATE TYPE company_activity_type AS ENUM (
            'company_verification_approved',
            'company_verification_declined', 
            'note_added',
            'meeting_prepared',
            'contact_added',
            'campaign_added',
            'icp_score_updated',
            'company_updated'
        );
        RAISE NOTICE 'Created company_activity_type enum';
    ELSE
        -- Enum exists, ensure all values are present
        -- Add missing values if they don't exist
        IF NOT EXISTS (
            SELECT 1 FROM pg_enum e
            JOIN pg_type t ON e.enumtypid = t.oid
            WHERE t.typname = 'company_activity_type' AND e.enumlabel = 'company_verification_approved'
        ) THEN
            ALTER TYPE company_activity_type ADD VALUE 'company_verification_approved';
            RAISE NOTICE 'Added company_verification_approved to company_activity_type enum';
        END IF;
        
        IF NOT EXISTS (
            SELECT 1 FROM pg_enum e
            JOIN pg_type t ON e.enumtypid = t.oid
            WHERE t.typname = 'company_activity_type' AND e.enumlabel = 'company_verification_declined'
        ) THEN
            ALTER TYPE company_activity_type ADD VALUE 'company_verification_declined';
            RAISE NOTICE 'Added company_verification_declined to company_activity_type enum';
        END IF;
        
        IF NOT EXISTS (
            SELECT 1 FROM pg_enum e
            JOIN pg_type t ON e.enumtypid = t.oid
            WHERE t.typname = 'company_activity_type' AND e.enumlabel = 'note_added'
        ) THEN
            ALTER TYPE company_activity_type ADD VALUE 'note_added';
            RAISE NOTICE 'Added note_added to company_activity_type enum';
        END IF;
        
        IF NOT EXISTS (
            SELECT 1 FROM pg_enum e
            JOIN pg_type t ON e.enumtypid = t.oid
            WHERE t.typname = 'company_activity_type' AND e.enumlabel = 'meeting_prepared'
        ) THEN
            ALTER TYPE company_activity_type ADD VALUE 'meeting_prepared';
            RAISE NOTICE 'Added meeting_prepared to company_activity_type enum';
        END IF;
        
        IF NOT EXISTS (
            SELECT 1 FROM pg_enum e
            JOIN pg_type t ON e.enumtypid = t.oid
            WHERE t.typname = 'company_activity_type' AND e.enumlabel = 'contact_added'
        ) THEN
            ALTER TYPE company_activity_type ADD VALUE 'contact_added';
            RAISE NOTICE 'Added contact_added to company_activity_type enum';
        END IF;
        
        IF NOT EXISTS (
            SELECT 1 FROM pg_enum e
            JOIN pg_type t ON e.enumtypid = t.oid
            WHERE t.typname = 'company_activity_type' AND e.enumlabel = 'campaign_added'
        ) THEN
            ALTER TYPE company_activity_type ADD VALUE 'campaign_added';
            RAISE NOTICE 'Added campaign_added to company_activity_type enum';
        END IF;
        
        IF NOT EXISTS (
            SELECT 1 FROM pg_enum e
            JOIN pg_type t ON e.enumtypid = t.oid
            WHERE t.typname = 'company_activity_type' AND e.enumlabel = 'icp_score_updated'
        ) THEN
            ALTER TYPE company_activity_type ADD VALUE 'icp_score_updated';
            RAISE NOTICE 'Added icp_score_updated to company_activity_type enum';
        END IF;
        
        IF NOT EXISTS (
            SELECT 1 FROM pg_enum e
            JOIN pg_type t ON e.enumtypid = t.oid
            WHERE t.typname = 'company_activity_type' AND e.enumlabel = 'company_updated'
        ) THEN
            ALTER TYPE company_activity_type ADD VALUE 'company_updated';
            RAISE NOTICE 'Added company_updated to company_activity_type enum';
        END IF;
        
        RAISE NOTICE 'company_activity_type enum already exists, verified all values';
    END IF;
END $$;

-- Step 2: Check if company_activities table exists and uses the wrong enum type
DO $$
DECLARE
    current_type_name text;
BEGIN
    -- Check what type the activity_type column currently uses
    SELECT udt_name INTO current_type_name
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'company_activities'
      AND column_name = 'activity_type';
    
    -- If the table exists and uses the wrong enum type, fix it
    IF current_type_name = 'activity_type' THEN
        RAISE NOTICE 'Found company_activities table using wrong enum type (activity_type), fixing...';
        
        -- First, delete any rows that have incompatible activity types
        -- (since activity_type enum doesn't have company_verification_approved/declined)
        DELETE FROM public.company_activities 
        WHERE activity_type::text IN ('company_verification_approved', 'company_verification_declined');
        
        -- Now alter the column to use the correct enum type
        -- Convert compatible values: note_added, meeting_prepared, contact_added, campaign_added
        ALTER TABLE public.company_activities 
        ALTER COLUMN activity_type TYPE company_activity_type 
        USING CASE 
            WHEN activity_type::text IN ('note_added', 'meeting_prepared', 'contact_added', 'campaign_added') 
            THEN activity_type::text::company_activity_type
            ELSE 'note_added'::company_activity_type  -- Default fallback for any other values
        END;
        
        RAISE NOTICE 'Fixed company_activities.activity_type to use company_activity_type enum';
    ELSIF current_type_name = 'company_activity_type' THEN
        RAISE NOTICE 'company_activities table already uses correct enum type (company_activity_type)';
    ELSIF current_type_name IS NULL THEN
        RAISE NOTICE 'company_activities table does not exist or activity_type column not found';
    ELSE
        RAISE NOTICE 'company_activities.activity_type uses unexpected type: %', current_type_name;
    END IF;
END $$;

-- Step 3: Update comment
COMMENT ON TYPE company_activity_type IS 'Valid activity types for company_activities table: company_verification_approved, company_verification_declined, note_added, meeting_prepared, contact_added, campaign_added, icp_score_updated, company_updated';

