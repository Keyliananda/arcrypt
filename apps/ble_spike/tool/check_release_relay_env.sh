#!/usr/bin/env bash
set -euo pipefail

relay_url="${PRSM_RELAY_BASE_URL:-}"

if [[ -z "$relay_url" ]]; then
  echo "ERROR: PRSM_RELAY_BASE_URL is required for Release builds." >&2
  exit 1
fi

if [[ ! "$relay_url" =~ ^https?://[^[:space:]]+$ ]]; then
  echo "ERROR: PRSM_RELAY_BASE_URL must be a valid http(s) URL." >&2
  exit 1
fi

echo "OK: PRSM_RELAY_BASE_URL is set."
