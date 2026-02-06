-- Migration: Simplify Style Guidelines Table Structure
-- Description: Removes unused complex fields and keeps only essential fields for simplified brand guidelines
-- Author: System
-- Date: 2025-02-03

-- First, let's backup existing data by creating a temporary table
CREATE TABLE IF NOT EXISTS style_guidelines_backup AS 
SELECT * FROM style_guidelines;

-- Drop the existing style_guidelines table
DROP TABLE IF EXISTS style_guidelines CASCADE;

-- Create simplified style_guidelines table
CREATE TABLE style_guidelines (
    id SERIAL PRIMARY KEY,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()),
    organization_id TEXT NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
    
    -- Essential fields for Writing Assistant
    -- Brand Voice & Tone (simplified)
    brand_voice TEXT, -- Overall brand voice description
    tone_attributes TEXT[], -- Combined emotions and personality traits
    
    -- Key Vocabulary (simplified)
    key_phrases TEXT[], -- Important phrases to use
    avoid_phrases TEXT[], -- Phrases to avoid
    
    -- Writing Style & Audience (simplified)
    writing_style TEXT, -- General writing style description
    target_audience TEXT, -- Target audience description
    
    -- Keep minimal structure for backward compatibility
    -- These will be auto-populated from simplified fields
    tone_of_voice_sound TEXT,
    tone_of_voice_emotions TEXT[],
    tone_of_voice_personality_traits TEXT[],
    key_word_choices_lexical_fields JSONB DEFAULT '{}',
    key_word_choices_dictionary JSONB DEFAULT '[]',
    writing_style_formality TEXT,
    writing_style_sentence_voice TEXT
);

-- Create index for improved query performance
CREATE INDEX style_guidelines_organization_id_idx ON style_guidelines (organization_id);

-- Create unique constraint to ensure one style guide per organization
CREATE UNIQUE INDEX style_guidelines_organization_unique ON style_guidelines (organization_id);

-- Migrate data from backup to new simplified structure
INSERT INTO style_guidelines (
    id,
    created_at,
    organization_id,
    brand_voice,
    tone_attributes,
    key_phrases,
    avoid_phrases,
    writing_style,
    target_audience,
    -- Backward compatibility fields
    tone_of_voice_sound,
    tone_of_voice_emotions,
    tone_of_voice_personality_traits,
    key_word_choices_lexical_fields,
    key_word_choices_dictionary,
    writing_style_formality,
    writing_style_sentence_voice
)
SELECT 
    id,
    created_at,
    organization_id,
    -- Map to new simplified fields
    tone_of_voice_sound as brand_voice,
    -- Combine emotions and personality traits into tone_attributes
    ARRAY(
        SELECT DISTINCT unnest 
        FROM (
            SELECT unnest(tone_of_voice_emotions)
            UNION ALL
            SELECT unnest(tone_of_voice_personality_traits)
        ) AS combined
        WHERE unnest IS NOT NULL
    ) as tone_attributes,
    -- Extract all phrases from lexical fields as key_phrases
    ARRAY(
        SELECT DISTINCT value
        FROM jsonb_each(key_word_choices_lexical_fields) AS fields(key, values),
        LATERAL jsonb_array_elements_text(values) AS value
        WHERE value IS NOT NULL
    ) as key_phrases,
    -- Extract avoid terms from dictionary
    ARRAY(
        SELECT DISTINCT entry->>'term'
        FROM jsonb_array_elements(key_word_choices_dictionary) AS entry
        WHERE entry->>'category' IN ('avoid', 'negative', 'do_not_use')
    ) as avoid_phrases,
    -- Combine writing style fields
    COALESCE(
        writing_style_formality || ', ' || writing_style_sentence_voice,
        writing_style_formality,
        'professional'
    ) as writing_style,
    -- Extract target audience if it exists in lexical fields
    COALESCE(
        (key_word_choices_lexical_fields->>'target_audience')::text,
        ''
    ) as target_audience,
    -- Keep backward compatibility fields
    tone_of_voice_sound,
    tone_of_voice_emotions,
    tone_of_voice_personality_traits,
    key_word_choices_lexical_fields,
    key_word_choices_dictionary,
    writing_style_formality,
    writing_style_sentence_voice
FROM style_guidelines_backup;

-- Update the sequence to continue from the last ID
SELECT setval('style_guidelines_id_seq', COALESCE((SELECT MAX(id) FROM style_guidelines), 1));

