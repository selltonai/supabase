-- Migration: Fix Realtime RLS for Clerk Third-Party Auth
-- Author: Milka
-- Date: 2026-03-08
-- Ticket: SP-38
--
-- Problem:
-- Supabase Realtime subscriptions receive no events because
-- requesting_user_id() returns incorrect values in the Realtime context.
--
-- Root cause:
-- current_setting('request.jwt.claim.sub', true) stores JWT claims as
-- JSON-encoded values (e.g., '"user_2NNEq..."' with surrounding quotes).
-- In the Realtime context, individual claim GUC variables like
-- request.jwt.claim.sub may not be set at all; only request.jwt.claims
-- (the full JSON blob) is reliably available.
--
-- Fix:
-- 1. Update requesting_user_id() to use auth.jwt()->>'sub' as primary
--    (the ->> operator correctly extracts text from the JSON blob)
-- 2. Fall back to current_setting only after stripping JSON quotes
-- 3. Wrap RLS expressions in (SELECT ...) as Supabase recommends for
--    Clerk integration (prevents planner from re-evaluating per row)

-- ============================================================
-- Step 1: Fix requesting_user_id() function
-- ============================================================

CREATE OR REPLACE FUNCTION public.requesting_user_id()
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    -- Primary: works reliably in both PostgREST and Realtime contexts.
    -- auth.jwt() reads from request.jwt.claims (full JSON blob),
    -- and ->> extracts the value as properly unquoted text.
    (auth.jwt()->>'sub'),
    -- Fallback: strip JSON quotes from the individual claim GUC variable.
    -- In PostgREST, request.jwt.claim.sub may be set as a JSON string
    -- like '"user_2NNEq..."' — trim the surrounding double quotes.
    NULLIF(trim(both '"' from current_setting('request.jwt.claim.sub', true)), '')
  );
$$;

-- ============================================================
-- Step 2: Rebuild notifications SELECT policy (simpler for Realtime)
-- ============================================================
-- Using (SELECT ...) wrapper as recommended by Supabase Clerk docs.
-- This prevents the planner from re-evaluating the function per row.

DROP POLICY IF EXISTS "Users can view their own notifications" ON notifications;
CREATE POLICY "Users can view their own notifications"
    ON notifications FOR SELECT
    USING (
        user_id = (SELECT requesting_user_id())
    );

-- UPDATE policy stays more restrictive (includes org check)
DROP POLICY IF EXISTS "Users can update their own notifications" ON notifications;
CREATE POLICY "Users can update their own notifications"
    ON notifications FOR UPDATE
    USING (
        user_id = (SELECT requesting_user_id())
        AND organization_id IN (
            SELECT organization_id
            FROM user_organizations
            WHERE user_id = (SELECT requesting_user_id())
        )
    )
    WITH CHECK (
        user_id = (SELECT requesting_user_id())
    );

-- ============================================================
-- Step 3: Rebuild user_profiles policies with same pattern
-- ============================================================

DROP POLICY IF EXISTS "Users can view their own profile" ON user_profiles;
CREATE POLICY "Users can view their own profile"
    ON user_profiles FOR SELECT
    USING (
        user_id = (SELECT requesting_user_id())
    );

DROP POLICY IF EXISTS "Users can update their own profile" ON user_profiles;
CREATE POLICY "Users can update their own profile"
    ON user_profiles FOR UPDATE
    USING (
        user_id = (SELECT requesting_user_id())
    )
    WITH CHECK (
        user_id = (SELECT requesting_user_id())
    );

DROP POLICY IF EXISTS "Users can insert their own profile" ON user_profiles;
CREATE POLICY "Users can insert their own profile"
    ON user_profiles FOR INSERT
    WITH CHECK (
        user_id = (SELECT requesting_user_id())
    );
