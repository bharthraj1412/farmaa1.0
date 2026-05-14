-- ============================================================
-- FARMAA – Full Database Schema (Firebase Auth Version)
-- Optimized for Supabase PostgreSQL
-- ============================================================

-- 0. Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. Drop existing tables (order matters)
DROP TABLE IF EXISTS market_prices CASCADE;
DROP TABLE IF EXISTS orders CASCADE;
DROP TABLE IF EXISTS crops CASCADE;
DROP TABLE IF EXISTS users CASCADE;

-- 2. Users table
CREATE TABLE users (
    id            VARCHAR PRIMARY KEY DEFAULT gen_random_uuid()::text,
    firebase_uid  VARCHAR(128) UNIQUE,
    phone         VARCHAR(15) UNIQUE,
    email         VARCHAR(255) UNIQUE,
    password_hash VARCHAR(255),
    name          VARCHAR(100) NOT NULL,
    role          VARCHAR(10) NOT NULL DEFAULT 'buyer',
    village       VARCHAR(100),
    district      VARCHAR(100),
    organization  VARCHAR(150),
    profile_image VARCHAR(500),
    is_verified   BOOLEAN DEFAULT FALSE,
    created_at    TIMESTAMP DEFAULT NOW(),
    updated_at    TIMESTAMP DEFAULT NOW()
);

-- 3. Crops table
CREATE TABLE crops (
    id                VARCHAR PRIMARY KEY DEFAULT gen_random_uuid()::text,
    farmer_id         VARCHAR NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name              VARCHAR(100) NOT NULL,
    variety           VARCHAR(100),
    description       TEXT,
    category          VARCHAR(50) DEFAULT 'Other',
    price_per_kg      FLOAT NOT NULL,
    stock_kg          FLOAT NOT NULL DEFAULT 0 CHECK (stock_kg >= 0),
    min_order_kg      FLOAT DEFAULT 50,
    unit              VARCHAR(10) DEFAULT 'kg',
    status            VARCHAR(20) DEFAULT 'approved',
    is_available      BOOLEAN DEFAULT TRUE,
    is_active         BOOLEAN DEFAULT TRUE,
    image_url         VARCHAR(500),
    location          VARCHAR(200),
    last_price_update TIMESTAMP DEFAULT NOW(),
    created_at        TIMESTAMP DEFAULT NOW(),
    updated_at        TIMESTAMP DEFAULT NOW()
);

-- 4. Orders table
CREATE TABLE orders (
    id                 VARCHAR PRIMARY KEY DEFAULT gen_random_uuid()::text,
    buyer_id           VARCHAR NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    farmer_id          VARCHAR NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    crop_id            VARCHAR NOT NULL REFERENCES crops(id) ON DELETE CASCADE,
    quantity_kg        FLOAT NOT NULL CHECK (quantity_kg > 0),
    total_amount       FLOAT NOT NULL CHECK (total_amount >= 0),
    delivery_address   TEXT,
    status             VARCHAR(20) DEFAULT 'pending',
    payment_id         VARCHAR(100),
    razorpay_order_id  VARCHAR(100),
    razorpay_signature VARCHAR(200),
    created_at         TIMESTAMP DEFAULT NOW(),
    updated_at         TIMESTAMP DEFAULT NOW()
);

-- 5. Market Prices table
CREATE TABLE market_prices (
    id           VARCHAR PRIMARY KEY DEFAULT gen_random_uuid()::text,
    crop_name    VARCHAR(100) NOT NULL,
    category     VARCHAR(50),
    price_per_kg FLOAT NOT NULL,
    market_name  VARCHAR(150),
    source       VARCHAR(100) DEFAULT 'manual',
    recorded_at  TIMESTAMP DEFAULT NOW()
);

