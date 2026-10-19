-- Reverses 403 as far as it can. Not needed: every reader accepts both spellings (Modal ADMIN_ROLES,
-- selltonai fix/kan309-roles-credentials, backoffice fix/kan309-admin-role-spellings). Lossy: 403 kept no
-- record of which rows were stripped before, so this strips every admin and owner row. Run it only if a reader
-- that compares role = 'admin' has to be served again; it never touches org:member (the column default).
UPDATE public.user_organizations
SET role = replace(role, 'org:', '')
WHERE role IN ('org:admin', 'org:owner');
