-- =====================================================
-- SUPABASE DELETE POLICIES FOR ACCOUNT DELETION
-- =====================================================
-- This SQL adds DELETE policies to allow users to delete their accounts
-- Run this in your Supabase SQL Editor
--
-- IMPORTANT: Run this to fix account deletion functionality

-- =====================================================
-- 1. USERS TABLE DELETE POLICY
-- =====================================================

-- Check if users table has RLS enabled
ALTER TABLE IF EXISTS public.users ENABLE ROW LEVEL SECURITY;

-- Drop existing delete policy if any
DROP POLICY IF EXISTS "Users can delete own account" ON public.users;
DROP POLICY IF EXISTS "Allow all to delete users" ON public.users;

-- Create permissive delete policy
-- Since your app doesn't use Supabase Auth, allow all deletions
CREATE POLICY "Allow all to delete users"
  ON public.users
  FOR DELETE
  USING (true);

-- =====================================================
-- 2. USER_FAVORITES TABLE DELETE POLICY
-- =====================================================

-- Check if user_favorites table exists and has RLS enabled
ALTER TABLE IF EXISTS public.user_favorites ENABLE ROW LEVEL SECURITY;

-- Drop existing delete policy if any
DROP POLICY IF EXISTS "Users can delete own favorites" ON public.user_favorites;
DROP POLICY IF EXISTS "Allow all to delete favorites" ON public.user_favorites;

-- Create permissive delete policy
CREATE POLICY "Allow all to delete favorites"
  ON public.user_favorites
  FOR DELETE
  USING (true);

-- =====================================================
-- 3. USER_PAYMENTS TABLE DELETE POLICY
-- =====================================================

-- The payments table might be named 'payments' or 'user_payments'
-- We'll create policies for both to be safe

-- For 'payments' table
ALTER TABLE IF EXISTS public.payments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can delete own payments" ON public.payments;
DROP POLICY IF EXISTS "Allow all to delete payments" ON public.payments;

CREATE POLICY "Allow all to delete payments"
  ON public.payments
  FOR DELETE
  USING (true);

-- For 'user_payments' table (if it exists)
ALTER TABLE IF EXISTS public.user_payments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can delete own payments" ON public.user_payments;
DROP POLICY IF EXISTS "Allow all to delete user_payments" ON public.user_payments;

CREATE POLICY "Allow all to delete user_payments"
  ON public.user_payments
  FOR DELETE
  USING (true);

-- =====================================================
-- 4. USER_SUBSCRIPTIONS TABLE DELETE POLICY
-- =====================================================

-- For 'subscriptions' table
ALTER TABLE IF EXISTS public.subscriptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can delete own subscription" ON public.subscriptions;
DROP POLICY IF EXISTS "Allow all to delete subscriptions" ON public.subscriptions;

CREATE POLICY "Allow all to delete subscriptions"
  ON public.subscriptions
  FOR DELETE
  USING (true);

-- For 'user_subscriptions' table (if it exists)
ALTER TABLE IF EXISTS public.user_subscriptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can delete own subscription" ON public.user_subscriptions;
DROP POLICY IF EXISTS "Allow all to delete user_subscriptions" ON public.user_subscriptions;

CREATE POLICY "Allow all to delete user_subscriptions"
  ON public.user_subscriptions
  FOR DELETE
  USING (true);

-- =====================================================
-- VERIFICATION QUERIES
-- =====================================================

-- Check all policies for users table
SELECT tablename, policyname, cmd, qual
FROM pg_policies
WHERE tablename = 'users';

-- Check all policies for user_favorites table
SELECT tablename, policyname, cmd, qual
FROM pg_policies
WHERE tablename = 'user_favorites';

-- Check all policies for payments table
SELECT tablename, policyname, cmd, qual
FROM pg_policies
WHERE tablename = 'payments';

-- Check all policies for user_payments table
SELECT tablename, policyname, cmd, qual
FROM pg_policies
WHERE tablename = 'user_payments';

-- Check all policies for subscriptions table
SELECT tablename, policyname, cmd, qual
FROM pg_policies
WHERE tablename = 'subscriptions';

-- Check all policies for user_subscriptions table
SELECT tablename, policyname, cmd, qual
FROM pg_policies
WHERE tablename = 'user_subscriptions';

-- =====================================================
-- TEST QUERIES (Optional - DON'T RUN IN PRODUCTION)
-- =====================================================

-- Test delete on test user (CAUTION: This will delete real data!)
-- DELETE FROM public.user_favorites WHERE user_id = 'test_user_id';
-- DELETE FROM public.payments WHERE user_id = 'test_user_id';
-- DELETE FROM public.subscriptions WHERE user_id = 'test_user_id';
-- DELETE FROM public.users WHERE id = 'test_user_id';

-- =====================================================
-- NOTES
-- =====================================================
--
-- These policies allow unrestricted DELETE operations on all tables
-- This is necessary because your app uses custom authentication
-- (username/PIN) instead of Supabase Auth
--
-- The app verifies the user's PIN before allowing deletion,
-- so the deletion is already secured at the application level
--
-- If you later add Supabase Auth, update these policies to:
--   USING (auth.uid()::text = user_id)
--
-- =====================================================
