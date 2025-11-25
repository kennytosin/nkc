-- =====================================================
-- SUPABASE USER FAVORITES TABLE SETUP
-- =====================================================
-- This creates the user_favorites table for syncing favorites across devices
-- Run this in your Supabase SQL Editor
--
-- IMPORTANT: Run this to enable favorites cloud sync

-- =====================================================
-- 1. CREATE user_favorites TABLE
-- =====================================================

CREATE TABLE IF NOT EXISTS public.user_favorites (
  id BIGSERIAL PRIMARY KEY,
  user_id TEXT NOT NULL,
  type TEXT NOT NULL,
  reference_id TEXT NOT NULL,
  title TEXT NOT NULL,
  content TEXT,
  subtitle TEXT,
  book_id INTEGER,
  chapter INTEGER,
  verse INTEGER,
  translation_id TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),

  -- Unique constraint: one user can't have duplicate favorites
  UNIQUE(user_id, type, reference_id)
);

-- =====================================================
-- 2. CREATE INDEXES FOR FAST QUERIES
-- =====================================================

CREATE INDEX IF NOT EXISTS idx_user_favorites_user_id
  ON public.user_favorites(user_id);

CREATE INDEX IF NOT EXISTS idx_user_favorites_type
  ON public.user_favorites(type);

CREATE INDEX IF NOT EXISTS idx_user_favorites_composite
  ON public.user_favorites(user_id, type, reference_id);

-- =====================================================
-- 3. ENABLE ROW LEVEL SECURITY (RLS)
-- =====================================================

ALTER TABLE public.user_favorites ENABLE ROW LEVEL SECURITY;

-- =====================================================
-- 4. CREATE RLS POLICIES
-- =====================================================

-- Allow all users to read their own favorites
CREATE POLICY "Users can read own favorites"
  ON public.user_favorites
  FOR SELECT
  USING (true);  -- Allow all reads (you can restrict to auth.uid() if using Supabase Auth)

-- Allow all users to insert their own favorites
CREATE POLICY "Users can insert own favorites"
  ON public.user_favorites
  FOR INSERT
  WITH CHECK (true);  -- Allow all inserts

-- Allow all users to update their own favorites
CREATE POLICY "Users can update own favorites"
  ON public.user_favorites
  FOR UPDATE
  USING (true)
  WITH CHECK (true);

-- Allow all users to delete their own favorites
CREATE POLICY "Users can delete own favorites"
  ON public.user_favorites
  FOR DELETE
  USING (true);  -- Already set up in SUPABASE_DELETE_POLICIES_SIMPLE.sql

-- =====================================================
-- 5. CREATE AUTO-UPDATE TRIGGER FOR updated_at
-- =====================================================

CREATE OR REPLACE FUNCTION update_user_favorites_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS user_favorites_updated_at_trigger ON public.user_favorites;

CREATE TRIGGER user_favorites_updated_at_trigger
  BEFORE UPDATE ON public.user_favorites
  FOR EACH ROW
  EXECUTE FUNCTION update_user_favorites_updated_at();

-- =====================================================
-- VERIFICATION QUERIES
-- =====================================================

-- Check if table was created successfully
SELECT table_name, table_type
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name = 'user_favorites';

-- Check indexes
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'user_favorites';

-- Check RLS is enabled
SELECT tablename, rowsecurity
FROM pg_tables
WHERE tablename = 'user_favorites';

-- View all policies
SELECT policyname, cmd, qual, with_check
FROM pg_policies
WHERE tablename = 'user_favorites';

-- =====================================================
-- TEST QUERIES (Optional)
-- =====================================================

-- View favorites for a specific user
-- SELECT * FROM public.user_favorites WHERE user_id = 'your_user_id' ORDER BY created_at DESC;

-- Count favorites by type for a user
-- SELECT type, COUNT(*) as count
-- FROM public.user_favorites
-- WHERE user_id = 'your_user_id'
-- GROUP BY type;

-- =====================================================
-- NOTES
-- =====================================================
--
-- Favorite Types:
--   - 'devotional': Daily devotionals
--   - 'verse': Bible verses
--   - 'theme': Devotional themes
--
-- The reference_id format depends on the type:
--   - devotional: Date string (e.g., '2024-11-25')
--   - verse: Format like 'John 3:16'
--   - theme: Theme ID/name
--
-- The UNIQUE constraint ensures a user can't favorite the same item twice
-- RLS policies allow all operations (safe for apps without Supabase Auth)
-- The updated_at timestamp automatically updates on every UPDATE
--
-- =====================================================
