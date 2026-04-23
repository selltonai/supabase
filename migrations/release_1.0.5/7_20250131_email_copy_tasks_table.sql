-- CREATE EMAIL COPY TASKS TABLE
-- Run this ENTIRE script in your Supabase SQL Editor

-- Step 1: Create the table with CORRECT UUID types
CREATE TABLE IF NOT EXISTS email_copy_tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id TEXT NOT NULL,
    contact_id UUID NOT NULL,
    company_id UUID NOT NULL,
    campaign_id UUID NOT NULL,
    thread_id TEXT,
    subject TEXT,
    reasoning_note TEXT,
    body TEXT,
    priority TEXT NOT NULL DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'in_review', 'approved', 'rejected', 'sent')),
    send_status TEXT DEFAULT 'not_sent' CHECK (send_status IN ('not_sent', 'sending', 'sent_success', 'sent_failed')),
    send_error_message TEXT,
    sent_at TIMESTAMP WITH TIME ZONE,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Step 2: Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_email_copy_tasks_organization_id ON email_copy_tasks(organization_id);
CREATE INDEX IF NOT EXISTS idx_email_copy_tasks_contact_id ON email_copy_tasks(contact_id);
CREATE INDEX IF NOT EXISTS idx_email_copy_tasks_company_id ON email_copy_tasks(company_id);
CREATE INDEX IF NOT EXISTS idx_email_copy_tasks_campaign_id ON email_copy_tasks(campaign_id);
CREATE INDEX IF NOT EXISTS idx_email_copy_tasks_status ON email_copy_tasks(status);
CREATE INDEX IF NOT EXISTS idx_email_copy_tasks_priority ON email_copy_tasks(priority);
CREATE INDEX IF NOT EXISTS idx_email_copy_tasks_send_status ON email_copy_tasks(send_status);
CREATE INDEX IF NOT EXISTS idx_email_copy_tasks_created_at ON email_copy_tasks(created_at);

-- Step 3: Create composite indexes for common queries
CREATE INDEX IF NOT EXISTS idx_email_copy_tasks_org_status ON email_copy_tasks(organization_id, status);
CREATE INDEX IF NOT EXISTS idx_email_copy_tasks_org_priority ON email_copy_tasks(organization_id, priority);
CREATE INDEX IF NOT EXISTS idx_email_copy_tasks_org_send_status ON email_copy_tasks(organization_id, send_status);
CREATE INDEX IF NOT EXISTS idx_email_copy_tasks_org_created ON email_copy_tasks(organization_id, created_at);

-- Step 4: Enable Row Level Security (RLS)
ALTER TABLE email_copy_tasks ENABLE ROW LEVEL SECURITY;

-- Step 5: Create RLS policies
-- Policy for users to see only their organization's tasks
CREATE POLICY "Users can view their organization's email copy tasks" ON email_copy_tasks
    FOR SELECT USING (organization_id = current_setting('app.organization_id', true)::text);

-- Policy for users to insert tasks for their organization
CREATE POLICY "Users can insert email copy tasks for their organization" ON email_copy_tasks
    FOR INSERT WITH CHECK (organization_id = current_setting('app.organization_id', true)::text);

-- Policy for users to update their organization's tasks
CREATE POLICY "Users can update their organization's email copy tasks" ON email_copy_tasks
    FOR UPDATE USING (organization_id = current_setting('app.organization_id', true)::text);

-- Policy for users to delete their organization's tasks
CREATE POLICY "Users can delete their organization's email copy tasks" ON email_copy_tasks
    FOR DELETE USING (organization_id = current_setting('app.organization_id', true)::text);

-- Step 6: Create trigger function for updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Step 7: Create trigger to automatically update updated_at
CREATE TRIGGER update_email_copy_tasks_updated_at 
    BEFORE UPDATE ON email_copy_tasks 
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();

-- Step 8: Add comments for documentation
COMMENT ON TABLE email_copy_tasks IS 'Stores email copy tasks for review and approval workflow';
COMMENT ON COLUMN email_copy_tasks.id IS 'Unique identifier for the task';
COMMENT ON COLUMN email_copy_tasks.organization_id IS 'Organization that owns this task';
COMMENT ON COLUMN email_copy_tasks.contact_id IS 'UUID of the contact this email is for';
COMMENT ON COLUMN email_copy_tasks.company_id IS 'UUID of the company this email is for';
COMMENT ON COLUMN email_copy_tasks.campaign_id IS 'UUID of the campaign this email belongs to';
COMMENT ON COLUMN email_copy_tasks.thread_id IS 'Email thread ID for conversation history';
COMMENT ON COLUMN email_copy_tasks.subject IS 'Email subject line';
COMMENT ON COLUMN email_copy_tasks.reasoning_note IS 'Reasoning for the email content';
COMMENT ON COLUMN email_copy_tasks.body IS 'Email body content';
COMMENT ON COLUMN email_copy_tasks.priority IS 'Task priority level';
COMMENT ON COLUMN email_copy_tasks.status IS 'Current status of the task';
COMMENT ON COLUMN email_copy_tasks.send_status IS 'Status of sending to external API';
COMMENT ON COLUMN email_copy_tasks.send_error_message IS 'Error message if sending failed';
COMMENT ON COLUMN email_copy_tasks.sent_at IS 'Timestamp when email was sent';
COMMENT ON COLUMN email_copy_tasks.metadata IS 'Additional metadata as JSON';
COMMENT ON COLUMN email_copy_tasks.created_at IS 'Timestamp when task was created';
COMMENT ON COLUMN email_copy_tasks.updated_at IS 'Timestamp when task was last updated';

-- Step 9: Verify the table was created correctly
SELECT 
    'Table created successfully' as status,
    COUNT(*) as column_count
FROM information_schema.columns 
WHERE table_name = 'email_copy_tasks';

-- Step 10: Show the table structure
SELECT 
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns 
WHERE table_name = 'email_copy_tasks'
ORDER BY ordinal_position;