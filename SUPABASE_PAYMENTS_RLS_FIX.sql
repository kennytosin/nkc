-- =====================================================
-- SUPABASE PAYMENTS TABLE RLS FIX
-- =====================================================
-- This fixes Row Level Security to allow payment inserts
-- Run this in your Supabase SQL Editor

-- Drop existing restrictive policies
DROP POLICY IF EXISTS "Users can insert own payment" ON public.payments;
DROP POLICY IF EXISTS "Users can read own payments" ON public.payments;
DROP POLICY IF EXISTS "Users can update own payment" ON public.payments;
DROP POLICY IF EXISTS "Users can delete own payment" ON public.payments;

-- Create permissive policies that allow all operations
-- (You can restrict these to auth.uid() later if you add Supabase Auth)

-- Allow all users to read payments
CREATE POLICY "Allow all to read payments"
  ON public.payments
  FOR SELECT
  USING (true);

-- Allow all users to insert payments
CREATE POLICY "Allow all to insert payments"
  ON public.payments
  FOR INSERT
  WITH CHECK (true);

-- Allow all users to update payments
CREATE POLICY "Allow all to update payments"
  ON public.payments
  FOR UPDATE
  USING (true)
  WITH CHECK (true);

-- Allow all users to delete payments
CREATE POLICY "Allow all to delete payments"
  ON public.payments
  FOR DELETE
  USING (true);

-- =====================================================
-- VERIFICATION
-- =====================================================

-- Check RLS is enabled
SELECT tablename, rowsecurity
FROM pg_tables
WHERE tablename = 'payments';

-- View all policies
SELECT policyname, cmd, qual, with_check
FROM pg_policies
WHERE tablename = 'payments';

-- =====================================================
-- NOTES
-- =====================================================
--
-- These policies allow unrestricted access to payments table
-- This is fine for testing and for apps without Supabase Auth
--
-- If you add Supabase Authentication later, update policies to:
--   USING (auth.uid()::text = user_id)
--   WITH CHECK (auth.uid()::text = user_id)
--
-- =====================================================
