DO $$ 
BEGIN
    ALTER TYPE email_status ADD VALUE 'scheduled';
EXCEPTION 
    WHEN duplicate_object THEN 
        -- Value already exists, which is fine
        NULL; 
END $$;