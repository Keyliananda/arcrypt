#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE_A="${DEVICE_A:-PM19765BA13A2302806}"  # ZTE
DEVICE_B="${DEVICE_B:-S5ME1218P002406}"      # SHIFT

# DEV default relay: host machine relay via adb reverse.
RELAY_BASE_URL="${PRSM_DEV_RELAY_BASE_URL:-http://127.0.0.1:3000}"

# Deterministic mailbox pair for DEV. Devices get swapped directions.
MAILBOX_A="${PRSM_DEV_MAILBOX_A:-bWFpbGJveC1pZC0xMjM0NTY3ODkw}"
MAILBOX_B="${PRSM_DEV_MAILBOX_B:-bWFpbGJveC1pZC0wOTg3NjU0MzIx}"

install_device() {
  local device="$1"
  local inbound="$2"
  local outbound="$3"

  echo "==> [$device] adb reverse tcp:3000 -> tcp:3000"
  adb -s "$device" reverse tcp:3000 tcp:3000

  echo "==> [$device] flutter run --no-resident with DEV relay defaults"
  flutter run -d "$device" --no-resident \
    --dart-define=PRSM_DEV_RELAY_BASE_URL="$RELAY_BASE_URL" \
    --dart-define=PRSM_DEV_RELAY_INBOUND_MAILBOX_ID="$inbound" \
    --dart-define=PRSM_DEV_RELAY_OUTBOUND_MAILBOX_ID="$outbound"
}

echo "Using DEV relay base URL: $RELAY_BASE_URL"
echo "Mailbox pair: A=$MAILBOX_A / B=$MAILBOX_B"

install_device "$DEVICE_A" "$MAILBOX_A" "$MAILBOX_B"
install_device "$DEVICE_B" "$MAILBOX_B" "$MAILBOX_A"

echo "Done. Both devices installed with DEV relay defaults."
