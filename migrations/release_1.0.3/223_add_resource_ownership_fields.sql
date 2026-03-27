-- Migration: Add assigned_to_user_id fields for resource ownership
-- Description: Adds assigned_to_user_id fields to contacts, companies, and tasks tables
--              to implement resource ownership and assignment functionality

-- Add assigned_to_user_id to contacts table
ALTER TABLE contacts ADD COLUMN assigned_to_user_id text REFERENCES "user"(id) ON DELETE SET NULL;

-- Add assigned_to_user_id to companies table
ALTER TABLE companies ADD COLUMN assigned_to_user_id text REFERENCES "user"(id) ON DELETE SET NULL;

-- Add assigned_to_user_id to tasks table
ALTER TABLE tasks ADD COLUMN assigned_to_user_id text REFERENCES "user"(id) ON DELETE SET NULL;

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_contacts_assigned_to_user_id ON contacts(organization_id, assigned_to_user_id) WHERE assigned_to_user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_companies_assigned_to_user_id ON companies(organization_id, assigned_to_user_id) WHERE assigned_to_user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_tasks_assigned_to_user_id ON tasks(organization_id, assigned_to_user_id) WHERE assigned_to_user_id IS NOT NULL;
