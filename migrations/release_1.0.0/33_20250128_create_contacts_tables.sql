-- Migration: Create Contacts Tables
-- Description: Creates tables for managing contacts, their communication channels, and activities
-- Author: System
-- Date: 2025-01-28

-- Create enum for contact types
CREATE TYPE contact_type AS ENUM ('user', 'lead', 'customer', 'prospect');

-- Create enum for channel types
CREATE TYPE channel_type AS ENUM ('email', 'whatsapp', 'messenger', 'phone_sms', 'phone', 'linkedin', 'twitter', 'other');

-- Create enum for activity types
CREATE TYPE activity_type AS ENUM ('email_sent', 'email_received', 'call', 'meeting', 'note', 'task', 'deal_created', 'deal_updated', 'status_change');

-- Create contacts table
CREATE TABLE IF NOT EXISTS contacts (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    organization_id TEXT NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL, -- Owner/assigned user
    
    -- Basic Information
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    avatar_url TEXT,
    
    -- Contact Type and Status
    contact_type contact_type DEFAULT 'lead',
    status TEXT DEFAULT 'active', -- active, inactive, archived
    
    -- Company Information
    company_name TEXT,
    company_size TEXT,
    company_industry TEXT,
    job_title TEXT,
    
    -- Location Information
    city TEXT,
    state TEXT,
    country TEXT,
    timezone TEXT,
    
    -- Engagement Metrics
    first_seen_at TIMESTAMPTZ DEFAULT NOW(),
    last_seen_at TIMESTAMPTZ DEFAULT NOW(),
    signed_up_at TIMESTAMPTZ,
    web_sessions INTEGER DEFAULT 0,
    page_views INTEGER DEFAULT 0,
    
    -- Business Metrics
    lifetime_value DECIMAL(10, 2) DEFAULT 0,
    plan_name TEXT,
    projects_count INTEGER DEFAULT 0,
    
    -- Custom Fields (JSON for flexibility)
    custom_fields JSONB DEFAULT '{}',
    tags TEXT[] DEFAULT '{}',
    
    -- Notes
    notes TEXT,
    
    -- Metadata
    external_id TEXT, -- ID from external systems
    source TEXT, -- Where the contact came from (manual, import, api, etc.)
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create contact_channels table
CREATE TABLE IF NOT EXISTS contact_channels (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    contact_id UUID NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
    organization_id TEXT NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
    
    channel_type channel_type NOT NULL,
    channel_value TEXT NOT NULL, -- email address, phone number, etc.
    is_primary BOOLEAN DEFAULT false,
    is_verified BOOLEAN DEFAULT false,
    
    -- Channel-specific metadata
    metadata JSONB DEFAULT '{}',
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Ensure unique channel per contact
    UNIQUE(contact_id, channel_type, channel_value)
);

-- Create contact_activities table
CREATE TABLE IF NOT EXISTS contact_activities (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    contact_id UUID NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
    organization_id TEXT NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL, -- User who performed the activity
    
    activity_type activity_type NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    
    -- Activity metadata (varies by type)
    metadata JSONB DEFAULT '{}',
    
    -- Related entities
    related_to_id UUID, -- Can reference other entities like deals, tickets, etc.
    related_to_type TEXT, -- Type of related entity
    
    occurred_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create contact_conversations table for tracking conversations
CREATE TABLE IF NOT EXISTS contact_conversations (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    contact_id UUID NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
    organization_id TEXT NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL, -- Assigned user
    
    channel_type channel_type NOT NULL,
    subject TEXT,
    last_message_preview TEXT,
    last_message_at TIMESTAMPTZ,
    
    is_open BOOLEAN DEFAULT true,
    is_unread BOOLEAN DEFAULT true,
    
    metadata JSONB DEFAULT '{}',
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes for performance
CREATE INDEX idx_contacts_organization_id ON contacts(organization_id);
CREATE INDEX idx_contacts_user_id ON contacts(user_id);
CREATE INDEX idx_contacts_email ON contacts(email);
CREATE INDEX idx_contacts_company_name ON contacts(company_name);
CREATE INDEX idx_contacts_last_seen_at ON contacts(last_seen_at);
CREATE INDEX idx_contacts_contact_type ON contacts(contact_type);
CREATE INDEX idx_contacts_status ON contacts(status);
CREATE INDEX idx_contacts_tags ON contacts USING GIN(tags);

CREATE INDEX idx_contact_channels_contact_id ON contact_channels(contact_id);
CREATE INDEX idx_contact_channels_organization_id ON contact_channels(organization_id);
CREATE INDEX idx_contact_channels_channel_type ON contact_channels(channel_type);

CREATE INDEX idx_contact_activities_contact_id ON contact_activities(contact_id);
CREATE INDEX idx_contact_activities_organization_id ON contact_activities(organization_id);
CREATE INDEX idx_contact_activities_user_id ON contact_activities(user_id);
CREATE INDEX idx_contact_activities_activity_type ON contact_activities(activity_type);
CREATE INDEX idx_contact_activities_occurred_at ON contact_activities(occurred_at);

CREATE INDEX idx_contact_conversations_contact_id ON contact_conversations(contact_id);
CREATE INDEX idx_contact_conversations_organization_id ON contact_conversations(organization_id);
CREATE INDEX idx_contact_conversations_is_open ON contact_conversations(is_open);
CREATE INDEX idx_contact_conversations_last_message_at ON contact_conversations(last_message_at);

-- Create updated_at trigger function if it doesn't exist
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create triggers for updated_at
CREATE TRIGGER update_contacts_updated_at BEFORE UPDATE ON contacts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_contact_channels_updated_at BEFORE UPDATE ON contact_channels
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_contact_activities_updated_at BEFORE UPDATE ON contact_activities
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_contact_conversations_updated_at BEFORE UPDATE ON contact_conversations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Enable Row Level Security
ALTER TABLE contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE contact_channels ENABLE ROW LEVEL SECURITY;
ALTER TABLE contact_activities ENABLE ROW LEVEL SECURITY;
ALTER TABLE contact_conversations ENABLE ROW LEVEL SECURITY;

-- Create RLS policies
-- Contacts policies
CREATE POLICY "Users can view contacts in their organization" ON contacts
    FOR SELECT USING (
        organization_id IN (
            SELECT organization_id FROM user_organizations 
            WHERE user_id = auth.uid()::text
        )
    );

CREATE POLICY "Users can create contacts in their organization" ON contacts
    FOR INSERT WITH CHECK (
        organization_id IN (
            SELECT organization_id FROM user_organizations 
            WHERE user_id = auth.uid()::text
        )
    );

CREATE POLICY "Users can update contacts in their organization" ON contacts
    FOR UPDATE USING (
        organization_id IN (
            SELECT organization_id FROM user_organizations 
            WHERE user_id = auth.uid()::text
        )
    );

CREATE POLICY "Users can delete contacts in their organization" ON contacts
    FOR DELETE USING (
        organization_id IN (
            SELECT organization_id FROM user_organizations 
            WHERE user_id = auth.uid()::text
        )
    );

-- Contact channels policies
CREATE POLICY "Users can view contact channels in their organization" ON contact_channels
    FOR SELECT USING (
        organization_id IN (
            SELECT organization_id FROM user_organizations 
            WHERE user_id = auth.uid()::text
        )
    );

CREATE POLICY "Users can manage contact channels in their organization" ON contact_channels
    FOR ALL USING (
        organization_id IN (
            SELECT organization_id FROM user_organizations 
            WHERE user_id = auth.uid()::text
        )
    );

-- Contact activities policies
CREATE POLICY "Users can view contact activities in their organization" ON contact_activities
    FOR SELECT USING (
        organization_id IN (
            SELECT organization_id FROM user_organizations 
            WHERE user_id = auth.uid()::text
        )
    );

CREATE POLICY "Users can manage contact activities in their organization" ON contact_activities
    FOR ALL USING (
        organization_id IN (
            SELECT organization_id FROM user_organizations 
            WHERE user_id = auth.uid()::text
        )
    );

-- Contact conversations policies
CREATE POLICY "Users can view contact conversations in their organization" ON contact_conversations
    FOR SELECT USING (
        organization_id IN (
            SELECT organization_id FROM user_organizations 
            WHERE user_id = auth.uid()::text
        )
    );

CREATE POLICY "Users can manage contact conversations in their organization" ON contact_conversations
    FOR ALL USING (
        organization_id IN (
            SELECT organization_id FROM user_organizations 
            WHERE user_id = auth.uid()::text
        )
    );

-- Add comments for documentation
COMMENT ON TABLE contacts IS 'Stores contact information for users, leads, and customers';
COMMENT ON COLUMN contacts.organization_id IS 'Organization this contact belongs to';
COMMENT ON COLUMN contacts.user_id IS 'User who owns or is assigned to this contact';
COMMENT ON COLUMN contacts.contact_type IS 'Type of contact: user, lead, customer, or prospect';
COMMENT ON COLUMN contacts.lifetime_value IS 'Total revenue generated by this contact';
COMMENT ON COLUMN contacts.custom_fields IS 'JSON object for storing custom fields specific to the organization';

COMMENT ON TABLE contact_channels IS 'Stores communication channels for each contact';
COMMENT ON COLUMN contact_channels.channel_type IS 'Type of communication channel';
COMMENT ON COLUMN contact_channels.channel_value IS 'The actual value (email address, phone number, etc.)';
COMMENT ON COLUMN contact_channels.metadata IS 'Channel-specific metadata (e.g., WhatsApp business account info)';

COMMENT ON TABLE contact_activities IS 'Stores all activities and interactions with contacts';
COMMENT ON COLUMN contact_activities.activity_type IS 'Type of activity performed';
COMMENT ON COLUMN contact_activities.metadata IS 'Activity-specific data (e.g., email content, call duration)';

COMMENT ON TABLE contact_conversations IS 'Tracks conversations with contacts across different channels';
COMMENT ON COLUMN contact_conversations.last_message_preview IS 'Preview of the last message in the conversation'; 