-- Create style_guidelines table with advanced structure
CREATE TABLE style_guidelines (
    id SERIAL PRIMARY KEY,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()),
    organization_id TEXT NOT NULL REFERENCES organization(id),
    -- Tone of voice
    tone_of_voice_sound TEXT NOT NULL,
    tone_of_voice_emotions TEXT[] NOT NULL,
    tone_of_voice_personality_traits TEXT[] NOT NULL,
    -- Key word choices
    key_word_choices_lexical_fields JSONB NOT NULL, -- { category: string[] }
    key_word_choices_dictionary JSONB NOT NULL,     -- [{ term, category, example }]
    -- Writing style
    writing_style_sentence_length TEXT NOT NULL,
    writing_style_sentence_complexity TEXT NOT NULL,
    writing_style_sentence_voice TEXT NOT NULL,
    writing_style_structural_devices TEXT[] NOT NULL,
    writing_style_formality TEXT NOT NULL,
    -- Narrative techniques
    narrative_techniques_hooks TEXT[] NOT NULL,
    narrative_techniques_rhetorical_devices TEXT[] NOT NULL,
    narrative_techniques_social_proof TEXT[] NOT NULL
);

-- Create index for improved query performance
CREATE INDEX style_guidelines_organization_id_idx ON style_guidelines (organization_id);

-- Add a function to update the style guidelines
CREATE OR REPLACE FUNCTION update_style_guidelines(
    org_id TEXT,
    tone JSONB,
    keywords JSONB,
    style JSONB,
    narratives JSONB
) RETURNS VOID AS $$
BEGIN
    -- Check if record exists
    IF EXISTS (SELECT 1 FROM style_guidelines WHERE organization_id = org_id) THEN
        -- Update existing record
        UPDATE style_guidelines
        SET 
            tone_of_voice = tone,
            key_word_choices = keywords,
            writing_style = style,
            narrative_techniques = narratives,
            created_at = NOW()
        WHERE organization_id = org_id;
    ELSE
        -- Insert new record
        INSERT INTO style_guidelines (
            organization_id,
            tone_of_voice,
            key_word_choices,
            writing_style,
            narrative_techniques
        ) VALUES (
            org_id,
            tone,
            keywords,
            style,
            narratives
        );
    END IF;
END;
$$ LANGUAGE plpgsql; 