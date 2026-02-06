-- =====================================================
-- Migration: Create document_short_urls table
-- Description: Short URL system for document sharing (like bit.ly)
-- Author: AI Assistant
-- Date: 2025-12-14
-- =====================================================

-- Create document_short_urls table
CREATE TABLE IF NOT EXISTS public.document_short_urls (
    -- Primary key
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Short code (e.g., "xK9mP2" - 6 characters, alphanumeric)
    short_code TEXT NOT NULL UNIQUE,
    
    -- Organization and file details
    organization_id TEXT NOT NULL,
    file_id UUID NOT NULL,
    file_name TEXT NOT NULL,
    file_category TEXT,
    
    -- 👤 Contact tracking (who this was shared with)
    contact_id UUID,  -- If shared with specific contact
    campaign_id UUID,  -- If shared as part of campaign
    shared_via TEXT,  -- "email", "manual_share", "link_copy"
    
    -- Expiration (30 days default, can be extended)
    expires_at TIMESTAMPTZ NOT NULL,
    
    -- Usage tracking
    access_count INTEGER DEFAULT 0,
    last_accessed_at TIMESTAMPTZ,
    first_accessed_at TIMESTAMPTZ,
    
    -- Metadata
    created_at TIMESTAMPTZ DEFAULT NOW(),
    created_by TEXT,
    
    -- Constraints
    CONSTRAINT fk_organization 
        FOREIGN KEY (organization_id) 
        REFERENCES public.organization(id) 
        ON DELETE CASCADE,
    
    CONSTRAINT fk_contact
        FOREIGN KEY (contact_id)
        REFERENCES public.contacts(id)
        ON DELETE SET NULL
);

-- Create document_access_events table (detailed tracking)
CREATE TABLE IF NOT EXISTS public.document_access_events (
    -- Primary key
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Link to short URL
    short_url_id UUID NOT NULL,
    short_code TEXT NOT NULL,
    
    -- Who accessed
    contact_id UUID,  -- If known
    organization_id TEXT NOT NULL,
    
    -- What happened
    event_type TEXT NOT NULL,  -- "opened", "downloaded", "viewed"
    file_id UUID NOT NULL,
    file_name TEXT,
    
    -- When and where
    accessed_at TIMESTAMPTZ DEFAULT NOW(),
    ip_address TEXT,
    user_agent TEXT,
    referrer TEXT,
    
    -- Session info
    session_id TEXT,
    duration_seconds INTEGER,  -- How long they viewed
    
    -- Metadata
    metadata JSONB DEFAULT '{}'::jsonb,
    
    -- Constraints
    CONSTRAINT fk_short_url
        FOREIGN KEY (short_url_id)
        REFERENCES public.document_short_urls(id)
        ON DELETE CASCADE,
    
    CONSTRAINT fk_contact_event
        FOREIGN KEY (contact_id)
        REFERENCES public.contacts(id)
        ON DELETE SET NULL
);

-- Indexes for document_short_urls
CREATE INDEX IF NOT EXISTS idx_short_urls_short_code 
    ON public.document_short_urls(short_code);

CREATE INDEX IF NOT EXISTS idx_short_urls_organization 
    ON public.document_short_urls(organization_id);

CREATE INDEX IF NOT EXISTS idx_short_urls_file_id 
    ON public.document_short_urls(file_id);

CREATE INDEX IF NOT EXISTS idx_short_urls_contact 
    ON public.document_short_urls(contact_id);

CREATE INDEX IF NOT EXISTS idx_short_urls_expires_at 
    ON public.document_short_urls(expires_at);

-- Indexes for document_access_events
CREATE INDEX IF NOT EXISTS idx_access_events_short_url 
    ON public.document_access_events(short_url_id);

CREATE INDEX IF NOT EXISTS idx_access_events_contact 
    ON public.document_access_events(contact_id);

CREATE INDEX IF NOT EXISTS idx_access_events_org 
    ON public.document_access_events(organization_id);

CREATE INDEX IF NOT EXISTS idx_access_events_accessed_at 
    ON public.document_access_events(accessed_at DESC);

CREATE INDEX IF NOT EXISTS idx_access_events_event_type 
    ON public.document_access_events(event_type);

-- Enable Row Level Security
ALTER TABLE public.document_short_urls ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_access_events ENABLE ROW LEVEL SECURITY;

-- RLS Policies for document_short_urls
CREATE POLICY "Users can view short URLs for their organization"
    ON public.document_short_urls
    FOR SELECT
    USING (
        organization_id IN (
            SELECT id FROM public.organization
            WHERE id = organization_id
        )
    );

CREATE POLICY "Service role has full access to short URLs"
    ON public.document_short_urls
    FOR ALL
    USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');

-- RLS Policies for document_access_events
CREATE POLICY "Users can view access events for their organization"
    ON public.document_access_events
    FOR SELECT
    USING (
        organization_id IN (
            SELECT id FROM public.organization
            WHERE id = organization_id
        )
    );

CREATE POLICY "Service role has full access to access events"
    ON public.document_access_events
    FOR ALL
    USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');

-- Comments for documentation
COMMENT ON TABLE public.document_short_urls IS 'Short URL mappings for document sharing (like bit.ly) - replaces long JWT tokens with short codes';
COMMENT ON COLUMN public.document_short_urls.short_code IS 'Short alphanumeric code (e.g., "xK9mP2") - 6 characters, URL-safe';
COMMENT ON COLUMN public.document_short_urls.contact_id IS 'Contact this document was shared with (for tracking)';
COMMENT ON COLUMN public.document_short_urls.shared_via IS 'How it was shared: "email", "manual_share", "link_copy"';
COMMENT ON COLUMN public.document_short_urls.expires_at IS 'Expiration timestamp - default 30 days, extended to 90 days for case studies';
COMMENT ON COLUMN public.document_short_urls.access_count IS 'Total number of times this short URL was accessed';

COMMENT ON TABLE public.document_access_events IS 'Detailed tracking of every document access - who opened, when, for how long';
COMMENT ON COLUMN public.document_access_events.event_type IS 'Event type: "opened" (link clicked), "downloaded" (file downloaded), "viewed" (page viewed)';
COMMENT ON COLUMN public.document_access_events.duration_seconds IS 'How long the document was viewed (if tracked by frontend)';
COMMENT ON COLUMN public.document_access_events.session_id IS 'Browser session ID for tracking multiple events from same visit';

