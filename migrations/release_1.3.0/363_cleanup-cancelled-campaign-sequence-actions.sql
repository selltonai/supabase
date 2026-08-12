-- ============================================================
-- Migration: 363_cleanup-cancelled-campaign-sequence-actions
-- Date:      2026-08-12
-- Purpose:   Retire LinkedIn journeys + sequence actions left live under
--            campaigns that were cancelled BEFORE the G2 fix shipped.
-- Projects:  selltonai-database/supabase (owner), selltonai (sequence claimer).
-- Contract:  Data-only. Terminal-state cleanup; no schema change.
-- Depends:   none (additive UPDATEs).
--
-- Why
-- ---
-- Cancelling a campaign is a SOFT DELETE. Until 2026-07-30 it deleted the
-- campaign's tasks but left `campaign_contacts` in queued_invite/messaged and
-- their `campaign_sequence_actions` at status='pending'. The claim loop then hit
-- its "campaign not active" gate and deferred every one of those actions +24h,
-- every tick, forever.
--
-- selltonai commit 8c5cd631 fixed the cancel path (cancelCampaignJourneys), but
-- it does not reach rows orphaned by earlier cancellations. Measured in
-- production 2026-08-12, one org carried 675 such actions:
--     614 linkedin_invitation  · 45 linkedin_message · 16 linkedin_followup
-- against 42 cancelled campaigns.
--
-- The damage was not just noise. Those 614 invitations were the ENTIRE pending
-- invitation population — there were zero invitation actions on any active
-- campaign — so the operator's "no new invites to approve" report and a
-- 1,475-row pending queue were the same fact. They also inflated the sequence
-- health widget, whose "pending" tile counts rows that exist rather than work
-- that is due.
--
-- Mirrors cancelCampaignJourneys exactly: actions first, then journeys, same
-- status sets. Actions-before-journeys is deliberate — a failure mid-way leaves
-- actions cancelled under a still-live journey (harmless, the campaign is
-- cancelled and the claim loop skips it) rather than the reverse, which would
-- leave claimable actions under a terminal journey.
-- ============================================================

-- 1. Retire non-terminal actions belonging to cancelled campaigns.
UPDATE public.campaign_sequence_actions csa
SET status = 'cancelled',
    updated_at = NOW()
FROM public.campaign_contacts cc
JOIN public.campaigns c ON c.id = cc.campaign_id
WHERE csa.campaign_contact_id = cc.id
  AND c.status = 'cancelled'
  AND csa.status IN ('pending', 'claimed', 'ready_for_review');

-- 2. Flip the journeys terminal so nothing re-queues them and they stop
--    appearing as live work. TERMINAL_STATES per the sequence engine:
--    replied, declined, failed, completed, cancelled, unreachable.
UPDATE public.campaign_contacts cc
SET journey_state = 'cancelled',
    next_action_at = NULL,
    updated_at = NOW()
FROM public.campaigns c
WHERE c.id = cc.campaign_id
  AND c.status = 'cancelled'
  AND cc.journey_state NOT IN (
    'replied', 'declined', 'failed', 'completed', 'cancelled', 'unreachable'
  );

-- Verify after apply.
--
-- Expect ZERO rows — no live action may remain under a cancelled campaign:
-- SELECT c.status AS campaign_status, csa.action_type, count(*)
-- FROM campaign_sequence_actions csa
-- JOIN campaign_contacts cc ON cc.id = csa.campaign_contact_id
-- JOIN campaigns c ON c.id = cc.campaign_id
-- WHERE c.status = 'cancelled'
--   AND csa.status IN ('pending','claimed','ready_for_review')
-- GROUP BY 1,2;
--
-- And the pending queue should now reflect only real work:
-- SELECT c.status AS campaign_status, csa.action_type, count(*),
--        count(*) FILTER (WHERE csa.scheduled_at IS NULL OR csa.scheduled_at <= NOW()) AS due_now
-- FROM campaign_sequence_actions csa
-- JOIN campaign_contacts cc ON cc.id = csa.campaign_contact_id
-- JOIN campaigns c ON c.id = cc.campaign_id
-- WHERE csa.status = 'pending'
-- GROUP BY 1,2 ORDER BY 3 DESC;
