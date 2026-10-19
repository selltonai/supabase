-- KAN-322 FR-C8b: the smallest organization_settings for migration 409's contract. Disposable database only.
CREATE TABLE public.organization_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL UNIQUE,
  company_name text,
  default_campaign_language text DEFAULT 'en'
);
ALTER TABLE public.organization_settings ENABLE ROW LEVEL SECURITY;
INSERT INTO public.organization_settings (organization_id, company_name) VALUES ('org_a', 'Acme'), ('org_b', NULL);
