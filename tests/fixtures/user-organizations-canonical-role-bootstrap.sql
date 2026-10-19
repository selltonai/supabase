-- KAN-309 / KAN-283 P0a contract bootstrap: only what migration 403 touches. Disposable database only.
CREATE TABLE public.user_organizations (
  user_id text NOT NULL,
  organization_id text NOT NULL,
  role text DEFAULT 'org:member',
  PRIMARY KEY (user_id, organization_id)
);
CREATE INDEX idx_user_organizations_org_role ON public.user_organizations (organization_id, role);
-- Every spelling seen on prod and stage (2026-10-15) plus the edge cases the UPDATEs must handle.
INSERT INTO public.user_organizations (user_id, organization_id, role) VALUES
  ('u_admin', 'org_a', 'admin'),
  ('u_member', 'org_a', 'member'),
  ('u_owner', 'org_a', 'owner'),
  ('u_padded', 'org_a', ' Admin '),
  ('u_upper', 'org_a', 'ORG:Admin'),
  ('u_clerk_admin', 'org_a', 'org:admin'),
  ('u_clerk_member', 'org_a', 'org:member'),
  ('u_clerk_owner', 'org_b', 'org:owner'),
  ('u_null', 'org_b', NULL),
  ('u_empty', 'org_b', ''),
  ('u_unknown', 'org_b', 'basic_member');
