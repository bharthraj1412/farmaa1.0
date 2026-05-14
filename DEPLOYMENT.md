# Deployment Plan – Farmaa Production Fix

## Pre-Deployment Checklist

- [ ] All tests pass locally: `cd farmaa_backend && python -m pytest tests/ -v`
- [ ] `SECRET_KEY` env var set to a strong random string (32+ characters)
- [ ] `DATABASE_URL` env var set to Supabase connection string
- [ ] `FIREBASE_CREDENTIALS_JSON` env var set (or `FIREBASE_CREDENTIALS_PATH`)
- [ ] Razorpay keys set via env vars (not hardcoded fallbacks)

## Step-by-Step Deployment

### 1. Run Schema Migration (Staging First)
```bash
# Connect to Supabase SQL editor or psql
psql "$DATABASE_URL" -f migrations/20260317_001_schema_hardening.sql
```
**Verify:**
```sql
SELECT column_name FROM information_schema.columns WHERE table_name='crops' AND column_name='is_active';
-- Should return 1 row
```

### 2. Apply RLS Policies
```bash
psql "$DATABASE_URL" -f migrations/20260317_002_rls_policies.sql
```
> **Note:** RLS only affects Supabase client SDK access. FastAPI uses `service_role` key which bypasses RLS.

### 3. Deploy Backend
```bash
# If on Vercel:
git add -A && git commit -m "fix: production hardening – auth, orders, profile"
git push origin main
# Vercel will auto-deploy

# If on Render:
git push origin main
# Render will auto-deploy
```

### 4. Smoke Test Production
```bash
BASE_URL=https://farmaa1-0.vercel.app ./verify.sh
```

### 5. Deploy Mobile App
- Build release APK/AAB with the `auth_service.dart` and `crop_service.dart` fixes
- Test on physical device before publishing to Play Store

## Rollback Plan

### Schema Rollback
```sql
ALTER TABLE crops DROP COLUMN IF EXISTS is_active;
ALTER TABLE crops DROP CONSTRAINT IF EXISTS chk_crops_stock_nonneg;
ALTER TABLE orders DROP CONSTRAINT IF EXISTS chk_orders_qty_positive;
ALTER TABLE orders DROP CONSTRAINT IF EXISTS chk_orders_total_nonneg;
DROP INDEX IF EXISTS idx_crops_marketplace;
```

### RLS Rollback
```sql
DROP POLICY IF EXISTS users_select_own ON users;
DROP POLICY IF EXISTS users_update_own ON users;
DROP POLICY IF EXISTS crops_select_marketplace ON crops;
DROP POLICY IF EXISTS crops_select_own ON crops;
DROP POLICY IF EXISTS crops_insert_own ON crops;
DROP POLICY IF EXISTS crops_update_own ON crops;
DROP POLICY IF EXISTS crops_delete_own ON crops;
DROP POLICY IF EXISTS orders_select_own ON orders;
DROP POLICY IF EXISTS orders_insert_authenticated ON orders;
DROP POLICY IF EXISTS orders_update_own ON orders;
DROP POLICY IF EXISTS market_prices_select_all ON market_prices;
ALTER TABLE users DISABLE ROW LEVEL SECURITY;
ALTER TABLE crops DISABLE ROW LEVEL SECURITY;
ALTER TABLE orders DISABLE ROW LEVEL SECURITY;
ALTER TABLE market_prices DISABLE ROW LEVEL SECURITY;
```

### Backend Rollback
```bash
git revert HEAD  # Reverts the last commit
git push origin main
```

## Downtime Estimate
- **Zero downtime**: All migrations are additive (no column drops/renames)
- Mobile app gracefully handles both old `/auth/firebase` and new `/auth/exchange_token` endpoints
