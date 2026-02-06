CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX IF NOT EXISTS idx_contacts_organization_id ON contacts (organization_id);
CREATE INDEX IF NOT EXISTS idx_contacts_created_at ON contacts (created_at);
CREATE INDEX IF NOT EXISTS idx_contacts_email ON contacts (email);
CREATE INDEX IF NOT EXISTS idx_contacts_search_gin ON contacts USING gin (name gin_trgm_ops, email gin_trgm_ops, firstname gin_trgm_ops, lastname gin_trgm_ops, headline gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_contacts_location_gin ON contacts USING gin (location);
CREATE INDEX IF NOT EXISTS idx_contacts_analysis_gin ON contacts USING gin (analysis);

-- Indexes for tasks table
CREATE INDEX IF NOT EXISTS idx_tasks_organization_id ON tasks (organization_id);
CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks (status);
CREATE INDEX IF NOT EXISTS idx_tasks_task_type ON tasks (task_type);
CREATE INDEX IF NOT EXISTS idx_tasks_contact_id ON tasks (contact_id);
CREATE INDEX IF NOT EXISTS idx_tasks_campaign_id ON tasks (campaign_id);
CREATE INDEX IF NOT EXISTS idx_tasks_company_id ON tasks (company_id);
CREATE INDEX IF NOT EXISTS idx_tasks_company_id_created_at ON tasks (company_id, created_at DESC);

-- Indexes for companies table
CREATE INDEX IF NOT EXISTS idx_companies_organization_id ON companies (organization_id);
CREATE INDEX IF NOT EXISTS idx_companies_search_gin ON companies USING gin (name gin_trgm_ops, location gin_trgm_ops, description gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_companies_industries_gin ON companies USING gin (industries);
CREATE INDEX IF NOT EXISTS idx_companies_employee_count ON companies (employee_count);
CREATE INDEX IF NOT EXISTS idx_companies_website ON companies (website);
CREATE INDEX IF NOT EXISTS idx_companies_created_at ON companies (created_at);
CREATE INDEX IF NOT EXISTS idx_companies_used_for_outreach ON companies (used_for_outreach);
CREATE INDEX IF NOT EXISTS idx_companies_processing_simple_status ON companies (processing_simple_status);

-- Indexes for organization_settings table
CREATE INDEX IF NOT EXISTS idx_organization_settings_organization_id ON organization_settings (organization_id);

-- Indexes for organization_icp_linkedin_urls table
CREATE INDEX IF NOT EXISTS idx_organization_icp_linkedin_urls_organization_id ON organization_icp_linkedin_urls (organization_id);

-- Indexes for style_guidelines table
CREATE INDEX IF NOT EXISTS idx_style_guidelines_organization_id ON style_guidelines (organization_id);

-- Indexes for user_organizations table
CREATE INDEX IF NOT EXISTS idx_user_organizations_user_id ON user_organizations (user_id);
CREATE INDEX IF NOT EXISTS idx_user_organizations_organization_id ON user_organizations (organization_id);
