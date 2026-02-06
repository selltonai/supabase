-- Migration: Add deleted flag to organization table
-- Description: Adds a deleted boolean flag to track when organizations are deleted from Clerk
-- Author: System
-- Date: 2025-01-XX

-- Add deleted column to organization table
ALTER TABLE organization 
  ADD COLUMN IF NOT EXISTS deleted BOOLEAN NOT NULL DEFAULT false;

-- Create index for efficient queries filtering by deleted status
CREATE INDEX IF NOT EXISTS idx_organization_deleted ON organization(deleted);

-- Add comment for documentation
COMMENT ON COLUMN organization.deleted IS 'Flag to mark organization as deleted (set to true when organization is deleted from Clerk, instead of hard deleting the record)';
