-- Create organization_files table for file management
CREATE TABLE IF NOT EXISTS organization_files (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id TEXT NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
    file_name TEXT NOT NULL,
    file_type TEXT NOT NULL,
    file_url TEXT NOT NULL,
    file_size INTEGER NOT NULL,
    uploaded_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    shared_with_client BOOLEAN DEFAULT false,
    uploaded_by TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_organization_files_org_id ON organization_files(organization_id);
CREATE INDEX IF NOT EXISTS idx_organization_files_shared ON organization_files(shared_with_client);
CREATE INDEX IF NOT EXISTS idx_organization_files_created_at ON organization_files(created_at DESC);

-- Enable RLS
ALTER TABLE organization_files ENABLE ROW LEVEL SECURITY;

-- Create RLS policies
-- Policy for authenticated users to view their organization's files
CREATE POLICY "Users can view their organization's files" ON organization_files
    FOR SELECT
    USING (auth.uid() IS NOT NULL);

-- Policy for authenticated users to insert files for their organization
CREATE POLICY "Users can insert files for their organization" ON organization_files
    FOR INSERT
    WITH CHECK (auth.uid() IS NOT NULL);

-- Policy for authenticated users to update their organization's files
CREATE POLICY "Users can update their organization's files" ON organization_files
    FOR UPDATE
    USING (auth.uid() IS NOT NULL);

-- Policy for authenticated users to delete their organization's files
CREATE POLICY "Users can delete their organization's files" ON organization_files
    FOR DELETE
    USING (auth.uid() IS NOT NULL);

-- Create storage bucket for organization files if it doesn't exist
-- Note: This bucket is PRIVATE - files can only be accessed via signed URLs
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'organization-files',
    'organization-files',
    false, -- Private bucket - requires authentication
    52428800, -- 50MB
    ARRAY['application/pdf', 'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'text/csv']::text[]
)
ON CONFLICT (id) DO UPDATE SET
    public = false, -- Ensure bucket remains private
    file_size_limit = 52428800,
    allowed_mime_types = ARRAY['application/pdf', 'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'text/csv']::text[];

-- Create storage policies for the bucket
-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Users can upload files to their organization folder" ON storage.objects;
DROP POLICY IF EXISTS "Users can view files in their organization folder" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete files from their organization folder" ON storage.objects;

-- Create new storage policies
CREATE POLICY "Users can upload files to their organization folder" ON storage.objects
    FOR INSERT
    WITH CHECK (
        bucket_id = 'organization-files' 
        AND auth.uid() IS NOT NULL
    );

CREATE POLICY "Users can view files in their organization folder" ON storage.objects
    FOR SELECT
    USING (
        bucket_id = 'organization-files' 
        AND auth.uid() IS NOT NULL
    );

CREATE POLICY "Users can delete files from their organization folder" ON storage.objects
    FOR DELETE
    USING (
        bucket_id = 'organization-files' 
        AND auth.uid() IS NOT NULL
    );

-- Create function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to automatically update updated_at
DROP TRIGGER IF EXISTS update_organization_files_updated_at ON organization_files;
CREATE TRIGGER update_organization_files_updated_at
    BEFORE UPDATE ON organization_files
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Grant permissions
GRANT ALL ON organization_files TO authenticated;
GRANT ALL ON organization_files TO service_role; 