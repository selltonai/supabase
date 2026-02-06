-- Campaign emails performance
CREATE INDEX IF NOT EXISTS idx_campaign_emails_campaign_id ON campaign_emails(campaign_id);
CREATE INDEX IF NOT EXISTS idx_campaign_emails_sent_at ON campaign_emails(sent_at);
CREATE INDEX IF NOT EXISTS idx_campaign_emails_status ON campaign_emails(status);

-- Campaign activities performance  
CREATE INDEX IF NOT EXISTS idx_campaign_activities_campaign_id ON campaign_activities(campaign_id);
CREATE INDEX IF NOT EXISTS idx_campaign_activities_occurred_at ON campaign_activities(occurred_at);

-- Campaign companies performance
CREATE INDEX IF NOT EXISTS idx_campaign_companies_campaign_id ON campaign_companies(campaign_id);
