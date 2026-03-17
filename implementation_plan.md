# Farmaa Production-Ready Fix

## A. Root Cause Summary

1. **Crop listing crash (frontend):** `crop_service.dart:31` casts `response.data` as `List<dynamic>`, but the backend returns `{"total": N, "items": [...]}`. Buyers see an error instead of the marketplace.
2. **Profile fields silently dropped:** [auth_router.py](file:///g:/farmaa%20project/farmaa_backend/routers/auth_router.py) PATCH `/auth/me` handler processes `name`, [phone](file:///g:/farmaa%20project/farmaa_backend/schemas.py#16-25), [email](file:///g:/farmaa%20project/farmaa_backend/schemas.py#77-84) but **ignores** `village`, `district`, and `org` from [UserUpdate](file:///g:/farmaa%20project/farmaa_backend/schemas.py#108-115) schema. Updates are lost.
3. **Inventory race condition:** [orders_router.py](file:///g:/farmaa%20project/farmaa_backend/routers/orders_router.py) checks `body.quantity_kg > crop.stock_kg` then decrements `crop.stock_kg -= body.quantity_kg` without `SELECT ... FOR UPDATE`. Two concurrent orders can over-sell.
4. **Auth dependency opens rogue DB session:** `auth.py:get_current_user_id()` calls `next(get_db())` manually (line 124), creating a session outside FastAPI's dependency injection—potential session leak.
5. **JWT not stored from backend:** The Flutter app stores the raw Firebase ID token (`idToken`) instead of the backend-issued [access_token](file:///g:/farmaa%20project/farmaa_backend/auth.py#42-55) from `/auth/firebase`. The [_AuthInterceptor](file:///g:/farmaa%20project/farmaa_mobile/lib/core/api/api_client.dart#97-136) then sends the Firebase token directly, forcing the backend to verify Firebase on every request.
6. **[UserUpdate](file:///g:/farmaa%20project/farmaa_backend/schemas.py#108-115) missing fields in handler:** Schema defines `village`, `district`, `org`, but the PATCH endpoint only updates `name`, [phone](file:///g:/farmaa%20project/farmaa_backend/schemas.py#16-25), [email](file:///g:/farmaa%20project/farmaa_backend/schemas.py#77-84). The other fields are silently dropped.

---

## B. Two Repair Options

### Option 1: Minimal Quick-Fix (Low Risk, ~2 hours)
| Change | File | Risk |
|--------|------|------|
| Fix crop response parsing | [crop_service.dart](file:///g:/farmaa%20project/farmaa_mobile/lib/core/services/crop_service.dart) | Low |
| Fix profile PATCH handler to persist village/district/org | [auth_router.py](file:///g:/farmaa%20project/farmaa_backend/routers/auth_router.py) | Low |
| Add `FOR UPDATE` lock on crop row in order creation | [orders_router.py](file:///g:/farmaa%20project/farmaa_backend/routers/orders_router.py) | Low |
| Store backend JWT instead of Firebase token | [auth_service.dart](file:///g:/farmaa%20project/farmaa_mobile/lib/core/services/auth_service.dart) | Low |

**Estimated risk:** Low. No schema changes. No migration needed. Backward compatible.

### Option 2: Recommended Full-Fix (Medium Risk, ~6 hours)
Everything in Option 1, **plus:**
| Change | File | Risk |
|--------|------|------|
| Add `is_active` column to crops for soft-delete | Migration SQL | Low |
| RLS policies for Supabase | `policies.sql` | Medium |
| Refactor [get_current_user_id](file:///g:/farmaa%20project/farmaa_backend/auth.py#100-142) to avoid rogue sessions | [auth.py](file:///g:/farmaa%20project/farmaa_backend/auth.py) | Low |
| Add inventory check constraint | Migration SQL | Low |
| Comprehensive pytest suite (auth, crops, orders, race) | `tests/` | Low |
| `DEPLOYMENT.md` + `PR_CHECKLIST.md` | Docs | None |

**Estimated risk:** Medium. Schema migration requires staging test first.

---

## C. Implementation Artifacts (Recommended Full-Fix)

### C.1 SQL Migration

#### [NEW] [20260317_001_schema_hardening.sql](file:///g:/farmaa%20project/farmaa_backend/migrations/20260317_001_schema_hardening.sql)
- Add `is_active BOOLEAN DEFAULT TRUE` to [crops](file:///g:/farmaa%20project/farmaa_backend/routers/crops_router.py#29-63) table
- Add `CHECK (stock_kg >= 0)` constraint on [crops](file:///g:/farmaa%20project/farmaa_backend/routers/crops_router.py#29-63)
- Add `CHECK (quantity_kg > 0)` constraint on [orders](file:///g:/farmaa%20project/farmaa_backend/routers/orders_router.py#108-115)
- Add indexes on [crops(is_available, status)](file:///g:/farmaa%20project/farmaa_backend/routers/crops_router.py#29-63) for marketplace queries
- Backfill: set `is_active = TRUE` for all existing crops

### C.2 RLS Policies

#### [NEW] [20260317_002_rls_policies.sql](file:///g:/farmaa%20project/farmaa_backend/migrations/20260317_002_rls_policies.sql)
- Enable RLS on `users`, [crops](file:///g:/farmaa%20project/farmaa_backend/routers/crops_router.py#29-63), [orders](file:///g:/farmaa%20project/farmaa_backend/routers/orders_router.py#108-115), [market_prices](file:///g:/farmaa%20project/farmaa_backend/routers/market_router.py#42-68)
- Public read on [crops](file:///g:/farmaa%20project/farmaa_backend/routers/crops_router.py#29-63) where `is_available = TRUE`
- Owner-only write on [crops](file:///g:/farmaa%20project/farmaa_backend/routers/crops_router.py#29-63) (matched by `farmer_id`)
- Authenticated read on own orders, write only for create

---

### C.3 Backend Code Patches

#### [MODIFY] [auth_router.py](file:///g:/farmaa%20project/farmaa_backend/routers/auth_router.py)
- Fix PATCH `/auth/me`: add handling for `body.village`, `body.district`, `body.org`

#### [MODIFY] [auth.py](file:///g:/farmaa%20project/farmaa_backend/auth.py)
- Refactor [get_current_user_id()](file:///g:/farmaa%20project/farmaa_backend/auth.py#100-142) to avoid manual `next(get_db())` call. Use a simpler approach: try backend JWT first (fast HS256 verify), then fall back to Firebase only if JWT fails.

#### [MODIFY] [orders_router.py](file:///g:/farmaa%20project/farmaa_backend/routers/orders_router.py)
- Use `SELECT ... FOR UPDATE` via `with_for_update()` on the crop query to prevent race conditions
- Use atomic `UPDATE crops SET stock_kg = stock_kg - :qty WHERE id = :id AND stock_kg >= :qty RETURNING stock_kg` pattern

---

### C.4 Frontend Patches

#### [MODIFY] [crop_service.dart](file:///g:/farmaa%20project/farmaa_mobile/lib/core/services/crop_service.dart)
- Fix [getCrops()](file:///g:/farmaa%20project/farmaa_mobile/lib/core/services/crop_service.dart#15-36): parse `response.data['items']` instead of `response.data` directly

#### [MODIFY] [auth_service.dart](file:///g:/farmaa%20project/farmaa_mobile/lib/core/services/auth_service.dart)
- Store backend [access_token](file:///g:/farmaa%20project/farmaa_backend/auth.py#42-55) from `/auth/firebase` response instead of raw Firebase `idToken`

---

### C.5 Tests

#### [MODIFY] [conftest.py](file:///g:/farmaa%20project/farmaa_backend/tests/conftest.py)
- Add helper to create authenticated test users with JWT tokens

#### [MODIFY] [test_auth.py](file:///g:/farmaa%20project/farmaa_backend/tests/test_auth.py)
- Add test for profile update persisting village/district/org

#### [NEW] [test_orders.py](file:///g:/farmaa%20project/farmaa_backend/tests/test_orders.py)
- Test order creation with valid stock
- Test order rejection when stock insufficient
- Test self-purchase prevention

#### [NEW] [verify.sh](file:///g:/farmaa%20project/farmaa_backend/verify.sh)
- Curl commands for manual smoke testing

---

### C.6 Docs

#### [NEW] [DEPLOYMENT.md](file:///g:/farmaa%20project/DEPLOYMENT.md)
#### [NEW] [PR_CHECKLIST.md](file:///g:/farmaa%20project/PR_CHECKLIST.md)

---

## Verification Plan

### Automated Tests
Run from `g:\farmaa project\farmaa_backend`:
```
python -m pytest tests/ -v --tb=short
```

Tests to verify:
1. `test_register_creates_user_and_returns_token` — existing, confirms registration works
2. `test_login_success` / `test_login_invalid_password` — existing, confirms login
3. `test_profile_update_persists_all_fields` — **new**, confirms village/district/org persist
4. `test_crops_list_returns_all_roles` — existing, confirms marketplace visibility
5. `test_create_order_decrements_stock` — **new**, confirms atomic decrement
6. `test_create_order_insufficient_stock_rejected` — **new**, confirms stock guard
7. `test_self_purchase_prevented` — **new**, confirms farmer can't buy own crop

### Manual Verification
1. After applying the `crop_service.dart` fix, open the Market tab in the Flutter app — crops should load without error
2. After applying the `auth_service.dart` fix, register a new user — subsequent API calls should use the backend JWT (visible in Dio logs as a shorter HS256 token instead of the long Firebase token)
3. After applying the profile fix, update your phone/village/district in Profile screen, close and reopen the app, and confirm the values persist

---

## D. Security Review Checklist
- [ ] `SECRET_KEY` is set to a strong random value in production (not dev default)
- [ ] Firebase credentials JSON stored as env var, not committed to git
- [ ] Backend JWT expiry is 7 days (acceptable for mobile app; consider 24h with refresh)
- [ ] Rate limiting via `slowapi` is active (200/min default)
- [ ] `flutter_secure_storage` used for JWT; `SharedPreferences` used only for non-sensitive user display data
- [ ] Razorpay keys in `.env` file, not hardcoded (currently hardcoded as fallback — should be removed for production)
- [ ] CORS restricted to `farmaa1-0.vercel.app` in production mode
