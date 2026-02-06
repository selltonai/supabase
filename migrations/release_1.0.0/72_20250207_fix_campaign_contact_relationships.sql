-- Migration: Fix Campaign Contact Relationships
-- Description: Remove single campaign_id constraint from contacts table and ensure proper many-to-many relationships
-- Author: System
-- Date: 2025-02-07

-- 1. First, check if campaign_contacts table exists and migrate any existing campaign_id data
-- This ensures we don't lose any existing relationships
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'campaign_contacts') THEN
        INSERT INTO campaign_contacts (
  campaign_id,
  contact_id,
  organization_id,
  source_type,
  created_from_campaign,
  added_by_user_id,
  added_at,
  status
)
SELECT 
  c.campaign_id,
  c.id as contact_id,
  c.organization_id,
  'manual' as source_type,
  false as created_from_campaign,
  c.user_id as added_by_user_id,
  c.created_at as added_at,
  'active' as status
FROM contacts c
WHERE c.campaign_id IS NOT NULL
  AND NOT EXISTS (
    -- Don't duplicate if relationship already exists in campaign_contacts
    SELECT 1 FROM campaign_contacts cc 
    WHERE cc.campaign_id = c.campaign_id 
    AND cc.contact_id = c.id
  );
    END IF;
END $$;

-- 2. Remove the campaign_id column from contacts table since we now use campaign_contacts for relationships
ALTER TABLE contacts DROP COLUMN IF EXISTS campaign_id;

-- 3. Remove the campaign field from contacts table since it's now stored in campaign_contacts
ALTER TABLE contacts DROP COLUMN IF EXISTS campaign;

-- 4. Remove the selected_contacts array from campaigns table since we use campaign_contacts for relationships
ALTER TABLE campaigns DROP COLUMN IF EXISTS selected_contacts;

-- 4. Update any existing campaign_emails that might not have corresponding campaign_contacts records
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'campaign_contacts') THEN
        INSERT INTO campaign_contacts (
          campaign_id,
          contact_id,
          organization_id,
          source_type,
          created_from_campaign,
          added_at,
          status
        )
        SELECT DISTINCT
          ce.campaign_id,
          ce.contact_id,
          ce.organization_id,
          'manual' as source_type,
          false as created_from_campaign,
          ce.created_at as added_at,
          'active' as status
        FROM campaign_emails ce
        WHERE NOT EXISTS (
          SELECT 1 FROM campaign_contacts cc 
          WHERE cc.campaign_id = ce.campaign_id 
          AND cc.contact_id = ce.contact_id
        );
    END IF;
END $$;

-- 5. Ensure all campaigns have accurate total_contacts count based on campaign_contacts
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'campaign_contacts') THEN
        UPDATE campaigns 
        SET total_contacts = (
          SELECT COUNT(*)
          FROM campaign_contacts cc
          WHERE cc.campaign_id = campaigns.id
            AND cc.status = 'active'
        );
    END IF;
END $$;

-- 6. Update selected_contacts array in campaigns to match campaign_contacts (REMOVED - we no longer use selected_contacts)

-- 7. Create a function to automatically update campaign metrics when contacts are added/removed
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'campaign_contacts') THEN
        CREATE OR REPLACE FUNCTION update_campaign_contact_count()
        RETURNS TRIGGER AS $func$
        BEGIN
          -- Update the campaign's total_contacts
          IF TG_OP = 'INSERT' THEN
            -- Adding a contact
            UPDATE campaigns 
            SET 
              total_contacts = (
                SELECT COUNT(*)
                FROM campaign_contacts cc
                WHERE cc.campaign_id = NEW.campaign_id
                  AND cc.status = 'active'
              )
            WHERE id = NEW.campaign_id;
            
            RETURN NEW;
          ELSIF TG_OP = 'UPDATE' THEN
            -- Status change or other update
            UPDATE campaigns 
            SET 
              total_contacts = (
                SELECT COUNT(*)
                FROM campaign_contacts cc
                WHERE cc.campaign_id = NEW.campaign_id
                  AND cc.status = 'active'
              )
            WHERE id = NEW.campaign_id;
            
            -- If campaign_id changed, update both old and new campaigns
            IF OLD.campaign_id != NEW.campaign_id THEN
              UPDATE campaigns 
              SET 
                total_contacts = (
                  SELECT COUNT(*)
                  FROM campaign_contacts cc
                  WHERE cc.campaign_id = OLD.campaign_id
                    AND cc.status = 'active'
                )
              WHERE id = OLD.campaign_id;
            END IF;
            
            RETURN NEW;
          ELSIF TG_OP = 'DELETE' THEN
            -- Removing a contact
            UPDATE campaigns 
            SET 
              total_contacts = (
                SELECT COUNT(*)
                FROM campaign_contacts cc
                WHERE cc.campaign_id = OLD.campaign_id
                  AND cc.status = 'active'
              )
            WHERE id = OLD.campaign_id;
            
            RETURN OLD;
          END IF;
          
          RETURN NULL;
        END;
        $func$ LANGUAGE plpgsql;

        -- 8. Create trigger to automatically update campaign contact counts
        DROP TRIGGER IF EXISTS trigger_update_campaign_contact_count ON campaign_contacts;
        CREATE TRIGGER trigger_update_campaign_contact_count
          AFTER INSERT OR UPDATE OR DELETE ON campaign_contacts
          FOR EACH ROW
          EXECUTE FUNCTION update_campaign_contact_count();
    END IF;
