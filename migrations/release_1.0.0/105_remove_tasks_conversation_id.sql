   -- Remove the conversation_id column from tasks table
   ALTER TABLE tasks DROP COLUMN IF EXISTS conversation_id;
   
   -- Remove the index on conversation_id (if it exists)
   DROP INDEX IF EXISTS idx_tasks_conversation_id;