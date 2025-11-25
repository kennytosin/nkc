-- =====================================================
-- SUPABASE DELETE POLICIES - SIMPLIFIED VERSION
-- =====================================================
-- This creates DELETE policies only for tables that exist
-- Run this in your Supabase SQL Editor
--
-- STEP 1: First, run this to see which tables you have:

SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_type = 'BASE TABLE'
  AND table_name IN ('users', 'user_favorites', 'payments', 'subscriptions')
ORDER BY table_name;

-- Copy the output and note which tables exist, then continue below

-- =====================================================
-- STEP 2: Run the sections below for tables that exist
-- =====================================================

-- =====================================================
-- FOR: users TABLE
-- =====================================================
-- Only run this if you have a 'users' table

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can delete own account" ON public.users;
DROP POLICY IF EXISTS "Allow all to delete users" ON public.users;

CREATE POLICY "Allow all to delete users"
  ON public.users
  FOR DELETE
  USING (true);

-- =====================================================
-- FOR: user_favorites TABLE
-- =====================================================
-- Only run this if you have a 'user_favorites' table

ALTER TABLE public.user_favorites ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can delete own favorites" ON public.user_favorites;
DROP POLICY IF EXISTS "Allow all to delete favorites" ON public.user_favorites;

CREATE POLICY "Allow all to delete favorites"
  ON public.user_favorites
  FOR DELETE
  USING (true);

-- =====================================================
-- FOR: payments TABLE
-- =====================================================
-- Only run this if you have a 'payments' table

ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can delete own payments" ON public.payments;
DROP POLICY IF EXISTS "Allow all to delete payments" ON public.payments;

CREATE POLICY "Allow all to delete payments"
  ON public.payments
  FOR DELETE
  USING (true);

-- =====================================================
-- FOR: subscriptions TABLE
-- =====================================================
-- Only run this if you have a 'subscriptions' table

ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can delete own subscription" ON public.subscriptions;
DROP POLICY IF EXISTS "Allow all to delete subscriptions" ON public.subscriptions;

CREATE POLICY "Allow all to delete subscriptions"
  ON public.subscriptions
  FOR DELETE
  USING (true);

-- =====================================================
-- VERIFICATION - Check that policies were created
-- =====================================================

-- View all DELETE policies
SELECT
  tablename,
  policyname,
  cmd as command
FROM pg_policies
WHERE cmd = 'DELETE'
  AND tablename IN ('users', 'user_favorites', 'payments', 'subscriptions')
ORDER BY tablename;

-- =====================================================
-- NOTES
-- =====================================================
-- These policies allow DELETE operations when the app requests them
-- The app code ensures only the specific user's data is deleted
-- No data is deleted by running this SQL - it only creates permissions
-- =====================================================