END $$;

-- 9. Create a function to get all campaigns for a contact
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'campaign_contacts') THEN
        CREATE OR REPLACE FUNCTION get_contact_campaigns(p_contact_id UUID)
        RETURNS TABLE (
          campaign_id UUID,
          campaign_name TEXT,
          campaign_status TEXT,
          campaign_type TEXT,
          added_at TIMESTAMPTZ,
          source_type TEXT,
          relationship_status TEXT
        ) AS $func$
        BEGIN
          RETURN QUERY
          SELECT 
            c.id as campaign_id,
            c.name as campaign_name,
            c.status::TEXT as campaign_status,
            c.campaign_type,
            cc.added_at,
            cc.source_type,
            cc.status as relationship_status
          FROM campaign_contacts cc
          JOIN campaigns c ON c.id = cc.campaign_id
          WHERE cc.contact_id = p_contact_id
          ORDER BY cc.added_at DESC;
        END;
        $func$ LANGUAGE plpgsql;

        -- 10. Create a function to get all contacts for a campaign
        CREATE OR REPLACE FUNCTION get_campaign_contacts(p_campaign_id UUID)
        RETURNS TABLE (
          contact_id UUID,
          contact_name TEXT,
          contact_email TEXT,
          company_name TEXT,
          job_title TEXT,
          added_at TIMESTAMPTZ,
          source_type TEXT,
          relationship_status TEXT,
          created_from_campaign BOOLEAN
        ) AS $func$
        BEGIN
          RETURN QUERY
          SELECT 
            c.id as contact_id,
            c.name as contact_name,
            c.email as contact_email,
            c.company_name,
            c.job_title,
            cc.added_at,
            cc.source_type,
            cc.status as relationship_status,
            cc.created_from_campaign
          FROM campaign_contacts cc
          JOIN contacts c ON c.id = cc.contact_id
          WHERE cc.campaign_id = p_campaign_id
          ORDER BY cc.added_at DESC;
        END;
        $func$ LANGUAGE plpgsql;
    END IF;
END $$;

-- 11. Add indexes for better performance on the new queries
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'campaign_contacts') THEN
        CREATE INDEX IF NOT EXISTS idx_campaign_contacts_contact_campaigns ON campaign_contacts(contact_id, added_at DESC);
        CREATE INDEX IF NOT EXISTS idx_campaign_contacts_campaign_contacts ON campaign_contacts(campaign_id, added_at DESC);
    END IF;
END $$;

-- 12. Update any existing constraints to ensure data integrity
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'campaign_contacts') THEN
        -- Ensure campaign_emails only exist for valid campaign-contact relationships
        DELETE FROM campaign_emails ce
        WHERE NOT EXISTS (
          SELECT 1 FROM campaign_contacts cc
          WHERE cc.campaign_id = ce.campaign_id
            AND cc.contact_id = ce.contact_id
        );

        -- Add a constraint to ensure campaign_emails match campaign_contacts
        -- This will prevent creating campaign_emails without proper campaign_contacts relationships
        ALTER TABLE campaign_emails DROP CONSTRAINT IF EXISTS campaign_emails_must_have_relationship;
        ALTER TABLE campaign_emails ADD CONSTRAINT campaign_emails_must_have_relationship
          CHECK (
            EXISTS (
              SELECT 1 FROM campaign_contacts cc
              WHERE cc.campaign_id = campaign_emails.campaign_id
                AND cc.contact_id = campaign_emails.contact_id
            )
          );
    END IF;
END $$;

-- Note: The above constraint might fail if there are existing campaign_emails without campaign_contacts
-- If it fails, run the INSERT statement in step 4 first, then retry the constraint

-- 14. Add comments for documentation
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'campaign_contacts') THEN
        COMMENT ON FUNCTION update_campaign_contact_count() IS 'Automatically updates campaign total_contacts when campaign_contacts changes';
        COMMENT ON FUNCTION get_contact_campaigns(UUID) IS 'Returns all campaigns that a contact is part of';
        COMMENT ON FUNCTION get_campaign_contacts(UUID) IS 'Returns all contacts in a specific campaign with relationship details';
    END IF;
END $$;

-- 15. Log the migration completion
INSERT INTO campaign_activities (
  campaign_id, 
  organization_id, 
  activity_type, 
  activity_data, 
  occurred_at
) 
SELECT 
  id,
  organization_id,
  'system_migration',
  jsonb_build_object(
    'migration_type', 'campaign_contact_relationships',
    'migration', '72_20250207_fix_campaign_contact_relationships',
    'description', 'Fixed campaign-contact relationships to support many-to-many relationships',
    'changes', jsonb_build_array(
      'Removed campaign_id column from contacts table',
      'Migrated existing relationships to campaign_contacts table',
      'Added automatic contact count updates',
      'Created helper functions for campaign-contact queries'
    )
  ),
  NOW()
FROM campaigns
WHERE total_contacts > 0; 