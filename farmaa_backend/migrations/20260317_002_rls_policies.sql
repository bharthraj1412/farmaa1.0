-- ============================================================
-- Migration: 20260317_002_rls_policies
-- Farmaa – Row Level Security policies for Supabase
-- NOTE: RLS is enforced by Supabase direct access (PostgREST).
-- The FastAPI backend connects via the service_role key which
-- bypasses RLS. These policies protect against direct client
-- access through Supabase JS/Flutter SDK.
-- ============================================================

-- ── Enable RLS ──────────────────────────────────────────────
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE crops ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE market_prices ENABLE ROW LEVEL SECURITY;

-- ── USERS ───────────────────────────────────────────────────

-- Users can read their own profile
CREATE POLICY users_select_own ON users
    FOR SELECT USING (auth.uid()::text = firebase_uid);

-- Users can update their own profile
CREATE POLICY users_update_own ON users
    FOR UPDATE USING (auth.uid()::text = firebase_uid)
    WITH CHECK (auth.uid()::text = firebase_uid);

-- ── CROPS ───────────────────────────────────────────────────

-- Anyone can read available crops (marketplace)
CREATE POLICY crops_select_marketplace ON crops
    FOR SELECT USING (is_available = TRUE AND is_active = TRUE);

-- Farmers can read all their own crops (including inactive)
CREATE POLICY crops_select_own ON crops
    FOR SELECT USING (
        farmer_id IN (SELECT id FROM users WHERE firebase_uid = auth.uid()::text)
    );

-- Farmers can insert their own crops
CREATE POLICY crops_insert_own ON crops
    FOR INSERT WITH CHECK (
        farmer_id IN (SELECT id FROM users WHERE firebase_uid = auth.uid()::text)
    );

-- Farmers can update their own crops
CREATE POLICY crops_update_own ON crops
    FOR UPDATE USING (
        farmer_id IN (SELECT id FROM users WHERE firebase_uid = auth.uid()::text)
    ) WITH CHECK (
        farmer_id IN (SELECT id FROM users WHERE firebase_uid = auth.uid()::text)
    );

-- Farmers can delete (soft-delete) their own crops
CREATE POLICY crops_delete_own ON crops
    FOR DELETE USING (
        farmer_id IN (SELECT id FROM users WHERE firebase_uid = auth.uid()::text)
    );

-- ── ORDERS ──────────────────────────────────────────────────

-- Buyers and farmers can see their own orders
CREATE POLICY orders_select_own ON orders
    FOR SELECT USING (
        buyer_id IN (SELECT id FROM users WHERE firebase_uid = auth.uid()::text)
        OR farmer_id IN (SELECT id FROM users WHERE firebase_uid = auth.uid()::text)
    );

-- Authenticated users can create orders (buyer check done in backend)
CREATE POLICY orders_insert_authenticated ON orders
    FOR INSERT WITH CHECK (
        buyer_id IN (SELECT id FROM users WHERE firebase_uid = auth.uid()::text)
    );

-- Buyers and farmers can update order status (role checks in backend)
CREATE POLICY orders_update_own ON orders
    FOR UPDATE USING (
        buyer_id IN (SELECT id FROM users WHERE firebase_uid = auth.uid()::text)
        OR farmer_id IN (SELECT id FROM users WHERE firebase_uid = auth.uid()::text)
    );

-- ── MARKET PRICES ───────────────────────────────────────────

-- Anyone can read market prices
CREATE POLICY market_prices_select_all ON market_prices
    FOR SELECT USING (TRUE);

-- Only service role (backend) can insert/update market prices
-- (No user-facing write policy needed; backend uses service_role)

-- ============================================================
-- ROLLBACK:
-- DROP POLICY IF EXISTS users_select_own ON users;
-- DROP POLICY IF EXISTS users_update_own ON users;
-- DROP POLICY IF EXISTS crops_select_marketplace ON crops;
-- DROP POLICY IF EXISTS crops_select_own ON crops;
-- DROP POLICY IF EXISTS crops_insert_own ON crops;
-- DROP POLICY IF EXISTS crops_update_own ON crops;
-- DROP POLICY IF EXISTS crops_delete_own ON crops;
-- DROP POLICY IF EXISTS orders_select_own ON orders;
-- DROP POLICY IF EXISTS orders_insert_authenticated ON orders;
-- DROP POLICY IF EXISTS orders_update_own ON orders;
-- DROP POLICY IF EXISTS market_prices_select_all ON market_prices;
-- ALTER TABLE users DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE crops DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE orders DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE market_prices DISABLE ROW LEVEL SECURITY;
-- ============================================================
