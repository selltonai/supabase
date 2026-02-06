-- Migration: Create Campaigns and Tasks Tables
-- Description: Creates tables for managing email campaigns, tasks, and tracking campaign performance
-- Author: System
-- Date: 2025-01-30

-- Create enum for task types
CREATE TYPE task_type AS ENUM ('review_draft', 'send_email', 'follow_up', 'meeting', 'custom');

-- Create enum for task status
CREATE TYPE task_status AS ENUM ('pending', 'in_progress', 'completed', 'cancelled', 'scheduled');

-- Create enum for campaign status
CREATE TYPE campaign_status AS ENUM ('draft', 'active', 'paused', 'completed', 'cancelled');

-- Create enum for email status
CREATE TYPE email_status AS ENUM ('draft', 'scheduled', 'sent', 'delivered', 'opened', 'clicked', 'replied', 'bounced', 'failed');

-- Create campaigns table
CREATE TABLE IF NOT EXISTS campaigns (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    organization_id TEXT NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL, -- User who created the campaign
    
    -- Campaign Details
    name TEXT NOT NULL,
    description TEXT,
    campaign_type TEXT DEFAULT 'email', -- email, sms, whatsapp, etc.
    status campaign_status DEFAULT 'draft',
    
    -- Targeting
    target_audience JSONB DEFAULT '{}', -- Criteria for selecting contacts
    selected_contacts UUID[] DEFAULT '{}', -- Specific contact IDs if manually selected
    total_contacts INTEGER DEFAULT 0,
    
    -- Email Template
    subject_line TEXT,
    pre_generated_copy TEXT, -- Original AI-generated copy
    final_copy TEXT, -- Approved/edited copy that gets sent
    
    -- Campaign Settings
    settings JSONB DEFAULT '{}', -- Additional campaign settings
    
    -- Schedule
    scheduled_start_date TIMESTAMPTZ,
    scheduled_end_date TIMESTAMPTZ,
    
    -- Performance Metrics
    emails_sent INTEGER DEFAULT 0,
    emails_delivered INTEGER DEFAULT 0,
    emails_opened INTEGER DEFAULT 0,
    emails_clicked INTEGER DEFAULT 0,
    emails_replied INTEGER DEFAULT 0,
    emails_bounced INTEGER DEFAULT 0,
    meetings_booked INTEGER DEFAULT 0,
    
    -- Metadata
    tags TEXT[] DEFAULT '{}',
    metadata JSONB DEFAULT '{}',
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ
);

