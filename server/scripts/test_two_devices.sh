#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing .env at $ENV_FILE" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

TOKEN1="${1:-}"
TOKEN2="${2:-}"
ENVIRONMENT="${3:-${APNS_ENV:-sandbox}}"
TOPIC="${APNS_TOPIC:-com.arcrypt.bleSpike}"
BASE_URL="${BASE_URL:-http://localhost:3000}"

if [[ -z "$TOKEN1" ]] || [[ -z "$TOKEN2" ]]; then
  echo "Usage: $0 <device_token_1> <device_token_2> [env]" >&2
  echo "" >&2
  echo "This script will:" >&2
  echo "  1. Register both tokens" >&2
  echo "  2. Wake device 1" >&2
  echo "  3. Wake device 2" >&2
  echo "  4. Send wake from device 1 to device 2" >&2
  exit 1
fi

if [[ -z "${HMAC_SECRET:-}" ]]; then
  echo "HMAC_SECRET is empty in .env" >&2
  exit 1
fi

echo "=========================================="
echo "Testing APNs with two devices"
echo "=========================================="
echo ""

# Helper function to compute HMAC
compute_hmac() {
  local token="$1"
  local ts="$2"
  HMAC_SECRET="$HMAC_SECRET" node -e "const crypto=require('crypto'); const secret=process.env.HMAC_SECRET; const token=process.argv[1]; const ts=process.argv[2]; process.stdout.write(crypto.createHmac('sha256', secret).update(\`\${token}:\${ts}\`).digest('hex'))" "$token" "$ts"
}

# Step 1: Register both tokens
echo "Step 1: Registering Device 1..."
REGISTER1_PAYLOAD="$(printf '{"token":"%s","topic":"%s","env":"%s"}' "$TOKEN1" "$TOPIC" "$ENVIRONMENT")"
RESPONSE1=$(curl -sS -X POST "$BASE_URL/v1/register" -H "content-type: application/json" -d "$REGISTER1_PAYLOAD")
echo "Response: $RESPONSE1"
echo ""

echo "Step 2: Registering Device 2..."
REGISTER2_PAYLOAD="$(printf '{"token":"%s","topic":"%s","env":"%s"}' "$TOKEN2" "$TOPIC" "$ENVIRONMENT")"
RESPONSE2=$(curl -sS -X POST "$BASE_URL/v1/register" -H "content-type: application/json" -d "$REGISTER2_PAYLOAD")
echo "Response: $RESPONSE2"
echo ""

# Step 2: Wake Device 1
echo "Step 3: Waking Device 1..."
TS1="$(date +%s)"
PROOF1="$(compute_hmac "$TOKEN1" "$TS1")"
WAKE1_PAYLOAD="$(printf '{"token":"%s","ts":%s,"proof":"%s"}' "$TOKEN1" "$TS1" "$PROOF1")"
WAKE1_RESPONSE=$(curl -sS -X POST "$BASE_URL/v1/wake" -H "content-type: application/json" -d "$WAKE1_PAYLOAD")
echo "Response: $WAKE1_RESPONSE"
echo ""

sleep 1

# Step 3: Wake Device 2
echo "Step 4: Waking Device 2..."
TS2="$(date +%s)"
PROOF2="$(compute_hmac "$TOKEN2" "$TS2")"
WAKE2_PAYLOAD="$(printf '{"token":"%s","ts":%s,"proof":"%s"}' "$TOKEN2" "$TS2" "$PROOF2")"
WAKE2_RESPONSE=$(curl -sS -X POST "$BASE_URL/v1/wake" -H "content-type: application/json" -d "$WAKE2_PAYLOAD")
echo "Response: $WAKE2_RESPONSE"
echo ""

sleep 1

# Step 4: Send "message" from Device 1 to Device 2 (via wake)
echo "Step 5: Sending 'message' from Device 1 to Device 2..."
TS3="$(date +%s)"
PROOF3="$(compute_hmac "$TOKEN2" "$TS3")"
MESSAGE_PAYLOAD="$(printf '{"token":"%s","ts":%s,"proof":"%s"}' "$TOKEN2" "$TS3" "$PROOF3")"
MESSAGE_RESPONSE=$(curl -sS -X POST "$BASE_URL/v1/wake" -H "content-type: application/json" -d "$MESSAGE_PAYLOAD")
echo "Response: $MESSAGE_RESPONSE"
echo ""

echo "=========================================="
echo "Test Complete!"
echo "=========================================="
echo ""
echo "Check the APNs responses above:"
echo "  - 'status': 'sent' with http_status: 200 = SUCCESS"
echo "  - 'status': 'failed' with reason = ERROR (check reason)"
echo ""
