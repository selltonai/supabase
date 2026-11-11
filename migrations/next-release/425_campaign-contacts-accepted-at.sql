-- ============================================================
-- Migration: 425_campaign-contacts-accepted-at
-- Date:      2026-11-10
-- Purpose:   Invitation lines (PLAN_INVITATION_NOTES_2026_11_10_REV4.md D19, stage 1b): the time a LinkedIn
--            invitation was accepted, on the play's journey row, so sent and accepted can be counted per invitation
--            line and the play can lean to the accepted line after 4 weeks of data. Today only relation_state is set.
-- Projects:  selltonai-database/supabase (owner); selltonai writes it (src/lib/linkedin-accepted-at.ts, called by
--            the relation transition on 'connected', once per row: only where it is still null); selltonai-modal
--            reads it (the per-line acceptance count).
-- Contract:  Additive only, nullable, no default, no backfill: rows accepted before this stay null and count as
--            "accepted, time unknown" through relation_state. The app writes it in its own update after the
--            relation_state write and ignores a missing column, so the order of the deploys does not matter.
--            Rollback: rollback/425_campaign-contacts-accepted-at.rollback.sql
-- ============================================================

ALTER TABLE public.campaign_contacts
  ADD COLUMN IF NOT EXISTS accepted_at timestamptz;

COMMENT ON COLUMN public.campaign_contacts.accepted_at IS
  'When the LinkedIn invitation of this journey was accepted (first time seen). Null: not accepted, or accepted before 425.';

-- Counting accepted invitations per play and week reads only the accepted rows.
CREATE INDEX IF NOT EXISTS idx_campaign_contacts_campaign_accepted_at
  ON public.campaign_contacts (campaign_id, accepted_at)
  WHERE accepted_at IS NOT NULL;

-- Verify
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'campaign_contacts' AND column_name = 'accepted_at'
  ) THEN
    RAISE EXCEPTION '425: campaign_contacts.accepted_at is missing';
  END IF;
END $$;
