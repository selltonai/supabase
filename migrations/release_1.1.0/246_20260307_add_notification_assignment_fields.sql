-- Migration: Add assignment metadata required by the notification system
-- Date: 2026-03-07

ALTER TABLE user_organizations
    ADD COLUMN IF NOT EXISTS role TEXT;

UPDATE user_organizations
SET role = COALESCE(role, 'org:member')
WHERE role IS NULL;

ALTER TABLE user_organizations
    ALTER COLUMN role SET DEFAULT 'org:member';

CREATE INDEX IF NOT EXISTS idx_user_organizations_org_role
    ON user_organizations(organization_id, role);

ALTER TABLE contacts
    ADD COLUMN IF NOT EXISTS assigned_to_user_id TEXT REFERENCES "user"(id) ON DELETE SET NULL;

UPDATE contacts
SET assigned_to_user_id = user_id
WHERE assigned_to_user_id IS NULL
  AND user_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_contacts_assigned_to_user_id
    ON contacts(assigned_to_user_id);

CREATE OR REPLACE FUNCTION sync_contacts_assigned_to_user_id()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.assigned_to_user_id IS NULL THEN
        NEW.assigned_to_user_id = NEW.user_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS sync_contacts_assigned_to_user_id_trigger ON contacts;
CREATE TRIGGER sync_contacts_assigned_to_user_id_trigger
    BEFORE INSERT OR UPDATE ON contacts
    FOR EACH ROW
    EXECUTE FUNCTION sync_contacts_assigned_to_user_id();

ALTER TABLE companies
    ADD COLUMN IF NOT EXISTS assigned_to_user_id TEXT REFERENCES "user"(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_companies_assigned_to_user_id
    ON companies(assigned_to_user_id);

ALTER TABLE tasks
    ADD COLUMN IF NOT EXISTS assigned_to_user_id TEXT REFERENCES "user"(id) ON DELETE SET NULL;

UPDATE tasks
SET assigned_to_user_id = created_by_user_id
WHERE assigned_to_user_id IS NULL
  AND created_by_user_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_tasks_assigned_to_user_id
    ON tasks(assigned_to_user_id);

CREATE OR REPLACE FUNCTION sync_tasks_assigned_to_user_id()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.assigned_to_user_id IS NULL THEN
        NEW.assigned_to_user_id = NEW.created_by_user_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS sync_tasks_assigned_to_user_id_trigger ON tasks;
CREATE TRIGGER sync_tasks_assigned_to_user_id_trigger
    BEFORE INSERT OR UPDATE ON tasks
    FOR EACH ROW
    EXECUTE FUNCTION sync_tasks_assigned_to_user_id();
