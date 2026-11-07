-- Reverses 418. The Modal code tolerates the missing tables (it logs and goes on): the Monday job then writes no
-- report row and no outcome table, the writer's frame choice stays as before, and the app's card shows no report.
DROP TABLE IF EXISTS public.learning_frame_outcomes;
DROP TABLE IF EXISTS public.learning_reports;
