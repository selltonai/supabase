-- Migration: Remove contact_conversations table
-- Since conversations are now fetched from external API, this table is no longer needed

-- Drop RLS policies first
DROP POLICY IF EXISTS "Users can view contact conversations in their organization" ON contact_conversations;
DROP POLICY IF EXISTS "Users can manage contact conversations in their organization" ON contact_conversations;

-- Drop trigger
DROP TRIGGER IF EXISTS update_contact_conversations_updated_at ON contact_conversations;

-- Drop indexes
DROP INDEX IF EXISTS idx_contact_conversations_contact_id;
DROP INDEX IF EXISTS idx_contact_conversations_organization_id;
DROP INDEX IF EXISTS idx_contact_conversations_is_open;
DROP INDEX IF EXISTS idx_contact_conversations_last_message_at;

-- Drop the table
DROP TABLE IF EXISTS contact_conversations;

-- Add comment to document the removal
COMMENT ON SCHEMA public IS 'contact_conversations table removed - conversations now fetched from external API'; 