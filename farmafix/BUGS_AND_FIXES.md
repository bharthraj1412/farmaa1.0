# Farmaa – Bug Analysis & Fix Report

## Summary

| Layer | Bugs Fixed | Improvements |
|-------|-----------|--------------|
| Backend | 6 | 3 |
| Flutter | 4 | 2 |

---

## 🔴 Critical Bugs (would break the app in production)

### 1. Market Prices district filter completely broken
**File:** `farmaa_mobile/lib/features/market/screens/market_prices_screen.dart`

```dart
// ❌ BEFORE – `final` means it can never change; dropdown has no effect
final String _selectedDistrict = 'Madurai';

onChanged: (v) {
  if (v != null) {
    _fetchPrices();          // district not updated — always fetches Madurai
  }
},

// ✅ AFTER
String _selectedDistrict = 'Madurai';   // mutable

onChanged: (v) {
  if (v != null && v != _selectedDistrict) {
    setState(() => _selectedDistrict = v);  // update state
    _fetchPrices();                          // then refetch
  }
},
```

---

### 2. Token expiry mismatch → users logged out after 1 hour
**File:** `farmaa_mobile/lib/core/services/auth_service.dart`

The backend issues 7-day JWTs (`ACCESS_TOKEN_EXPIRY_MINUTES = 10080`), but
`ApiClient.saveBackendToken` defaults to `expiresInSeconds: 3600` (1 hour).
After 1 hour `getStoredToken()` returns null, the interceptor rejects every
request, and the user is forced to re-login.

```dart
// ❌ BEFORE
await ApiClient.instance.saveBackendToken(backendToken);  // defaults to 1 h

// ✅ AFTER – read expires_in from the response (backend now returns it)
final expiresIn = (data['expires_in'] as num?)?.toInt() ?? (7 * 24 * 60 * 60);
await ApiClient.instance.saveBackendToken(backendToken, expiresInSeconds: expiresIn);
```

Also added `expires_in` to `AuthResponse` in `schemas.py`.

---

### 3. All new users become "buyer" – no way to become a farmer
**Files:** `farmaa_backend/schemas.py`, `routers/auth_router.py`,
`farmaa_mobile/lib/features/auth/screens/profile_completion_screen.dart`,
`farmaa_mobile/lib/core/providers/auth_provider.dart`,
`farmaa_mobile/lib/core/services/auth_service.dart`

`ProfileCompleteRequest` had no `role` field. New users defaulted to `"buyer"`
with no mechanism to register as `"farmer"`.

**Fix:** added role selector UI (farmer/buyer cards) to the profile completion
screen, a `role` field to `ProfileCompleteRequest` (validated to
`{"farmer","buyer"}`), and role propagation through the notifier → service →
API call chain.

---

### 4. Hardcoded production database credentials in source code
**File:** `farmaa_backend/init_db.py`

```python
# ❌ BEFORE – real Supabase URL + password committed to git
url = "postgresql://postgres.wwtlqasnplvejymsbmvm:jIaHHCoN38pZ2ayQ@..."

# ✅ AFTER – reads from environment
url = os.getenv("DATABASE_URL")
if not url:
    sys.exit(1)
```

---

### 5. Orders allowed without a completed profile
**File:** `farmaa_backend/routers/orders_router.py`

A user could place an order immediately after Google sign-in, before
completing their profile (no mobile number, no address). The delivery address
would be null.

**Fix:** added a `profile_completed` guard at the top of `create_order`, plus
automatic fall-back to `buyer.address` when `delivery_address` is omitted.

```python
if not buyer.profile_completed:
    raise HTTPException(400, "Please complete your profile before placing orders.")
```

---

### 6. `get_current_user_id` silently swallowed HTTPException
**File:** `farmaa_backend/auth.py`

```python
# ❌ BEFORE – catches HTTPException, then raises a generic 401 with a
#             different message, losing the original error detail
try:
    payload = verify_token(token)
    user_id = payload.get("sub")
    if user_id:
        return user_id
except HTTPException:
    pass
raise HTTPException(status_code=401, detail="Invalid or expired token")

# ✅ AFTER – verify_token already raises 401; just propagate it
payload = verify_token(token)
user_id = payload.get("sub")
if not user_id:
    raise HTTPException(status_code=401, detail="Invalid token: missing subject")
return user_id
```

---

## 🟠 Medium Bugs (wrong behaviour, not a crash)

### 7. Profile screen showed hardcoded "User account" as role
**File:** `farmaa_mobile/lib/features/shared/screens/profile_screen.dart`

```dart
// ❌ BEFORE
_tile(Icons.badge_outlined, l.role, 'User account'),

// ✅ AFTER – shows actual role with emoji
_tile(Icons.badge_outlined, l.role,
    user.isFarmer ? '🌾 Farmer' : '🛒 Buyer'),
```

---

### 8. `User.crops` lazy="joined" caused N+1 / over-fetching
**File:** `farmaa_backend/models.py`

`lazy="joined"` on `User.crops` means every `SELECT` on `users` also joins
`crops`, loading all crop rows for every user — catastrophic for admin
queries or bulk user listing.

```python
# ❌ BEFORE
crops = relationship("Crop", back_populates="farmer", lazy="joined")

# ✅ AFTER
crops = relationship("Crop", back_populates="farmer", lazy="select")
```

---

### 9. `create_order` stock could go slightly negative
**File:** `farmaa_backend/routers/orders_router.py`

Under the `FOR UPDATE` lock there was no floor clamp:
```python
# ✅ AFTER
crop.stock_kg -= body.quantity_kg
if crop.stock_kg <= 0:
    crop.stock_kg = 0        # ← added clamp
    crop.is_available = False
    crop.status = "sold_out"
```

---

## 🟡 Improvements

### 10. `AuthResponse` now includes `expires_in` and `token_type`
**File:** `farmaa_backend/schemas.py`

Flutter (and any future web client) can use `expires_in` to set token
storage expiry precisely instead of guessing.

### 11. `UserUpdate` supports role switching
Users can now switch between farmer and buyer from their profile edit dialog
without having to delete their account.

### 12. `CropUpdate` supports `is_available` toggling
Farmers can now pause/unpause listings without changing stock or price.

---

## Files Changed

### Backend
| File | Change |
|------|--------|
| `init_db.py` | Remove hardcoded credentials, read from env |
| `auth.py` | Export `ACCESS_TOKEN_EXPIRY_MINUTES`; fix `get_current_user_id` |
| `schemas.py` | Add `role` to `ProfileCompleteRequest`; add `expires_in`/`token_type` to `AuthResponse`; add `role` + `is_available` to `UserUpdate` |
| `routers/auth_router.py` | Handle `role` in `complete_profile` & `update_profile`; fix empty email edge case |
| `routers/orders_router.py` | `profile_completed` guard; delivery address fallback; stock floor clamp |
| `models.py` | Fix `User.crops` lazy loading |

### Flutter
| File | Change |
|------|--------|
| `market_prices_screen.dart` | Fix `final` → mutable `_selectedDistrict` |
| `auth_service.dart` | Fix token expiry; pass `role` in `completeProfile` / `updateProfile` |
| `auth_provider.dart` | Add `role` param to `completeProfile` and `updateProfile` |
| `profile_completion_screen.dart` | Add farmer/buyer role selector cards |
| `profile_screen.dart` | Show actual role; add role switcher in edit dialog |
