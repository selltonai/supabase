-- 346 — CRM list owner (uploader) for contact ownership.
--
-- What changed:
--   Adds crm_lists.user_id — the user who created/uploaded the list. Contact
--   extraction (selltonai-modal CRMService) inherits it and stamps each new
--   contact's assigned_to_user_id, so CSV/Sales-Nav uploads are owned by their
--   uploader and scope correctly under the CRM member filter (W6 / KAN-260).
--
--   Nullable on purpose: pre-existing lists have no recorded uploader and stay
--   NULL (unowned → admin-only under the member filter), matching how existing
--   owner-less contacts already behave. Additive and safe to drop.
--
-- Affected projects:
--   - selltonai passes the Clerk user id to POST /lists on CSV upload.
--   - selltonai-modal create_list persists user_id; process_list_import reads it
--     and _extract_contacts stamps contacts.assigned_to_user_id.
--   - backoffice and billing readers are unchanged.
--
-- Deploy order:
--   1. Apply this additive migration in every environment FIRST.
--   2. Then deploy selltonai-modal (create_list writes the new column) and the
--      selltonai BFF (passes the uploader). A rolled-back build simply leaves
--      user_id NULL — no break.

ALTER TABLE public.crm_lists
  ADD COLUMN IF NOT EXISTS user_id text;

CREATE INDEX IF NOT EXISTS idx_crm_lists_user_id
  ON public.crm_lists(user_id)
  WHERE user_id IS NOT NULL;

COMMENT ON COLUMN public.crm_lists.user_id IS
  'Clerk user id of the uploader/owner. Inherited by extracted contacts as assigned_to_user_id (W6/KAN-260). NULL for legacy lists with no recorded uploader.';

-- Verify:
--   SELECT user_id IS NULL AS unowned, count(*)
--   FROM public.crm_lists
--   GROUP BY 1
--   ORDER BY 1;
