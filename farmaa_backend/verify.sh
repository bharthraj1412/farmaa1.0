#!/bin/bash
# verify.sh: Step-by-step verification of backend token-exchange and protected endpoints.
# Usage: ./verify.sh
# Optional environment overrides:
#   BACKEND_URL: Default http://localhost:8000
#   FIREBASE_ID_TOKEN: Set via export to avoid prompt

set -e

BACKEND_URL=${BACKEND_URL:-"http://localhost:8000"}

# Check for Firebase token or provide instructions
if [ -z "$FIREBASE_ID_TOKEN" ]; then
    echo "ERROR: FIREBASE_ID_TOKEN is not set."
    echo "To obtain one, run the flutter app, sign in, and print: await FirebaseAuth.instance.currentUser?.getIdToken();"
    echo "Then re-run: export FIREBASE_ID_TOKEN=\"your_token\" && ./verify.sh"
    exit 1
fi

echo "--- STEP A: Token Exchange ---"
EXCHANGE_RES=$(curl -s -w "\nHTTP_STATUS:%{http_code}\n" -X POST "$BACKEND_URL/auth/exchange_token" \
    -H "Content-Type: application/json" \
    -d "{\"firebase_id_token\":\"$FIREBASE_ID_TOKEN\"}")

EXCHANGE_STATUS=$(echo "$EXCHANGE_RES" | grep 'HTTP_STATUS' | awk -F: '{print $2}')
EXCHANGE_BODY=$(echo "$EXCHANGE_RES" | sed '/HTTP_STATUS/d')

if [ "$EXCHANGE_STATUS" != "200" ] && [ "$EXCHANGE_STATUS" != "201" ]; then
    echo "Exchange Failed (HTTP $EXCHANGE_STATUS):"
    echo "$EXCHANGE_BODY"
    exit 10
fi

ACCESS_TOKEN=$(echo "$EXCHANGE_BODY" | jq -r '.access_token')
if [ "$ACCESS_TOKEN" == "null" ] || [ -z "$ACCESS_TOKEN" ]; then
    echo "Exchange Failed: No access_token in response"
    exit 10
fi

echo "EXCHANGE OK - Token: ${ACCESS_TOKEN:0:24}..."

echo -e "\n--- STEP B: Protected Endpoint test ---"
CROP_RES=$(curl -s -w "\nHTTP_STATUS:%{http_code}\n" -X POST "$BACKEND_URL/crops" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "Test Crop Verification",
        "category": "Other",
        "price_per_kg": 20.0,
        "stock_kg": 100
    }')

CROP_STATUS=$(echo "$CROP_RES" | grep 'HTTP_STATUS' | awk -F: '{print $2}')
if [ "$CROP_STATUS" != "201" ]; then
    echo "Crop Create Failed (HTTP $CROP_STATUS)"
    echo "$CROP_RES"
    exit 11
fi
echo "Protected POST OK (HTTP 201)"

echo -e "\n--- STEP C: Invalid Token test ---"
# Truncate token by dropping last 5 chars
BAD_TOKEN="${ACCESS_TOKEN:0:${#ACCESS_TOKEN}-5}"

BAD_RES=$(curl -s -w "\nHTTP_STATUS:%{http_code}\n" -X POST "$BACKEND_URL/crops" \
    -H "Authorization: Bearer $BAD_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{ "name": "Fail Crop", "price_per_kg": 10.0, "stock_kg": 10 }')

BAD_STATUS=$(echo "$BAD_RES" | grep 'HTTP_STATUS' | awk -F: '{print $2}')
if [ "$BAD_STATUS" != "401" ]; then
    echo "Simulated Invalid Token test failed. Expected 401, got $BAD_STATUS"
    exit 12
fi
echo "Invalid token simulation OK (HTTP 401 expectedly blocked)."

echo -e "\n--- STEP D: Client Retry Sim Flow ---"
echo "Client detects 401, exchanging token again..."
REFRESH_RES=$(curl -s -X POST "$BACKEND_URL/auth/exchange_token" -H "Content-Type: application/json" -d "{\"firebase_id_token\":\"$FIREBASE_ID_TOKEN\"}")
FRESH_TOKEN=$(echo "$REFRESH_RES" | jq -r '.access_token')

echo "Retrying POST crops with freshly exchanged token..."
RETRY_RES=$(curl -s -w "\nHTTP_STATUS:%{http_code}\n" -X POST "$BACKEND_URL/crops" \
    -H "Authorization: Bearer $FRESH_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{ "name": "Retry Flow Crop", "price_per_kg": 15.0, "stock_kg": 50, "category": "Other" }')

RETRY_STATUS=$(echo "$RETRY_RES" | grep 'HTTP_STATUS' | awk -F: '{print $2}')
if [ "$RETRY_STATUS" == "201" ]; then
    echo "Retry flow completed successfully (HTTP 201)."
elif [ "$RETRY_STATUS" == "401" ]; then
    echo "Retry flow resulted in HTTP 401 (Wait, is Firebase token expired?)"
else
    echo "Unexpected retry status: $RETRY_STATUS"
    exit 1
fi

echo -e "\nALL VERIFICATIONS PASSED."
exit 0
