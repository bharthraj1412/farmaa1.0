# PR Checklist – Farmaa Production Hardening

## PR Title
`fix: production hardening – auth, orders, profile, marketplace visibility`

## Summary
Fixes 6 critical bugs: crop marketplace crash, profile update data loss, inventory race condition, auth session leak, wrong token storage, and missing DB constraints.

## Files Changed

### SQL Migrations
- `migrations/20260317_001_schema_hardening.sql` – `is_active` column, CHECK constraints, indexes, triggers
- `migrations/20260317_002_rls_policies.sql` – RLS policies for all tables

### Backend (Python)
- `auth.py` – JWT-first verification (eliminates session leak)
- `models.py` – Added `is_active` column to Crop model
- `schemas.py` – Added description to `org` field in UserUpdate
- `routers/auth_router.py` – Fixed profile PATCH + added `/auth/exchange_token`
- `routers/orders_router.py` – Atomic inventory decrement with `FOR UPDATE`

### Frontend (Dart)
- `lib/core/services/crop_service.dart` – Fixed response parsing (Map vs List)
- `lib/core/services/auth_service.dart` – Store backend JWT, use `/auth/exchange_token`

### Tests
- `tests/test_orders.py` – Order creation, stock decrement, race condition, self-purchase
- `tests/test_profile.py` – Profile update persistence validation

### Docs
- `DEPLOYMENT.md` – Step-by-step deployment + rollback plan
- `verify.sh` – Curl smoke tests

## Pre-Merge Checklist
- [ ] `python -m pytest tests/ -v` passes
- [ ] Schema migration tested on staging DB
- [ ] RLS policies tested via Supabase Dashboard
- [ ] Mobile app tested on physical device
- [ ] No hardcoded secrets in diff

## Commit Messages
```
fix(schema): add is_active, CHECK constraints, indexes, stock trigger
fix(rls): add row-level security policies for all tables
fix(auth): JWT-first verification, add /auth/exchange_token endpoint
fix(profile): persist village, district, org in PATCH /auth/me
fix(orders): atomic inventory decrement with SELECT FOR UPDATE
fix(models): add is_active column to Crop model
fix(frontend): parse crop marketplace response correctly
fix(frontend): store backend JWT instead of Firebase token
test: add order creation, profile update, and marketplace tests
docs: add DEPLOYMENT.md, PR_CHECKLIST.md, verify.sh
```

## Rollback Steps
1. `git revert HEAD` to undo backend changes
2. Run rollback SQL from DEPLOYMENT.md to revert schema
3. Mobile app falls back gracefully (old `/auth/firebase` still works)
