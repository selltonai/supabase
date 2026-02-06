-- Migration: Remove Custom Categories from Style Guidelines
-- Description: Ensures only fixed categories are used in lexical fields and dictionary
-- Author: System
-- Date: 2025-01-31

-- Function to clean up lexical fields to only include fixed categories
CREATE OR REPLACE FUNCTION cleanup_lexical_fields(fields JSONB) RETURNS JSONB AS $$
DECLARE
    fixed_categories text[] := ARRAY[
        'brand_identity',
        'product_service',
        'customer_experience',
        'professional_tone',
        'industry_specific',
        'value_proposition',
        'communication_style',
        'business_growth',
        'innovation_technology'
    ];
    result JSONB := '{}';
    key text;
    value JSONB;
BEGIN
    -- Iterate through existing fields
    FOR key, value IN SELECT * FROM jsonb_each(fields)
    LOOP
        -- Only keep fields that are in the fixed categories list
        IF key = ANY(fixed_categories) THEN
            result := result || jsonb_build_object(key, value);
        END IF;
    END LOOP;
    
    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Function to clean up dictionary entries to only use fixed categories
CREATE OR REPLACE FUNCTION cleanup_dictionary_entries(entries JSONB) RETURNS JSONB AS $$
DECLARE
    fixed_categories text[] := ARRAY[
        'General Terms',
        'Product Features',
        'Customer Benefits',
        'Industry Terms',
        'Value Propositions',
        'Technical Terms',
        'Business Terms'
    ];
    result JSONB := '[]';
    entry JSONB;
    category text;
BEGIN
    -- Iterate through existing entries
    FOR entry IN SELECT * FROM jsonb_array_elements(entries)
    LOOP
        category := entry->>'category';
        
        -- Only keep entries with valid categories
        IF category = ANY(fixed_categories) THEN
            result := result || jsonb_build_array(entry);
        ELSE
            -- Map custom categories to the most appropriate fixed category
            IF category ILIKE '%product%' OR category ILIKE '%feature%' THEN
                entry := jsonb_set(entry, '{category}', '"Product Features"');
            ELSIF category ILIKE '%customer%' OR category ILIKE '%benefit%' THEN
                entry := jsonb_set(entry, '{category}', '"Customer Benefits"');
            ELSIF category ILIKE '%industry%' OR category ILIKE '%business%' THEN
                entry := jsonb_set(entry, '{category}', '"Industry Terms"');
            ELSIF category ILIKE '%tech%' THEN
                entry := jsonb_set(entry, '{category}', '"Technical Terms"');
            ELSIF category ILIKE '%value%' OR category ILIKE '%proposition%' THEN
                entry := jsonb_set(entry, '{category}', '"Value Propositions"');
            ELSE
                entry := jsonb_set(entry, '{category}', '"General Terms"');
            END IF;
            result := result || jsonb_build_array(entry);
        END IF;
    END LOOP;
    
    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Update existing style guidelines to remove custom categories
UPDATE style_guidelines
SET 
    key_word_choices_lexical_fields = cleanup_lexical_fields(key_word_choices_lexical_fields),
    key_word_choices_dictionary = cleanup_dictionary_entries(key_word_choices_dictionary)
WHERE key_word_choices_lexical_fields IS NOT NULL 
   OR key_word_choices_dictionary IS NOT NULL;

-- Drop the cleanup functions as they're no longer needed
DROP FUNCTION IF EXISTS cleanup_lexical_fields(JSONB);
DROP FUNCTION IF EXISTS cleanup_dictionary_entries(JSONB);

-- Add a check constraint to ensure only valid categories are used (optional)
-- Note: This is commented out as JSONB check constraints can be complex
-- and might impact performance. The application layer will enforce this.
/*
ALTER TABLE style_guidelines 
ADD CONSTRAINT valid_lexical_categories CHECK (
    -- This would require a complex JSONB validation function
    true
);
*/ 