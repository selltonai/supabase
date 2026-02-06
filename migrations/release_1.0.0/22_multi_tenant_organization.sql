-- Create user_organizations join table
CREATE TABLE user_organizations (
    user_id TEXT NOT NULL REFERENCES "user"(id),
    organization_id TEXT NOT NULL REFERENCES organization(id),
    PRIMARY KEY (user_id, organization_id)
);

-- Populate user_organizations from existing user data
-- This assumes that the existing organization_id in the user table
-- is the one we want to keep for now.
-- You might need to adjust this logic based on your specific data migration needs.
INSERT INTO user_organizations (user_id, organization_id)
SELECT id, organization_id FROM "user" WHERE organization_id IS NOT NULL;

-- Remove organization_id column from user table
ALTER TABLE "user" DROP COLUMN organization_id;

-- Add new indexes
CREATE INDEX user_organizations_user_id_idx ON user_organizations (user_id);
CREATE INDEX user_organizations_organization_id_idx ON user_organizations (organization_id); 