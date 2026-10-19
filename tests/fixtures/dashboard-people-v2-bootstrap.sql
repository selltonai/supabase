-- KAN-322 FR-A11g contract bootstrap: the columns 407 reads beyond 387's (contacts.linkedin_provider_id, 365).
-- Disposable database only.
CREATE TABLE IF NOT EXISTS public.contacts (id uuid PRIMARY KEY, organization_id text NOT NULL, linkedin_provider_id text);
