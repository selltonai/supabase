-- Add new activity types for email workflow
ALTER TYPE activity_type ADD VALUE IF NOT EXISTS 'email_draft_created';
ALTER TYPE activity_type ADD VALUE IF NOT EXISTS 'email_reply_sent';
ALTER TYPE activity_type ADD VALUE IF NOT EXISTS 'campaign_added'; 