-- Migration: Add conversation_summary column to tasks table
-- Created: 2025-12-13
-- Purpose: Store conversation context, answered/unanswered questions, and thread state
-- This enables better task consolidation and context preservation

-- Add conversation_summary JSONB column to tasks table (for structured queries)
ALTER TABLE public.tasks 
ADD COLUMN IF NOT EXISTS conversation_summary JSONB DEFAULT '{}'::jsonb;

-- Add conversation_summary_text TEXT column (for frontend display)
ALTER TABLE public.tasks 
ADD COLUMN IF NOT EXISTS conversation_summary_text TEXT;

-- Add helpful comment explaining the JSONB structure
COMMENT ON COLUMN public.tasks.conversation_summary IS 
'Stores conversation context including:
{
  "thread_id": "string",
  "topic": "string - what the conversation is about",
  "total_messages": number,
  "our_messages_count": number,
  "their_messages_count": number,
  "last_our_reply_at": "timestamp",
  "answered_questions": [
    {
      "question": "What is Sellton?",
      "answer": "Sellton is an autonomous...",
      "answered_at": "2025-12-13T..."
    }
  ],
  "unanswered_questions": ["Who is in your team?"],
  "current_intents": ["inquiry", "booking", "follow_up"],
  "scheduling_status": "slots_provided | waiting | booked | none",
  "last_updated": "timestamp"
}

NOTE: current_intents is an ARRAY to support multiple simultaneous intents.
Example: ["inquiry", "booking"] when user asks questions AND wants to schedule.';

-- Add comment for text field
COMMENT ON COLUMN public.tasks.conversation_summary_text IS 
'Human-readable conversation summary for frontend display. Example:
"Discussed Sellton product features and scheduling. User asked about team size, company history, and use cases. We answered all questions and provided meeting slots for Dec 22-24. Waiting for time confirmation."';

-- Create index for faster queries by thread_id in summary
CREATE INDEX IF NOT EXISTS idx_tasks_conversation_summary_thread_id 
ON public.tasks USING gin ((conversation_summary->'thread_id'));

-- Create index for tasks with unanswered questions
CREATE INDEX IF NOT EXISTS idx_tasks_unanswered_questions 
ON public.tasks USING gin ((conversation_summary->'unanswered_questions'));

-- Create full-text search index on summary text for frontend search
CREATE INDEX IF NOT EXISTS idx_tasks_conversation_summary_text_search 
ON public.tasks USING gin (to_tsvector('english', conversation_summary_text));

