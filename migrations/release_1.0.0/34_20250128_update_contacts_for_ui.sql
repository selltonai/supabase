-- Migration: Update Contacts for UI Requirements
-- Description: Updates contacts table to support all UI features, removes unnecessary fields, adds multiple notes support
-- Author: System
-- Date: 2025-01-28

-- Remove unnecessary columns from contacts table
ALTER TABLE contacts DROP COLUMN IF EXISTS plan_name;
ALTER TABLE contacts DROP COLUMN IF EXISTS projects_count;

-- Add missing columns for UI support
ALTER TABLE contacts ADD COLUMN IF NOT EXISTS fit_score INTEGER CHECK (fit_score >= 0 AND fit_score <= 100);
ALTER TABLE contacts ADD COLUMN IF NOT EXISTS fit_score_rationale TEXT;
ALTER TABLE contacts ADD COLUMN IF NOT EXISTS campaign TEXT;
ALTER TABLE contacts ADD COLUMN IF NOT EXISTS pain_points TEXT[];
ALTER TABLE contacts ADD COLUMN IF NOT EXISTS company_funding TEXT;

-- Remove the single notes column (we'll use a separate notes table)
ALTER TABLE contacts DROP COLUMN IF EXISTS notes;

-- Create contact_notes table for multiple notes support
CREATE TABLE IF NOT EXISTS contact_notes (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    contact_id UUID NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
    organization_id TEXT NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL, -- User who created the note
    
    content TEXT NOT NULL,
    note_type TEXT DEFAULT 'general', -- general, call, meeting, email, etc.
    is_pinned BOOLEAN DEFAULT false,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create conversations and messages tables for proper conversation support
CREATE TABLE IF NOT EXISTS conversations (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    contact_id UUID NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
    organization_id TEXT NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL, -- Assigned user
    
    subject TEXT NOT NULL,
    channel_type channel_type NOT NULL DEFAULT 'email',
    
    -- Status and priority
    status TEXT DEFAULT 'open' CHECK (status IN ('open', 'pending', 'closed')),
    priority TEXT DEFAULT 'normal' CHECK (priority IN ('high', 'normal', 'low')),
    
    -- Email specific fields
    account_email TEXT, -- Which account the conversation is from (sales@company.com)
    
    -- Flags
    is_unread BOOLEAN DEFAULT true,
    
    -- Metadata
    tags TEXT[] DEFAULT '{}',
    metadata JSONB DEFAULT '{}',
    
    -- Timestamps
    last_message_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create messages table
CREATE TABLE IF NOT EXISTS conversation_messages (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    organization_id TEXT NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
    
    sender_type TEXT NOT NULL CHECK (sender_type IN ('user', 'contact')),
    sender_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL, -- If sender is user
    
    content TEXT NOT NULL,
    subject TEXT, -- For email messages
    
    -- Message metadata
    channel_type channel_type NOT NULL DEFAULT 'email',
    message_type TEXT DEFAULT 'text', -- text, html, attachment, etc.
    
    -- Email tracking (if applicable)
    email_message_id TEXT, -- Unique email message ID
    in_reply_to TEXT, -- Message ID this is replying to
    
    -- Metadata
    metadata JSONB DEFAULT '{}',
    
    sent_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create companies table for better company data management
CREATE TABLE IF NOT EXISTS companies (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    organization_id TEXT NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
    
    name TEXT NOT NULL,
    domain TEXT,
    website TEXT,
    industry TEXT,
    size_category TEXT, -- e.g., "500-1000", "50-100"
    funding_stage TEXT, -- e.g., "Series C - $100M"
    
    -- Location
    city TEXT,
    state TEXT,
    country TEXT,
    headquarters TEXT,
    
    -- Business info
    founded_year INTEGER,
    total_funding_amount DECIMAL(15, 2),
    last_funding_round TEXT,
    investors TEXT[],
    
    -- Technical info
    tech_stack TEXT[],
    competitors TEXT[],
    
    -- Social media
    linkedin_url TEXT,
    twitter_url TEXT,
    linkedin_followers INTEGER,
    twitter_followers INTEGER,
    
    -- Metadata
    description TEXT,
    custom_fields JSONB DEFAULT '{}',
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Ensure unique company name per organization
    UNIQUE(organization_id, name)
);

-- Add company_id reference to contacts table
ALTER TABLE contacts ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES companies(id) ON DELETE SET NULL;

-- Create indexes for performance
CREATE INDEX idx_contact_notes_contact_id ON contact_notes(contact_id);
CREATE INDEX idx_contact_notes_organization_id ON contact_notes(organization_id);
CREATE INDEX idx_contact_notes_created_at ON contact_notes(created_at);

CREATE INDEX idx_conversations_contact_id ON conversations(contact_id);
CREATE INDEX idx_conversations_organization_id ON conversations(organization_id);
CREATE INDEX idx_conversations_status ON conversations(status);
CREATE INDEX idx_conversations_is_unread ON conversations(is_unread);
CREATE INDEX idx_conversations_last_message_at ON conversations(last_message_at);

CREATE INDEX idx_conversation_messages_conversation_id ON conversation_messages(conversation_id);
CREATE INDEX idx_conversation_messages_organization_id ON conversation_messages(organization_id);
CREATE INDEX idx_conversation_messages_sent_at ON conversation_messages(sent_at);
CREATE INDEX idx_conversation_messages_sender_type ON conversation_messages(sender_type);

CREATE INDEX idx_companies_organization_id ON companies(organization_id);
CREATE INDEX idx_companies_name ON companies(name);
CREATE INDEX idx_companies_domain ON companies(domain);
CREATE INDEX idx_companies_industry ON companies(industry);

CREATE INDEX idx_contacts_company_id ON contacts(company_id);
CREATE INDEX idx_contacts_fit_score ON contacts(fit_score);
CREATE INDEX idx_contacts_campaign ON contacts(campaign);

-- Create triggers for updated_at
CREATE TRIGGER update_contact_notes_updated_at BEFORE UPDATE ON contact_notes
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_conversations_updated_at BEFORE UPDATE ON conversations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_conversation_messages_updated_at BEFORE UPDATE ON conversation_messages
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_companies_updated_at BEFORE UPDATE ON companies
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Enable Row Level Security
ALTER TABLE contact_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversation_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;

-- Create RLS policies
-- Contact notes policies
CREATE POLICY "Users can view contact notes in their organization" ON contact_notes
    FOR SELECT USING (
        organization_id IN (
            SELECT organization_id FROM user_organizations 
            WHERE user_id = auth.uid()::text
        )
    );

CREATE POLICY "Users can manage contact notes in their organization" ON contact_notes
    FOR ALL USING (
        organization_id IN (
            SELECT organization_id FROM user_organizations 
            WHERE user_id = auth.uid()::text
        )
    );

-- Conversations policies
CREATE POLICY "Users can view conversations in their organization" ON conversations
    FOR SELECT USING (
        organization_id IN (
            SELECT organization_id FROM user_organizations 
            WHERE user_id = auth.uid()::text
        )
    );

CREATE POLICY "Users can manage conversations in their organization" ON conversations
    FOR ALL USING (
        organization_id IN (
            SELECT organization_id FROM user_organizations 
            WHERE user_id = auth.uid()::text
        )
    );

-- Conversation messages policies
CREATE POLICY "Users can view conversation messages in their organization" ON conversation_messages
    FOR SELECT USING (
        organization_id IN (
            SELECT organization_id FROM user_organizations 
            WHERE user_id = auth.uid()::text
        )
    );

CREATE POLICY "Users can manage conversation messages in their organization" ON conversation_messages
    FOR ALL USING (
        organization_id IN (
            SELECT organization_id FROM user_organizations 
            WHERE user_id = auth.uid()::text
        )
    );

-- Companies policies
CREATE POLICY "Users can view companies in their organization" ON companies
    FOR SELECT USING (
        organization_id IN (
            SELECT organization_id FROM user_organizations 
            WHERE user_id = auth.uid()::text
        )
    );

CREATE POLICY "Users can manage companies in their organization" ON companies
    FOR ALL USING (
        organization_id IN (
            SELECT organization_id FROM user_organizations 
            WHERE user_id = auth.uid()::text
        )
    );

-- Add comments for documentation
COMMENT ON TABLE contact_notes IS 'Stores multiple notes for each contact';
COMMENT ON COLUMN contact_notes.note_type IS 'Type of note: general, call, meeting, email, etc.';
COMMENT ON COLUMN contact_notes.is_pinned IS 'Whether this note is pinned to the top';

COMMENT ON TABLE conversations IS 'Stores conversation threads with contacts';
COMMENT ON COLUMN conversations.account_email IS 'Email account the conversation is happening through';
COMMENT ON COLUMN conversations.tags IS 'Array of tags for categorizing conversations';

COMMENT ON TABLE conversation_messages IS 'Individual messages within conversations';
COMMENT ON COLUMN conversation_messages.sender_type IS 'Whether message was sent by user or contact';
COMMENT ON COLUMN conversation_messages.email_message_id IS 'Unique email message ID for tracking';

COMMENT ON TABLE companies IS 'Company information separate from contacts for better data management';
COMMENT ON COLUMN companies.size_category IS 'Company size range (e.g., 500-1000, 50-100)';
COMMENT ON COLUMN companies.funding_stage IS 'Latest funding information (e.g., Series C - $100M)'; 