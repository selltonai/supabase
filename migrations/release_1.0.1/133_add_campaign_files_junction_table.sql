-- Migration: Create campaign_files junction table
-- Created: 2025-11-02
-- Purpose: Link campaigns with documents to enable campaign-specific document management
-- Description: Creates a junction table to associate organization_files with campaigns

-- Create campaign_files junction table
CREATE TABLE IF NOT EXISTS campaign_files (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id uuid NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
  file_id uuid NOT NULL REFERENCES organization_files(id) ON DELETE CASCADE,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  UNIQUE(campaign_id, file_id)
);

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_campaign_files_campaign_id ON campaign_files(campaign_id);
CREATE INDEX IF NOT EXISTS idx_campaign_files_file_id ON campaign_files(file_id);
CREATE INDEX IF NOT EXISTS idx_campaign_files_created_at ON campaign_files(created_at DESC);

-- Enable RLS
ALTER TABLE campaign_files ENABLE ROW LEVEL SECURITY;

-- Create RLS policies
-- Policy for authenticated users to view campaign files for their organization
CREATE POLICY "Users can view campaign files for their organization" ON campaign_files
    FOR SELECT
    USING (
      EXISTS (
        SELECT 1 FROM campaigns c
        WHERE c.id = campaign_files.campaign_id
        AND c.organization_id IN (
          SELECT organization_id FROM user_organizations
          WHERE user_id = auth.uid()::text
        )
      )
    );

-- Policy for authenticated users to insert campaign files for their organization
CREATE POLICY "Users can insert campaign files for their organization" ON campaign_files
    FOR INSERT
    WITH CHECK (
      EXISTS (
        SELECT 1 FROM campaigns c
        WHERE c.id = campaign_files.campaign_id
        AND c.organization_id IN (
          SELECT organization_id FROM user_organizations
          WHERE user_id = auth.uid()::text
        )
      )
    );

-- Policy for authenticated users to delete campaign files for their organization
CREATE POLICY "Users can delete campaign files for their organization" ON campaign_files
    FOR DELETE
    USING (
      EXISTS (
        SELECT 1 FROM campaigns c
        WHERE c.id = campaign_files.campaign_id
        AND c.organization_id IN (
          SELECT organization_id FROM user_organizations
          WHERE user_id = auth.uid()::text
        )
      )
    );

-- Add comments for documentation
COMMENT ON TABLE campaign_files IS 'Junction table linking campaigns with organization_files. Allows documents to be associated with specific campaigns for campaign-specific knowledge base use.';
COMMENT ON COLUMN campaign_files.campaign_id IS 'Reference to the campaign that uses this document';
COMMENT ON COLUMN campaign_files.file_id IS 'Reference to the organization file/document';

