-- 347 — Campaign created-by-admin attribution (W6 / KAN-250).
--
-- What changed:
--   Adds campaigns.created_by_admin_user_id — the admin/org-owner who created a
--   campaign ON BEHALF OF another rep (i.e. pointed it at that rep's LinkedIn
--   account). NULL for self-created campaigns.
--
--   Why a separate column instead of reusing user_id: campaigns.user_id is the
--   OWNER axis that voice, copywriter approach, LinkedIn account auto-pick, and
--   the rebinding resolver (resolveActiveCampaignLinkedinAccount) all key off. To
--   let an admin run a campaign on a teammate's account WITHOUT the resolver
--   force-rebinding it back, user_id must be set to the ACCOUNT'S owner (the
--   rep), not the admin. This column records the admin separately, purely for
--   audit + a "created by" display — it is NOT read by any send/scope logic.
--
--   Nullable + additive; safe to drop. No backfill: existing campaigns are all
--   self-created (user_id already = the creating rep), so created_by_admin_user_id
--   is correctly NULL for them.
--
-- Affected projects:
--   - selltonai POST /api/campaigns sets user_id = the LinkedIn account's owner
--     and created_by_admin_user_id = the admin when they differ.
--   - selltonai-modal + backoffice: unchanged (do not read this column).
--
-- Deploy order: apply this additive migration before deploying the selltonai
-- campaign-create change. A rolled-back build simply never writes the column.

ALTER TABLE public.campaigns
  ADD COLUMN IF NOT EXISTS created_by_admin_user_id text;

CREATE INDEX IF NOT EXISTS idx_campaigns_created_by_admin_user_id
  ON public.campaigns(created_by_admin_user_id)
  WHERE created_by_admin_user_id IS NOT NULL;

COMMENT ON COLUMN public.campaigns.created_by_admin_user_id IS
  'Admin/org-owner who created this campaign on behalf of another rep (audit + "created by" display only; never read by send/scope logic). NULL for self-created campaigns. campaigns.user_id remains the OWNER = the rep whose LinkedIn account runs it. W6/KAN-250.';

-- Verify:
--   SELECT created_by_admin_user_id IS NOT NULL AS admin_created, count(*)
--   FROM public.campaigns
--   GROUP BY 1
--   ORDER BY 1;
