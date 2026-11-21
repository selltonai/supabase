-- Reverses 450: the index and the two columns are dropped, so no person is held for a signal any more and every held
-- person is back in their play at the next tick. The Modal and app readers treat the missing columns as no hold (a
-- failed read is logged and holds nobody), so they may stay live; the Modal writer logs a failed hold write and then
-- makes no signal draft for a person in a running play (the 2a task "Outside the topic" comes instead).
SET LOCAL lock_timeout = '10s';

DROP INDEX IF EXISTS public.idx_contacts_signal_hold_until;

ALTER TABLE public.contacts
  DROP COLUMN IF EXISTS signal_hold_reason,
  DROP COLUMN IF EXISTS signal_hold_until;
