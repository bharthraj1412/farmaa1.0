-- ============================================================
-- Farmaa Database Sync – Supabase Schema Update
-- Syncs Supabase tables with SQLAlchemy models.py
-- ============================================================

-- 1. Update USERS Table
DO $$
BEGIN
    -- Add email column
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='email') THEN
        ALTER TABLE users ADD COLUMN email VARCHAR(255);
        CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email_unique ON users(email);
    END IF;

    -- Add password_hash column
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='password_hash') THEN
        ALTER TABLE users ADD COLUMN password_hash VARCHAR(255);
    END IF;

    -- Add profile_image column
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='profile_image') THEN
        ALTER TABLE users ADD COLUMN profile_image VARCHAR(500);
    END IF;
END $$;

-- Make phone nullable to support email-only registration/Google login
ALTER TABLE users ALTER COLUMN phone DROP NOT NULL;

-- 2. Update ORDERS Table
DO $$
BEGIN
    -- Add razorpay_order_id
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='orders' AND column_name='razorpay_order_id') THEN
        ALTER TABLE orders ADD COLUMN razorpay_order_id VARCHAR(100);
    END IF;

    -- Add razorpay_signature
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='orders' AND column_name='razorpay_signature') THEN
        ALTER TABLE orders ADD COLUMN razorpay_signature VARCHAR(200);
    END IF;
END $$;

-- 3. Verify Indexes
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_orders_razorpay_order_id ON orders(razorpay_order_id);

-- Success Message
SELECT 'Schema sync successful! Database is now aligned with models.py.' as info;
