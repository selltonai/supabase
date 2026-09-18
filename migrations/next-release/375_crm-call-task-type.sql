-- KAN-305: dedicated human call task type. Affected: selltonai, selltonai-modal.
-- Commit before 376 references this enum value. Existing migrations immutable.
ALTER TYPE public.task_type ADD VALUE IF NOT EXISTS 'call';
