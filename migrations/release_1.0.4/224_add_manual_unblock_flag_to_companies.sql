ALTER TABLE "public"."companies"
ADD COLUMN IF NOT EXISTS "manually_unblocked" boolean DEFAULT false;

COMMENT ON COLUMN "public"."companies"."manually_unblocked" IS 'Flag set when a user manually unblocks an ICP-blocked company. Tells the processing pipeline to skip ICP blocking for this company. Cleared after processing completes.';
