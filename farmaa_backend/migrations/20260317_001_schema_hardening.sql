-- ============================================================
-- Migration: 20260317_001_schema_hardening
-- Farmaa – Add constraints, indexes, is_active column
-- Safe: backward-compatible (adds nullable columns, then backfills)
-- ============================================================

-- 1. Add is_active to crops (soft-delete support)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='crops' AND column_name='is_active') THEN
        ALTER TABLE crops ADD COLUMN is_active BOOLEAN DEFAULT TRUE;
    END IF;
END $$;

-- 2. Backfill: all existing crops are active
UPDATE crops SET is_active = TRUE WHERE is_active IS NULL;

-- 3. Add CHECK constraints (safe – will not fail on existing compliant data)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.constraint_column_usage
                   WHERE table_name='crops' AND constraint_name='chk_crops_stock_nonneg') THEN
        ALTER TABLE crops ADD CONSTRAINT chk_crops_stock_nonneg CHECK (stock_kg >= 0);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.constraint_column_usage
                   WHERE table_name='orders' AND constraint_name='chk_orders_qty_positive') THEN
        ALTER TABLE orders ADD CONSTRAINT chk_orders_qty_positive CHECK (quantity_kg > 0);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.constraint_column_usage
                   WHERE table_name='orders' AND constraint_name='chk_orders_total_nonneg') THEN
        ALTER TABLE orders ADD CONSTRAINT chk_orders_total_nonneg CHECK (total_amount >= 0);
    END IF;
END $$;

-- 4. Performance indexes for marketplace queries
CREATE INDEX IF NOT EXISTS idx_crops_marketplace
    ON crops (is_available, is_active, status)
    WHERE is_available = TRUE AND is_active = TRUE;

CREATE INDEX IF NOT EXISTS idx_crops_category ON crops (category);

CREATE INDEX IF NOT EXISTS idx_orders_status ON orders (status);
CREATE INDEX IF NOT EXISTS idx_orders_crop_id ON orders (crop_id);

-- 5. Ensure updated_at trigger exists
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_users_updated_at') THEN
        CREATE TRIGGER trg_users_updated_at BEFORE UPDATE ON users
        FOR EACH ROW EXECUTE FUNCTION update_updated_at();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_crops_updated_at') THEN
        CREATE TRIGGER trg_crops_updated_at BEFORE UPDATE ON crops
        FOR EACH ROW EXECUTE FUNCTION update_updated_at();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_orders_updated_at') THEN
        CREATE TRIGGER trg_orders_updated_at BEFORE UPDATE ON orders
        FOR EACH ROW EXECUTE FUNCTION update_updated_at();
    END IF;
END $$;

-- 6. Stock management trigger (DB-level safety net)
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

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_crop_stock_check') THEN
        CREATE TRIGGER trg_crop_stock_check BEFORE UPDATE ON crops
        FOR EACH ROW EXECUTE FUNCTION check_crop_stock();
    END IF;
END $$;

-- 7. Notify on inventory change (Supabase Realtime)
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

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_notify_stock_change') THEN
        CREATE TRIGGER trg_notify_stock_change AFTER UPDATE ON crops
        FOR EACH ROW EXECUTE FUNCTION notify_stock_change();
    END IF;
END $$;

-- ============================================================
-- ROLLBACK (run these to revert if needed):
-- ALTER TABLE crops DROP COLUMN IF EXISTS is_active;
-- ALTER TABLE crops DROP CONSTRAINT IF EXISTS chk_crops_stock_nonneg;
-- ALTER TABLE orders DROP CONSTRAINT IF EXISTS chk_orders_qty_positive;
-- ALTER TABLE orders DROP CONSTRAINT IF EXISTS chk_orders_total_nonneg;
-- DROP INDEX IF EXISTS idx_crops_marketplace;
-- DROP INDEX IF EXISTS idx_crops_category;
-- DROP INDEX IF EXISTS idx_orders_status;
-- DROP INDEX IF EXISTS idx_orders_crop_id;
-- ============================================================
