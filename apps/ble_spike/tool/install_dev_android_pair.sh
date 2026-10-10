#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT_DIR="$(pwd)"

load_env_file() {
  local env_file="$1"
  if [[ ! -f "$env_file" ]]; then
    return
  fi
  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a
}

# Load repo env files when variables are not already present in the shell.
if [[ -z "${PRSM_DEV_RELAY_BASE_URL:-}" && -z "${PRSM_RELAY_BASE_URL:-}" ]]; then
  load_env_file "$ROOT_DIR/.env"
  load_env_file "$ROOT_DIR/server/.env"
fi

DEVICE_A="${DEVICE_A:-PM19765BA13A2302806}"  # ZTE
DEVICE_B="${DEVICE_B:-S5ME1218P002406}"      # SHIFT

# Server relay URL: shell env -> loaded .env -> localhost default.
DEFAULT_RELAY_BASE_URL="${DEFAULT_RELAY_BASE_URL:-http://127.0.0.1:3000}"
RELAY_BASE_URL="${PRSM_DEV_RELAY_BASE_URL:-${PRSM_RELAY_BASE_URL:-$DEFAULT_RELAY_BASE_URL}}"
USE_ADB_REVERSE="${USE_ADB_REVERSE:-0}"
RELAY_REVERSE_PORT="${RELAY_REVERSE_PORT:-3000}"

# Deterministic mailbox pair for DEV. Devices get swapped directions.
MAILBOX_A="${PRSM_DEV_MAILBOX_A:-bWFpbGJveC1pZC0xMjM0NTY3ODkw}"
MAILBOX_B="${PRSM_DEV_MAILBOX_B:-bWFpbGJveC1pZC0wOTg3NjU0MzIx}"

if [[ -z "$RELAY_BASE_URL" ]]; then
  echo "ERROR: Set PRSM_DEV_RELAY_BASE_URL (or PRSM_RELAY_BASE_URL) or DEFAULT_RELAY_BASE_URL." >&2
  exit 1
fi

if [[ ! "$RELAY_BASE_URL" =~ ^https?://[^[:space:]]+$ ]]; then
  echo "ERROR: RELAY_BASE_URL must be a valid http(s) URL." >&2
  exit 1
fi

if [[ "$USE_ADB_REVERSE" == "1" ]]; then
  if [[ ! "$RELAY_BASE_URL" =~ ^https?://(127\.0\.0\.1|localhost)(:([0-9]+))?(/|$) ]]; then
    echo "ERROR: USE_ADB_REVERSE=1 is only allowed with localhost/127.0.0.1 relay URLs." >&2
    exit 1
  fi
  if [[ "$RELAY_BASE_URL" =~ :([0-9]+) ]]; then
    RELAY_REVERSE_PORT="${BASH_REMATCH[1]}"
  fi
fi

install_device() {
  local device="$1"
  local inbound="$2"
  local outbound="$3"

  if [[ "$USE_ADB_REVERSE" == "1" ]]; then
    echo "==> [$device] adb reverse tcp:$RELAY_REVERSE_PORT -> tcp:$RELAY_REVERSE_PORT"
    adb -s "$device" reverse "tcp:$RELAY_REVERSE_PORT" "tcp:$RELAY_REVERSE_PORT"
  else
    # Remove stale local reverse so the app really targets remote server URLs.
    adb -s "$device" reverse --remove "tcp:3000" >/dev/null 2>&1 || true
    adb -s "$device" reverse --remove "tcp:$RELAY_REVERSE_PORT" >/dev/null 2>&1 || true
  fi

  echo "==> [$device] flutter run --no-resident with DEV relay defaults"
  flutter run -d "$device" --no-resident \
    --dart-define=PRSM_DEV_RELAY_BASE_URL="$RELAY_BASE_URL" \
    --dart-define=PRSM_DEV_RELAY_INBOUND_MAILBOX_ID="$inbound" \
    --dart-define=PRSM_DEV_RELAY_OUTBOUND_MAILBOX_ID="$outbound"
}

echo "Using DEV relay base URL: $RELAY_BASE_URL"
echo "adb reverse enabled: $USE_ADB_REVERSE (port=$RELAY_REVERSE_PORT)"
echo "Mailbox pair: A=$MAILBOX_A / B=$MAILBOX_B"

install_device "$DEVICE_A" "$MAILBOX_A" "$MAILBOX_B"
install_device "$DEVICE_B" "$MAILBOX_B" "$MAILBOX_A"

echo "Done. Both devices installed with DEV relay defaults."
