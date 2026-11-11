-- Reverses 431: removes the two Signals labels of the web app's Brain signal services. The phone's mobile_signals row
-- (396) stays.
DELETE FROM public.action_label_map
WHERE provider = '' AND model_name_pattern = '' AND requires_grounding = false AND task_key = 'signals'
  AND service_name IN ('brain_signals', 'brain_signal_router');
