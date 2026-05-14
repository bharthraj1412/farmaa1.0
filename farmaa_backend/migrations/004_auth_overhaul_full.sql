-- ============================================================
-- FARMAA – Auth Overhaul Migration (Google-only)
-- Run this in Supabase SQL Editor
-- Date: 2026-03-19
-- ============================================================
-- This migration:
--   1. Adds new columns for Google auth + profile completion
--   2. Migrates existing data from legacy columns
--   3. Drops legacy columns (phone, password_hash, village, organization)
--   4. Updates indexes and RLS policies
-- ============================================================

-- ┌──────────────────────────────────────────────────────────────┐
-- │  STEP 1: Add new columns (safe – won't fail if they exist)  │
-- └──────────────────────────────────────────────────────────────┘

ALTER TABLE users ADD COLUMN IF NOT EXISTS google_id VARCHAR(128);
ALTER TABLE users ADD COLUMN IF NOT EXISTS mobile_number VARCHAR(15);
ALTER TABLE users ADD COLUMN IF NOT EXISTS postal_code VARCHAR(10);
ALTER TABLE users ADD COLUMN IF NOT EXISTS address TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS company_name VARCHAR(150);
ALTER TABLE users ADD COLUMN IF NOT EXISTS profile_completed BOOLEAN DEFAULT FALSE;

-- ┌──────────────────────────────────────────────────────────────┐
-- │  STEP 2: Migrate data from legacy columns to new columns    │
-- └──────────────────────────────────────────────────────────────┘

-- Copy phone → mobile_number (only if mobile_number is empty)
UPDATE users
SET mobile_number = phone
WHERE phone IS NOT NULL
  AND (mobile_number IS NULL OR mobile_number = '');

-- Copy village → address (only if address is empty)
UPDATE users
SET address = village
WHERE village IS NOT NULL
  AND (address IS NULL OR address = '');

-- Copy organization → company_name (only if company_name is empty)
UPDATE users
SET company_name = organization
WHERE organization IS NOT NULL
  AND (company_name IS NULL OR company_name = '');

-- Mark existing users with sufficient profile data as profile_completed
UPDATE users
SET profile_completed = TRUE
WHERE name IS NOT NULL
  AND name != ''
  AND (mobile_number IS NOT NULL AND mobile_number != '')
  AND (district IS NOT NULL AND district != '');

-- ┌──────────────────────────────────────────────────────────────┐
-- │  STEP 3: Add constraints and indexes on new columns         │
-- └──────────────────────────────────────────────────────────────┘

-- Unique constraints
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_google_id ON users(google_id) WHERE google_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_mobile_number ON users(mobile_number) WHERE mobile_number IS NOT NULL;

-- General indexes for faster lookups
CREATE INDEX IF NOT EXISTS idx_users_profile_completed ON users(profile_completed);
CREATE INDEX IF NOT EXISTS idx_users_postal_code ON users(postal_code);

-- ┌──────────────────────────────────────────────────────────────┐
-- │  STEP 4: Drop legacy columns                                │
-- │  ⚠️  DESTRUCTIVE – Only run after verifying data migration  │
-- │  You can comment these out first and run them later          │
-- └──────────────────────────────────────────────────────────────┘

-- Drop old indexes first
DROP INDEX IF EXISTS idx_users_phone;

-- Drop legacy columns
ALTER TABLE users DROP COLUMN IF EXISTS phone;
ALTER TABLE users DROP COLUMN IF EXISTS password_hash;
ALTER TABLE users DROP COLUMN IF EXISTS village;
ALTER TABLE users DROP COLUMN IF EXISTS organization;

-- ┌──────────────────────────────────────────────────────────────┐
-- │  STEP 5: Update RLS policies (optional – if using Supabase) │
-- └──────────────────────────────────────────────────────────────┘

-- Drop old policies if they exist (will not fail if they don't)
DROP POLICY IF EXISTS users_select_own ON users;
DROP POLICY IF EXISTS users_update_own ON users;

-- Recreate user policies based on firebase_uid
CREATE POLICY users_select_own ON users
    FOR SELECT USING (auth.uid()::text = firebase_uid);

CREATE POLICY users_update_own ON users
    FOR UPDATE USING (auth.uid()::text = firebase_uid)
    WITH CHECK (auth.uid()::text = firebase_uid);

-- ============================================================
-- VERIFICATION QUERIES (run these after migration to confirm)
-- ============================================================

-- Check the new table structure:
-- SELECT column_name, data_type, is_nullable
-- FROM information_schema.columns
-- WHERE table_name = 'users'
-- ORDER BY ordinal_position;

-- Verify legacy columns are gone:
-- SELECT column_name FROM information_schema.columns
-- WHERE table_name = 'users'
--   AND column_name IN ('phone', 'password_hash', 'village', 'organization');
-- (Should return 0 rows)

-- Check profile_completed status:
-- SELECT
--   COUNT(*) AS total_users,
--   COUNT(*) FILTER (WHERE profile_completed = TRUE) AS completed,
--   COUNT(*) FILTER (WHERE profile_completed = FALSE OR profile_completed IS NULL) AS incomplete
-- FROM users;

-- Check migrated data:
-- SELECT id, email, name, mobile_number, district, postal_code, address, company_name, profile_completed
-- FROM users
-- LIMIT 10;
