-- =====================================================
-- SUPABASE SUBSCRIPTIONS TABLE SETUP
-- =====================================================
-- This SQL creates the subscriptions table for cross-device sync
-- Run this in your Supabase SQL Editor

-- 1. Create subscriptions table
CREATE TABLE IF NOT EXISTS public.subscriptions (
  id BIGSERIAL PRIMARY KEY,
  user_id TEXT NOT NULL,
  tier_index INTEGER NOT NULL DEFAULT 0,
  tier_name TEXT NOT NULL DEFAULT 'free',
  expiry_date TIMESTAMP WITH TIME ZONE,
  purchase_date TIMESTAMP WITH TIME ZONE,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()

  -- No UNIQUE constraint - users can have multiple subscription records (renewal history)
);

-- 2. Create indexes for faster queries
CREATE INDEX IF NOT EXISTS idx_subscriptions_user_id
  ON public.subscriptions(user_id);

CREATE INDEX IF NOT EXISTS idx_subscriptions_expiry
  ON public.subscriptions(expiry_date);

-- 3. Enable Row Level Security (RLS)
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;

-- 4. RLS Policies - Allow users to read/write their own subscriptions

-- Allow users to read their own subscription
CREATE POLICY "Users can read own subscription"
  ON public.subscriptions
  FOR SELECT
  USING (true);  -- Allow all reads (you can restrict to auth.uid() if using auth)

-- Allow users to insert their own subscription
CREATE POLICY "Users can insert own subscription"
  ON public.subscriptions
  FOR INSERT
  WITH CHECK (true);  -- Allow all inserts (you can restrict to auth.uid() if using auth)

-- Allow users to update their own subscription
CREATE POLICY "Users can update own subscription"
  ON public.subscriptions
  FOR UPDATE
  USING (true)  -- Allow all updates (you can restrict to auth.uid() if using auth)
  WITH CHECK (true);

-- Allow users to delete their own subscription
CREATE POLICY "Users can delete own subscription"
  ON public.subscriptions
  FOR DELETE
  USING (true);  -- Allow all deletes (you can restrict to auth.uid() if using auth)

-- 5. Create function to automatically update updated_at timestamp
CREATE OR REPLACE FUNCTION update_subscriptions_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 6. Create trigger to call the function
DROP TRIGGER IF EXISTS subscriptions_updated_at_trigger ON public.subscriptions;
CREATE TRIGGER subscriptions_updated_at_trigger
  BEFORE UPDATE ON public.subscriptions
  FOR EACH ROW
  EXECUTE FUNCTION update_subscriptions_updated_at();

-- =====================================================
-- VERIFICATION QUERIES
-- =====================================================

-- Check if table was created successfully
SELECT table_name, table_type
FROM information_schema.tables
WHERE table_schema = 'public'
AND table_name = 'subscriptions';

-- Check indexes
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'subscriptions';

-- Check RLS is enabled
SELECT tablename, rowsecurity
FROM pg_tables
WHERE tablename = 'subscriptions';

-- View all policies
SELECT policyname, cmd, qual, with_check
FROM pg_policies
WHERE tablename = 'subscriptions';

-- =====================================================
-- TEST QUERIES (Optional)
-- =====================================================

-- Insert a test subscription
-- INSERT INTO public.subscriptions (user_id, tier_index, tier_name, expiry_date, purchase_date)
-- VALUES ('test_user_123', 2, 'sixMonths', NOW() + INTERVAL '6 months', NOW());

-- Query subscriptions
-- SELECT * FROM public.subscriptions WHERE user_id = 'test_user_123';

-- Update subscription
-- UPDATE public.subscriptions
-- SET tier_index = 3, tier_name = 'yearly', expiry_date = NOW() + INTERVAL '1 year'
-- WHERE user_id = 'test_user_123';

-- Delete subscription
-- DELETE FROM public.subscriptions WHERE user_id = 'test_user_123';

-- =====================================================
-- NOTES
-- =====================================================
--
-- * Users can have MULTIPLE subscription records (renewal history tracking)
-- * App queries for the latest active subscription (ORDER BY created_at DESC)
-- * Each purchase creates a NEW row (keeps full history)
-- * The updated_at timestamp updates automatically on every UPDATE
-- * RLS policies allow all operations - adjust if you add Supabase Auth
-- * tier_index maps to: 0=free, 1=threeMonths, 2=sixMonths, 3=yearly
--
-- =====================================================
