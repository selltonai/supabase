-- KAN-305 A4: retain AI Ark professional fields with separate provenance.
-- Producer: selltonai-modal AI Ark mapping (A1/A2).
-- Consumers: LinkedIn context (A3), future review warnings (A5), contact UI.
-- Apply before deploying the backend mapping. No auth/RLS or existing column changes.
ALTER TABLE public.contacts ADD COLUMN IF NOT EXISTS professional_summary jsonb DEFAULT '{}'::jsonb;

COMMENT ON COLUMN public.contacts.professional_summary IS
    'AI Ark professional facts from A1/A2: department, seniority, function, tenure months, source, fetched_at; durations use provider snapshot as_of. Read by LinkedIn context A3 and review features A5. Separate from LLM analysis and Unipile linkedin_profile.';