-- Create tasks table
CREATE TABLE IF NOT EXISTS tasks (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    organization_id TEXT NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL, -- Assigned user
    created_by_user_id TEXT NOT NULL, -- User who created the task
    
    -- Task Details
    title TEXT NOT NULL,
    description TEXT,
    task_type task_type NOT NULL,
    status task_status DEFAULT 'pending',
    priority TEXT DEFAULT 'normal' CHECK (priority IN ('high', 'normal', 'low')),
    
    -- Related Entities
    contact_id UUID REFERENCES contacts(id) ON DELETE SET NULL,
    campaign_id UUID REFERENCES campaigns(id) ON DELETE SET NULL,
    conversation_id UUID REFERENCES conversations(id) ON DELETE SET NULL,
    
    -- Email Draft Specific Fields
    pre_generated_copy TEXT, -- For review_draft tasks
    final_copy TEXT, -- Approved copy
    
    -- Due Date and Schedule
    due_date TIMESTAMPTZ,
    scheduled_date TIMESTAMPTZ, -- For scheduled tasks
    
    -- Completion Info
    completed_at TIMESTAMPTZ,
    completed_by_user_id TEXT,
    
    -- Metadata
    metadata JSONB DEFAULT '{}',
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create campaign_emails table to track individual emails
CREATE TABLE IF NOT EXISTS campaign_emails (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    campaign_id UUID NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
    contact_id UUID NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
    organization_id TEXT NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
    
    -- Email Status
    status email_status DEFAULT 'draft',
    
    -- Email Content (might have personalization)
    subject TEXT,
    content TEXT, -- Final personalized content
    
    -- Email Metadata
    message_id TEXT, -- Email service provider message ID
    thread_id TEXT, -- Gmail thread ID or similar
    
    -- Tracking
    sent_at TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ,
    opened_at TIMESTAMPTZ,
    first_opened_at TIMESTAMPTZ,
    clicked_at TIMESTAMPTZ,
    replied_at TIMESTAMPTZ,
    bounced_at TIMESTAMPTZ,
    
    -- Response
    reply_content TEXT,
    reply_received_at TIMESTAMPTZ,
    
    -- Metrics
    open_count INTEGER DEFAULT 0,
    click_count INTEGER DEFAULT 0,
    
    -- Error Info
    error_message TEXT,
    error_code TEXT,
    
    -- Metadata
    metadata JSONB DEFAULT '{}',
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create campaign_activities table for tracking all campaign-related activities
CREATE TABLE IF NOT EXISTS campaign_activities (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    campaign_id UUID NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
    contact_id UUID REFERENCES contacts(id) ON DELETE SET NULL,
    organization_id TEXT NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
    user_id TEXT, -- User who performed the activity
    
    activity_type TEXT NOT NULL, -- email_sent, email_opened, email_clicked, email_replied, meeting_booked, etc.
    activity_data JSONB DEFAULT '{}',
    
    occurred_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes for performance
CREATE INDEX idx_campaigns_organization_id ON campaigns(organization_id);
CREATE INDEX idx_campaigns_user_id ON campaigns(user_id);
CREATE INDEX idx_campaigns_status ON campaigns(status);
CREATE INDEX idx_campaigns_created_at ON campaigns(created_at);
CREATE INDEX idx_campaigns_scheduled_start_date ON campaigns(scheduled_start_date);

CREATE INDEX idx_tasks_organization_id ON tasks(organization_id);
CREATE INDEX idx_tasks_user_id ON tasks(user_id);
CREATE INDEX idx_tasks_created_by_user_id ON tasks(created_by_user_id);
CREATE INDEX idx_tasks_contact_id ON tasks(contact_id);
CREATE INDEX idx_tasks_campaign_id ON tasks(campaign_id);
CREATE INDEX idx_tasks_conversation_id ON tasks(conversation_id);
CREATE INDEX idx_tasks_status ON tasks(status);
CREATE INDEX idx_tasks_task_type ON tasks(task_type);
CREATE INDEX idx_tasks_due_date ON tasks(due_date);
CREATE INDEX idx_tasks_scheduled_date ON tasks(scheduled_date);

CREATE INDEX idx_campaign_emails_campaign_id ON campaign_emails(campaign_id);
CREATE INDEX idx_campaign_emails_contact_id ON campaign_emails(contact_id);
CREATE INDEX idx_campaign_emails_organization_id ON campaign_emails(organization_id);
CREATE INDEX idx_campaign_emails_status ON campaign_emails(status);
CREATE INDEX idx_campaign_emails_sent_at ON campaign_emails(sent_at);
CREATE INDEX idx_campaign_emails_thread_id ON campaign_emails(thread_id);

CREATE INDEX idx_campaign_activities_campaign_id ON campaign_activities(campaign_id);
CREATE INDEX idx_campaign_activities_contact_id ON campaign_activities(contact_id);
CREATE INDEX idx_campaign_activities_organization_id ON campaign_activities(organization_id);
CREATE INDEX idx_campaign_activities_activity_type ON campaign_activities(activity_type);
CREATE INDEX idx_campaign_activities_occurred_at ON campaign_activities(occurred_at);

-- Create triggers for updated_at
CREATE TRIGGER update_campaigns_updated_at BEFORE UPDATE ON campaigns
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_tasks_updated_at BEFORE UPDATE ON tasks
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_campaign_emails_updated_at BEFORE UPDATE ON campaign_emails
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Enable Row Level Security
ALTER TABLE campaigns ENABLE ROW LEVEL SECURITY;
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE campaign_emails ENABLE ROW LEVEL SECURITY;
ALTER TABLE campaign_activities ENABLE ROW LEVEL SECURITY;

-- Create RLS policies
-- Campaigns policies
CREATE POLICY "Users can view campaigns in their organization" ON campaigns
    FOR SELECT USING (
        organization_id IN (
            SELECT organization_id FROM user_organizations 
            WHERE user_id = auth.uid()::text
        )
    );

CREATE POLICY "Users can create campaigns in their organization" ON campaigns
    FOR INSERT WITH CHECK (
        organization_id IN (
            SELECT organization_id FROM user_organizations 
            WHERE user_id = auth.uid()::text
        )
    );

CREATE POLICY "Users can update campaigns in their organization" ON campaigns
    FOR UPDATE USING (
        organization_id IN (
            SELECT organization_id FROM user_organizations 
            WHERE user_id = auth.uid()::text
        )
    );

CREATE POLICY "Users can delete campaigns in their organization" ON campaigns
    FOR DELETE USING (
        organization_id IN (
            SELECT organization_id FROM user_organizations 
            WHERE user_id = auth.uid()::text
        )
    );

-- Tasks policies
CREATE POLICY "Users can view tasks in their organization" ON tasks
    FOR SELECT USING (
        organization_id IN (
            SELECT organization_id FROM user_organizations 
            WHERE user_id = auth.uid()::text
        )
    );

CREATE POLICY "Users can manage tasks in their organization" ON tasks
    FOR ALL USING (
        organization_id IN (
            SELECT organization_id FROM user_organizations 
            WHERE user_id = auth.uid()::text
        )
    );

-- Campaign emails policies
CREATE POLICY "Users can view campaign emails in their organization" ON campaign_emails
    FOR SELECT USING (
        organization_id IN (
            SELECT organization_id FROM user_organizations 
            WHERE user_id = auth.uid()::text
        )
    );

CREATE POLICY "Users can manage campaign emails in their organization" ON campaign_emails
    FOR ALL USING (
        organization_id IN (
            SELECT organization_id FROM user_organizations 
            WHERE user_id = auth.uid()::text
        )
    );

-- Campaign activities policies
CREATE POLICY "Users can view campaign activities in their organization" ON campaign_activities
    FOR SELECT USING (
        organization_id IN (
            SELECT organization_id FROM user_organizations 
            WHERE user_id = auth.uid()::text
        )
    );

CREATE POLICY "Users can manage campaign activities in their organization" ON campaign_activities
    FOR ALL USING (
        organization_id IN (
            SELECT organization_id FROM user_organizations 
            WHERE user_id = auth.uid()::text
        )
    );

-- Add comments for documentation
COMMENT ON TABLE campaigns IS 'Stores email marketing campaigns and their performance metrics';
COMMENT ON COLUMN campaigns.pre_generated_copy IS 'Original AI-generated email copy before user edits';
COMMENT ON COLUMN campaigns.final_copy IS 'Final approved email copy that will be sent';
COMMENT ON COLUMN campaigns.target_audience IS 'JSON criteria for selecting contacts (e.g., {industry: "tech", size: ">100"})';

COMMENT ON TABLE tasks IS 'Stores tasks for users including draft reviews, follow-ups, and meetings';
COMMENT ON COLUMN tasks.task_type IS 'Type of task: review_draft, send_email, follow_up, meeting, custom';
COMMENT ON COLUMN tasks.pre_generated_copy IS 'For review_draft tasks: the original AI-generated copy';
COMMENT ON COLUMN tasks.final_copy IS 'For review_draft tasks: the approved/edited copy';

COMMENT ON TABLE campaign_emails IS 'Tracks individual emails sent as part of campaigns';
COMMENT ON COLUMN campaign_emails.thread_id IS 'Email thread ID for tracking conversations (e.g., Gmail thread ID)';

COMMENT ON TABLE campaign_activities IS 'Detailed activity log for all campaign-related events';
COMMENT ON COLUMN campaign_activities.activity_data IS 'Additional data specific to the activity type'; 