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

TOKEN="${1:-}"
ENVIRONMENT="${2:-${APNS_ENV:-sandbox}}"
TOPIC="${3:-${APNS_TOPIC:-}}"
BASE_URL="${BASE_URL:-http://localhost:3000}"

if [[ -z "$TOKEN" ]]; then
  echo "Usage: $0 <device_token> [env] [topic]" >&2
  exit 1
fi

if [[ -z "$TOPIC" ]]; then
  echo "APNS_TOPIC is empty; set it in .env or pass as arg" >&2
  exit 1
fi

if [[ -z "${HMAC_SECRET:-}" ]]; then
  echo "HMAC_SECRET is empty in .env" >&2
  exit 1
fi

TS="$(date +%s)"
PROOF="$(node -e "const crypto=require('crypto'); const secret=process.env.HMAC_SECRET; const token=process.argv[1]; const ts=process.argv[2]; process.stdout.write(crypto.createHmac('sha256', secret).update(`${token}:${ts}`).digest('hex'))" "$TOKEN" "$TS")"

REGISTER_PAYLOAD="$(printf '{"token":"%s","topic":"%s","env":"%s"}' "$TOKEN" "$TOPIC" "$ENVIRONMENT")"
WAKE_PAYLOAD="$(printf '{"token":"%s","ts":%s,"proof":"%s"}' "$TOKEN" "$TS" "$PROOF")"

echo "Register -> $BASE_URL/v1/register"
curl -sS -X POST "$BASE_URL/v1/register" -H "content-type: application/json" -d "$REGISTER_PAYLOAD"
echo
echo "Wake -> $BASE_URL/v1/wake"
curl -sS -X POST "$BASE_URL/v1/wake" -H "content-type: application/json" -d "$WAKE_PAYLOAD"
echo
