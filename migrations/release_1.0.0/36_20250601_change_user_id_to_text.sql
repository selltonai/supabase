-- Migration: Change user_id columns to TEXT for consistency
-- Date: 2025-06-01
-- This migration changes all user_id and sender_user_id columns in contacts-related tables from UUID to TEXT,
-- and updates their foreign key references to point to "user"(id) (TEXT) instead of auth.users(id) (UUID).

-- 1. contacts.user_id
ALTER TABLE contacts
    ALTER COLUMN user_id DROP DEFAULT,
    ALTER COLUMN user_id TYPE TEXT USING user_id::text,
    DROP CONSTRAINT IF EXISTS contacts_user_id_fkey,
    ADD CONSTRAINT contacts_user_id_fkey FOREIGN KEY (user_id) REFERENCES "user"(id) ON DELETE SET NULL;

-- 2. contact_notes.user_id
ALTER TABLE contact_notes
    ALTER COLUMN user_id DROP DEFAULT,
    ALTER COLUMN user_id TYPE TEXT USING user_id::text,
    DROP CONSTRAINT IF EXISTS contact_notes_user_id_fkey,
    ADD CONSTRAINT contact_notes_user_id_fkey FOREIGN KEY (user_id) REFERENCES "user"(id) ON DELETE SET NULL;

-- 3. contact_activities.user_id
ALTER TABLE contact_activities
    ALTER COLUMN user_id DROP DEFAULT,
    ALTER COLUMN user_id TYPE TEXT USING user_id::text,
    DROP CONSTRAINT IF EXISTS contact_activities_user_id_fkey,
    ADD CONSTRAINT contact_activities_user_id_fkey FOREIGN KEY (user_id) REFERENCES "user"(id) ON DELETE SET NULL;

-- 4. contact_conversations.user_id
ALTER TABLE contact_conversations
    ALTER COLUMN user_id DROP DEFAULT,
    ALTER COLUMN user_id TYPE TEXT USING user_id::text,
    DROP CONSTRAINT IF EXISTS contact_conversations_user_id_fkey,
    ADD CONSTRAINT contact_conversations_user_id_fkey FOREIGN KEY (user_id) REFERENCES "user"(id) ON DELETE SET NULL;

-- 5. conversations.user_id
ALTER TABLE conversations
    ALTER COLUMN user_id DROP DEFAULT,
    ALTER COLUMN user_id TYPE TEXT USING user_id::text,
    DROP CONSTRAINT IF EXISTS conversations_user_id_fkey,
    ADD CONSTRAINT conversations_user_id_fkey FOREIGN KEY (user_id) REFERENCES "user"(id) ON DELETE SET NULL;

-- 6. conversation_messages.sender_user_id
ALTER TABLE conversation_messages
    ALTER COLUMN sender_user_id DROP DEFAULT,
    ALTER COLUMN sender_user_id TYPE TEXT USING sender_user_id::text,
    DROP CONSTRAINT IF EXISTS conversation_messages_sender_user_id_fkey,
    ADD CONSTRAINT conversation_messages_sender_user_id_fkey FOREIGN KEY (sender_user_id) REFERENCES "user"(id) ON DELETE SET NULL; 