-- ============================================================
-- Migration 003: Auth Overhaul – Google-only + Profile Completion
-- Run against Supabase PostgreSQL
-- ============================================================

-- 1. Add new columns
ALTER TABLE users ADD COLUMN IF NOT EXISTS google_id VARCHAR(128) UNIQUE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS mobile_number VARCHAR(15) UNIQUE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS postal_code VARCHAR(10);
ALTER TABLE users ADD COLUMN IF NOT EXISTS address TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS company_name VARCHAR(150);
ALTER TABLE users ADD COLUMN IF NOT EXISTS profile_completed BOOLEAN DEFAULT FALSE;

-- 2. Create index on google_id
CREATE INDEX IF NOT EXISTS idx_users_google_id ON users(google_id);
CREATE INDEX IF NOT EXISTS idx_users_mobile_number ON users(mobile_number);

-- 3. Migrate data from legacy columns (safe – keeps data)
UPDATE users SET mobile_number = phone WHERE phone IS NOT NULL AND mobile_number IS NULL;
UPDATE users SET address = village WHERE village IS NOT NULL AND address IS NULL;
UPDATE users SET company_name = organization WHERE organization IS NOT NULL AND company_name IS NULL;

-- 4. Mark existing users with profiles as complete (they have at least name + email)
UPDATE users SET profile_completed = TRUE WHERE email IS NOT NULL AND name IS NOT NULL AND name != 'User';

-- 5. Deprecate old columns (rename, don't drop – safety net)
-- Only run these once you've verified the migration worked:
-- ALTER TABLE users RENAME COLUMN password_hash TO _deprecated_password_hash;
-- ALTER TABLE users RENAME COLUMN phone TO _deprecated_phone;
-- ALTER TABLE users RENAME COLUMN village TO _deprecated_village;
-- ALTER TABLE users RENAME COLUMN organization TO _deprecated_organization;