-- 6. Indexes
CREATE INDEX idx_users_phone ON users(phone);
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_firebase_uid ON users(firebase_uid);
CREATE INDEX idx_crops_farmer_id ON crops(farmer_id);
CREATE INDEX idx_crops_category ON crops(category);
CREATE INDEX idx_crops_marketplace ON crops(is_available, is_active, status) WHERE is_available = TRUE AND is_active = TRUE;
CREATE INDEX idx_orders_buyer_id ON orders(buyer_id);
CREATE INDEX idx_orders_farmer_id ON orders(farmer_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_orders_crop_id ON orders(crop_id);
CREATE INDEX idx_market_prices_crop_name ON market_prices(crop_name);

-- 7. Triggers & Functions
-- Update updated_at
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_crops_updated_at BEFORE UPDATE ON crops FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_orders_updated_at BEFORE UPDATE ON orders FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Stock management
CREATE OR REPLACE FUNCTION check_crop_stock()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.stock_kg <= 0 THEN
        NEW.is_available = FALSE;
        NEW.status = 'sold_out';
        NEW.stock_kg = GREATEST(NEW.stock_kg, 0);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_crop_stock_check BEFORE UPDATE ON crops FOR EACH ROW EXECUTE FUNCTION check_crop_stock();

-- Price tracking
CREATE OR REPLACE FUNCTION track_price_change()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.price_per_kg <> OLD.price_per_kg THEN
        NEW.last_price_update = NOW();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_crop_price_change BEFORE UPDATE ON crops FOR EACH ROW EXECUTE FUNCTION track_price_change();

-- Realtime updates
CREATE OR REPLACE FUNCTION notify_stock_change()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.stock_kg IS DISTINCT FROM NEW.stock_kg THEN
        PERFORM pg_notify('stock_change', json_build_object(
            'crop_id', NEW.id,
            'old_stock', OLD.stock_kg,
            'new_stock', NEW.stock_kg,
            'is_available', NEW.is_available
        )::text);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_notify_stock_change AFTER UPDATE ON crops FOR EACH ROW EXECUTE FUNCTION notify_stock_change();

-- 8. Seed Data
INSERT INTO market_prices (crop_name, category, price_per_kg, market_name, source) VALUES
  ('Wheat',        'Grains',  28.50, 'Chennai Koyambedu',  'agmarknet'),
  ('Rice',         'Grains',  42.00, 'Madurai Market',     'agmarknet'),
  ('Ragi',         'Millets', 35.00, 'Coimbatore APMC',    'agmarknet'),
  ('Toor Dal',     'Pulses',  95.00, 'Chennai Koyambedu',  'agmarknet');

-- ============================================================
-- 9. Row Level Security Policies
-- ============================================================

ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE crops ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE market_prices ENABLE ROW LEVEL SECURITY;

-- ── USERS ───────────────────────────────────────────────────
CREATE POLICY users_select_own ON users
    FOR SELECT USING (auth.uid()::text = firebase_uid);
CREATE POLICY users_update_own ON users
    FOR UPDATE USING (auth.uid()::text = firebase_uid)
    WITH CHECK (auth.uid()::text = firebase_uid);

-- ── CROPS ───────────────────────────────────────────────────
CREATE POLICY crops_select_marketplace ON crops
    FOR SELECT USING (is_available = TRUE AND is_active = TRUE);

CREATE POLICY crops_select_own ON crops
    FOR SELECT USING (farmer_id IN (SELECT id FROM users WHERE firebase_uid = auth.uid()::text));

CREATE POLICY crops_insert_own ON crops
    FOR INSERT WITH CHECK (farmer_id IN (SELECT id FROM users WHERE firebase_uid = auth.uid()::text));

CREATE POLICY crops_update_own ON crops
    FOR UPDATE USING (farmer_id IN (SELECT id FROM users WHERE firebase_uid = auth.uid()::text))
    WITH CHECK (farmer_id IN (SELECT id FROM users WHERE firebase_uid = auth.uid()::text));

CREATE POLICY crops_delete_own ON crops
    FOR DELETE USING (farmer_id IN (SELECT id FROM users WHERE firebase_uid = auth.uid()::text));

-- ── ORDERS ──────────────────────────────────────────────────
CREATE POLICY orders_select_own ON orders
    FOR SELECT USING (
        buyer_id IN (SELECT id FROM users WHERE firebase_uid = auth.uid()::text)
        OR farmer_id IN (SELECT id FROM users WHERE firebase_uid = auth.uid()::text)
    );

CREATE POLICY orders_insert_authenticated ON orders
    FOR INSERT WITH CHECK (buyer_id IN (SELECT id FROM users WHERE firebase_uid = auth.uid()::text));

CREATE POLICY orders_update_own ON orders
    FOR UPDATE USING (
        buyer_id IN (SELECT id FROM users WHERE firebase_uid = auth.uid()::text)
        OR farmer_id IN (SELECT id FROM users WHERE firebase_uid = auth.uid()::text)
    );

-- ── MARKET PRICES ───────────────────────────────────────────
CREATE POLICY market_prices_select_all ON market_prices
    FOR SELECT USING (TRUE);
