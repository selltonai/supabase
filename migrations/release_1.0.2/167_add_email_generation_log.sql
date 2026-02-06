-- Add comprehensive email generation logging to email_copy_tasks table
-- This tracks all steps, inputs, outputs, models used, and data used during email generation
-- Similar to the processing_log system used for ICP scoring

-- Add generation_log JSONB column to store comprehensive logging data
ALTER TABLE email_copy_tasks 
ADD COLUMN IF NOT EXISTS generation_log JSONB DEFAULT '{}'::jsonb;

-- Add index for querying by generation log data
CREATE INDEX IF NOT EXISTS idx_email_copy_tasks_generation_log 
ON email_copy_tasks USING GIN (generation_log);

-- Add comment explaining the structure
COMMENT ON COLUMN email_copy_tasks.generation_log IS 'Comprehensive logging of email generation process including all steps, inputs, outputs, models used, templates, context data, and any errors. Structure: {generation_started_at, generation_completed_at, steps: [{step, status, timestamp, input_data, output_data, model_used, template_used, error}], final_status, campaign_data_used, company_data_used, contact_data_used, strategic_reasoning_input, strategic_reasoning_output, email_generation_input, email_generation_output}';




