-- ============================================================
-- Migration: 450_contacts-signal-hold
-- Date:      2026-11-21
-- Purpose:   Signals S5, phase 5 (PLAN_SIGNALS_FIND_PEOPLE_BILLING_AND_FIND_A_NUMBER_2026_11_21 section 6, S5;
--            PLAN_SIGNALS_WORKING_PLAN_2026_11_19 section 7, R2 and R3; REVIEW_SIGNALS_S2_TO_S7_2026_11_21, B10).
--            A person in a running play who gets a central signal outside the play's topic gets a signal draft of
--            their own, and their steps in the play wait (Borce 2026-11-21: 14 days). The plays have per-person stops
--            (do not contact, stop_drafts, an automation hold, an unsubscribe), all of them permanent; nothing pauses
--            one person for a while and gives them back to the play. This adds that hold.
--              1. contacts.signal_hold_until timestamptz, nullable: while it is in the future the plays do not draft,
--                 dispatch or enrol this person (the LinkedIn claim loop defers the step to this time, the scheduled
--                 LinkedIn dispatch re-parks the send, the email follow-up cron skips the person, a new play's
--                 enrolment leaves them out). Past or null = no hold; nothing has to clear it.
--              2. contacts.signal_hold_reason text, nullable: why. `outside_topic_signal` (the signal draft of a
--                 running play's person, 14 days after the last signal message went out) or `signal_replied` (they
--                 replied to the signal message: the signal hand-over owns the reply and the play does not take them
--                 back). Only Modal (brain_signal_outreach, signal_reply_handover) writes both columns.
--              3. A partial index on signal_hold_until for the rows that have one (the Modal pass that extends or
--                 clears holds reads them every 5 minutes; almost every row is null).
--            `automation_hold_at` is NOT reused: it is permanent, it reads as Do Not Contact in nurture, calls and the
--            next best action, and it would cancel the signal's own sequence (REVIEW B10).
-- Projects:  selltonai-database/supabase (owner); selltonai-modal writes the columns and reads them in the email
--            follow-up cron, the first-email choke point and the signal router and hand-over; selltonai reads them
--            in the LinkedIn claim loop, the scheduled LinkedIn dispatch, the auto-enroll route and the signal
--            sequence's running-play test.
-- Contract:  Two new nullable columns and one partial index. No default, no backfill, no trigger, no change to any
--            existing column, function or policy. Readers read the columns in their own select and treat a failed
--            read as no hold, so the order is safe either way; the merge order is this, then Modal, then the app.
-- Depends:   public.contacts.
-- Rollback:  rollback/450_contacts-signal-hold.rollback.sql
-- ============================================================

SET LOCAL lock_timeout = '10s';

ALTER TABLE public.contacts
  ADD COLUMN IF NOT EXISTS signal_hold_until timestamptz,
  ADD COLUMN IF NOT EXISTS signal_hold_reason text;

COMMENT ON COLUMN public.contacts.signal_hold_until IS
  'Signals S5 (450): while in the future, the plays hold this person''s steps (no draft, no dispatch, no enrolment). Past or null = no hold. Written by Modal only.';
COMMENT ON COLUMN public.contacts.signal_hold_reason IS
  'Signals S5 (450): why signal_hold_until is set: outside_topic_signal or signal_replied. Written by Modal only.';

CREATE INDEX IF NOT EXISTS idx_contacts_signal_hold_until
  ON public.contacts (signal_hold_until)
  WHERE signal_hold_until IS NOT NULL;
