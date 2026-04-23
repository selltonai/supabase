-- Migration: Enable Clerk Third-Party Auth + Realtime for notifications
-- Author: Milka
-- Date: 2026-03-08
-- Ticket: SP-38
--
-- Context:
-- Sellton uses Clerk for authentication and Supabase for the database.
-- As of April 2025, Supabase supports Clerk as a native Third-Party Auth
-- provider (JWT Templates are deprecated). With Third-Party Auth, Supabase
-- verifies Clerk session tokens via JWKS (asymmetric keys).
--
-- Problem:
-- auth.uid() casts the JWT 'sub' claim to UUID, but Clerk user IDs are
-- strings like 'user_2NNEq...'. This causes auth.uid() to return NULL,
-- breaking all RLS policies that use auth.uid()::text.
--
-- Solution:
-- 1. Create requesting_user_id() that reads 'sub' as text (no UUID cast)
-- 2. Update notifications + user_profiles RLS to use requesting_user_id()
-- 3. Add notifications to Realtime publication
--
-- PREREQUISITES (one-time setup):
-- 1. Configure Clerk: https://dashboard.clerk.com/setup/supabase
-- 2. Supabase Dashboard → Authentication → Third-Party Auth → Add Clerk
--    (enter your Clerk Frontend API URL)

-- ============================================================
-- Step 1: Create requesting_user_id() helper function
-- ============================================================
-- Safely extracts the Clerk user ID from the JWT 'sub' claim as TEXT.
-- Works with both Third-Party Auth and service role tokens.

CREATE OR REPLACE FUNCTION public.requesting_user_id()
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    current_setting('request.jwt.claim.sub', true),
    (auth.jwt()->>'sub')
  );
$$;

-- ============================================================
-- Step 2: Update notifications RLS policies
-- ============================================================
-- Replace auth.uid()::text → requesting_user_id()

DROP POLICY IF EXISTS "Users can view their own notifications" ON notifications;
CREATE POLICY "Users can view their own notifications"
    ON notifications FOR SELECT
    USING (
        user_id = requesting_user_id()
        AND organization_id IN (
            SELECT organization_id
            FROM user_organizations
            WHERE user_id = requesting_user_id()
        )
    );

DROP POLICY IF EXISTS "Users can update their own notifications" ON notifications;
CREATE POLICY "Users can update their own notifications"
    ON notifications FOR UPDATE
    USING (
        user_id = requesting_user_id()
        AND organization_id IN (
            SELECT organization_id
            FROM user_organizations
            WHERE user_id = requesting_user_id()
        )
    )
    WITH CHECK (
        user_id = requesting_user_id()
        AND organization_id IN (
            SELECT organization_id
            FROM user_organizations
            WHERE user_id = requesting_user_id()
        )
    );

-- Service role policy stays unchanged (uses current_setting directly)

-- ============================================================
-- Step 3: Update user_profiles RLS policies
-- ============================================================

DROP POLICY IF EXISTS "Users can view their own profile" ON user_profiles;
CREATE POLICY "Users can view their own profile"
    ON user_profiles FOR SELECT
    USING (
        user_id = requesting_user_id()
        AND organization_id IN (
            SELECT organization_id FROM user_organizations
            WHERE user_id = requesting_user_id()
        )
    );

DROP POLICY IF EXISTS "Users can update their own profile" ON user_profiles;
CREATE POLICY "Users can update their own profile"
    ON user_profiles FOR UPDATE
    USING (
        user_id = requesting_user_id()
        AND organization_id IN (
            SELECT organization_id FROM user_organizations
            WHERE user_id = requesting_user_id()
        )
    )
    WITH CHECK (
        user_id = requesting_user_id()
        AND organization_id IN (
            SELECT organization_id FROM user_organizations
            WHERE user_id = requesting_user_id()
        )
    );

DROP POLICY IF EXISTS "Users can insert their own profile" ON user_profiles;
CREATE POLICY "Users can insert their own profile"
    ON user_profiles FOR INSERT
    WITH CHECK (
        user_id = requesting_user_id()
        AND organization_id IN (
            SELECT organization_id FROM user_organizations
            WHERE user_id = requesting_user_id()
        )
    );

-- ============================================================
-- Step 4: Enable Realtime on notifications table
-- ============================================================
-- Postgres Changes respect RLS directly — no private channel config needed.
-- Records are only sent to clients who pass the SELECT policy.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
    AND tablename = 'notifications'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
  END IF;
END $$;
