-- Migration to update farm-specific lexical field categories to generic business categories
-- This migration maps old farm-specific categories to new generic business categories
-- and removes any custom categories, keeping only the predefined set

DO $$
DECLARE
    style_record RECORD;
    updated_lexical_fields JSONB;
    field_key TEXT;
    field_value JSONB;
    allowed_categories TEXT[] := ARRAY[
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
BEGIN
    -- Loop through all style guidelines records
    FOR style_record IN 
        SELECT id, key_word_choices_lexical_fields 
        FROM style_guidelines 
        WHERE key_word_choices_lexical_fields IS NOT NULL
    LOOP
        updated_lexical_fields := '{}';
        
        -- Map old farm-specific categories to new generic categories
        FOR field_key, field_value IN
            SELECT * FROM jsonb_each(style_record.key_word_choices_lexical_fields)
        LOOP
            CASE field_key
                WHEN 'farm_agrarian' THEN
                    updated_lexical_fields := updated_lexical_fields || jsonb_build_object('industry_specific', field_value);
                WHEN 'rural_locale' THEN
                    updated_lexical_fields := updated_lexical_fields || jsonb_build_object('brand_identity', field_value);
                WHEN 'natural_environment' THEN
                    updated_lexical_fields := updated_lexical_fields || jsonb_build_object('industry_specific', 
                        COALESCE(updated_lexical_fields->'industry_specific', '[]'::jsonb) || field_value);
                WHEN 'activity_fun' THEN
                    updated_lexical_fields := updated_lexical_fields || jsonb_build_object('customer_experience', field_value);
                WHEN 'group_experience' THEN
                    updated_lexical_fields := updated_lexical_fields || jsonb_build_object('customer_experience',
                        COALESCE(updated_lexical_fields->'customer_experience', '[]'::jsonb) || field_value);
                WHEN 'social_leisure' THEN
                    updated_lexical_fields := updated_lexical_fields || jsonb_build_object('customer_experience',
                        COALESCE(updated_lexical_fields->'customer_experience', '[]'::jsonb) || field_value);
                WHEN 'action_movement' THEN
                    updated_lexical_fields := updated_lexical_fields || jsonb_build_object('communication_style', field_value);
                WHEN 'dynamic_energy' THEN
                    updated_lexical_fields := updated_lexical_fields || jsonb_build_object('communication_style',
                        COALESCE(updated_lexical_fields->'communication_style', '[]'::jsonb) || field_value);
                WHEN 'fun_engagement' THEN
                    updated_lexical_fields := updated_lexical_fields || jsonb_build_object('communication_style',
                        COALESCE(updated_lexical_fields->'communication_style', '[]'::jsonb) || field_value);
                ELSE
                    -- Only keep categories that are in the allowed list
                    IF field_key = ANY(allowed_categories) THEN
                        updated_lexical_fields := updated_lexical_fields || jsonb_build_object(field_key, field_value);
                    ELSE
                        RAISE NOTICE 'Removing custom/unknown category: % for style guidelines ID: %', field_key, style_record.id;
                    END IF;
            END CASE;
        END LOOP;
        
        -- Update the record with the new lexical fields structure
        UPDATE style_guidelines 
        SET key_word_choices_lexical_fields = updated_lexical_fields
        WHERE id = style_record.id;
        
        RAISE NOTICE 'Updated lexical fields for style guidelines ID: %', style_record.id;
    END LOOP;
    
    RAISE NOTICE 'Lexical fields migration completed successfully. Only predefined categories are now allowed.';
END $$;