-- Create trigger to update the updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = TIMEZONE('utc', NOW());
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_style_guidelines_updated_at
    BEFORE UPDATE ON style_guidelines
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Create simplified function to upsert style guidelines
CREATE OR REPLACE FUNCTION upsert_style_guidelines(
    p_organization_id TEXT,
    p_brand_voice TEXT DEFAULT NULL,
    p_tone_attributes TEXT[] DEFAULT NULL,
    p_key_phrases TEXT[] DEFAULT NULL,
    p_avoid_phrases TEXT[] DEFAULT NULL,
    p_writing_style TEXT DEFAULT NULL,
    p_target_audience TEXT DEFAULT NULL
) RETURNS style_guidelines AS $$
DECLARE
    v_result style_guidelines;
BEGIN
    INSERT INTO style_guidelines (
        organization_id,
        brand_voice,
        tone_attributes,
        key_phrases,
        avoid_phrases,
        writing_style,
        target_audience,
        -- Auto-populate backward compatibility fields
        tone_of_voice_sound,
        tone_of_voice_emotions,
        tone_of_voice_personality_traits,
        key_word_choices_lexical_fields,
        key_word_choices_dictionary,
        writing_style_formality,
        writing_style_sentence_voice
    ) VALUES (
        p_organization_id,
        p_brand_voice,
        p_tone_attributes,
        p_key_phrases,
        p_avoid_phrases,
        p_writing_style,
        p_target_audience,
        -- Backward compatibility mappings
        p_brand_voice,
        COALESCE(p_tone_attributes[1:array_length(p_tone_attributes, 1)/2], '{}'),
        COALESCE(p_tone_attributes[array_length(p_tone_attributes, 1)/2+1:], '{}'),
        jsonb_build_object(
            'brand_identity', to_jsonb(COALESCE(p_key_phrases[1:3], '{}')),
            'communication_style', to_jsonb(COALESCE(p_key_phrases[4:6], '{}')),
            'value_proposition', to_jsonb(COALESCE(p_key_phrases[7:], '{}'))
        ),
        CASE 
            WHEN p_avoid_phrases IS NOT NULL AND array_length(p_avoid_phrases, 1) > 0 THEN
                (SELECT jsonb_agg(
                    jsonb_build_object(
                        'term', phrase,
                        'category', 'avoid',
                        'example', 'Do not use "' || phrase || '" in communications'
                    )
                ) FROM unnest(p_avoid_phrases) AS phrase)
            ELSE '[]'::jsonb
        END,
        CASE 
            WHEN p_writing_style ILIKE '%formal%' THEN 'formal'
            WHEN p_writing_style ILIKE '%casual%' THEN 'casual'
            ELSE 'professional'
        END,
        CASE 
            WHEN p_writing_style ILIKE '%active%' THEN 'active'
            WHEN p_writing_style ILIKE '%passive%' THEN 'passive'
            ELSE 'balanced'
        END
    )
    ON CONFLICT (organization_id) 
    DO UPDATE SET
        brand_voice = EXCLUDED.brand_voice,
        tone_attributes = EXCLUDED.tone_attributes,
        key_phrases = EXCLUDED.key_phrases,
        avoid_phrases = EXCLUDED.avoid_phrases,
        writing_style = EXCLUDED.writing_style,
        target_audience = EXCLUDED.target_audience,
        tone_of_voice_sound = EXCLUDED.tone_of_voice_sound,
        tone_of_voice_emotions = EXCLUDED.tone_of_voice_emotions,
        tone_of_voice_personality_traits = EXCLUDED.tone_of_voice_personality_traits,
        key_word_choices_lexical_fields = EXCLUDED.key_word_choices_lexical_fields,
        key_word_choices_dictionary = EXCLUDED.key_word_choices_dictionary,
        writing_style_formality = EXCLUDED.writing_style_formality,
        writing_style_sentence_voice = EXCLUDED.writing_style_sentence_voice,
        updated_at = TIMEZONE('utc', NOW())
    RETURNING * INTO v_result;
    
    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- Drop the old update function
DROP FUNCTION IF EXISTS update_style_guidelines(TEXT, JSONB, JSONB, JSONB, JSONB);

-- Add helpful comments
COMMENT ON TABLE style_guidelines IS 'Simplified brand writing guidelines for AI-powered content generation';
COMMENT ON COLUMN style_guidelines.brand_voice IS 'Overall brand voice description (e.g., Professional yet approachable)';
COMMENT ON COLUMN style_guidelines.tone_attributes IS 'Key attributes describing brand tone (e.g., confident, empathetic, innovative)';
COMMENT ON COLUMN style_guidelines.key_phrases IS 'Important words and phrases to use in content';
COMMENT ON COLUMN style_guidelines.avoid_phrases IS 'Words and phrases to avoid in communications';
COMMENT ON COLUMN style_guidelines.writing_style IS 'General writing style description';
COMMENT ON COLUMN style_guidelines.target_audience IS 'Description of target audience';

-- Note: The backup table is kept for safety. It can be dropped later with:
-- DROP TABLE IF EXISTS style_guidelines_backup;