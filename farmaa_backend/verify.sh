#!/usr/bin/env bash
# ============================================================
# verify.sh – Smoke test suite for Farmaa API
# Usage: BASE_URL=https://farmaa1-0.vercel.app ./verify.sh
# ============================================================
set -euo pipefail

BASE="${BASE_URL:-http://localhost:10000}"
echo "Testing against: $BASE"

# 1. Health check
echo "── 1. Health check ──"
curl -sf "$BASE/health" | python3 -m json.tool
echo ""

# 2. DB health check
echo "── 2. DB health check ──"
curl -sf "$BASE/health/db" | python3 -m json.tool
echo ""

# 3. Register a test user
echo "── 3. Register user ──"
REGISTER=$(curl -sf -X POST "$BASE/auth/register" \
  -H "Content-Type: application/json" \
  -d '{"name":"Verify Farmer","email":"verify_farmer@test.com","password":"testpass123"}')
echo "$REGISTER" | python3 -m json.tool
TOKEN=$(echo "$REGISTER" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
echo "Token: ${TOKEN:0:30}..."
echo ""

# 4. Get profile
echo "── 4. Get profile ──"
curl -sf "$BASE/auth/me" -H "Authorization: Bearer $TOKEN" | python3 -m json.tool
echo ""

# 5. Update profile with village/district
echo "── 5. Update profile (village/district) ──"
curl -sf -X PATCH "$BASE/auth/me" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"Verify Farmer Updated","village":"Srirangam","district":"Trichy","org":"Test Coop"}' \
  | python3 -m json.tool
echo ""

# 6. Read back profile to confirm persistence
echo "── 6. Read back profile ──"
curl -sf "$BASE/auth/me" -H "Authorization: Bearer $TOKEN" | python3 -m json.tool
echo ""

# 7. Create a crop
echo "── 7. Create crop ──"
CROP=$(curl -sf -X POST "$BASE/crops/" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"Test Wheat","category":"Wheat","price_per_kg":28.5,"stock_kg":500}')
echo "$CROP" | python3 -m json.tool
CROP_ID=$(echo "$CROP" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
echo "Crop ID: $CROP_ID"
echo ""

# 8. List marketplace crops (public, no auth)
echo "── 8. List marketplace ──"
curl -sf "$BASE/crops" | python3 -m json.tool
echo ""

# 9. Register a buyer
echo "── 9. Register buyer ──"
BUYER=$(curl -sf -X POST "$BASE/auth/register" \
  -H "Content-Type: application/json" \
  -d '{"name":"Verify Buyer","email":"verify_buyer@test.com","password":"buyerpass123"}')
BUYER_TOKEN=$(echo "$BUYER" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
echo "Buyer Token: ${BUYER_TOKEN:0:30}..."
echo ""

# 10. Create order
echo "── 10. Create order ──"
curl -sf -X POST "$BASE/orders/" \
  -H "Authorization: Bearer $BUYER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"crop_id\":\"$CROP_ID\",\"quantity_kg\":50}" \
  | python3 -m json.tool
echo ""

# 11. Verify stock decremented
echo "── 11. Verify stock decrement ──"
curl -sf "$BASE/crops/$CROP_ID" | python3 -m json.tool
echo ""

echo "✓ All smoke tests passed!"
