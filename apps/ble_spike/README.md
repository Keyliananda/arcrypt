# ble_spike

BLE spike app to validate BLE roles and platform limits for the MVP.

## What it does
- Central role: scan, connect, disconnect.
- Peripheral role: advertising only (no GATT server).

## Run
1) `flutter run` on real devices (Android + iOS preferred).
2) Android: tap "Berechtigungen anfordern" and allow all BLE permissions.
3) Android: tap "Advertise starten" (default Service UUID).
4) iOS: tap "Scan starten" and try Connect/Disconnect.
5) Log results in `docs/ble-spike-results.md`.

## Notes
- `flutter_ble_peripheral` only advertises; Service/Char/Write/Notify are N/A.
- For GATT testing, a native peripheral or another plugin is required.

## Relay status in the Advertise screen
- The `Relay: ...` pill is based on compile-time `--dart-define` values.
- If `PRSM_RELAY_BASE_URL` (and mailbox IDs) are missing at build/run time,
  the app shows `Remote nicht konfiguriert ...` even when BLE itself works.
- BLE connectivity and Relay configuration are independent signals.

## Stable Relay configuration (recommended)
- You can configure Relay at runtime via `Relay konfigurieren` on the start screen.
- Runtime config is stored securely on-device and has priority over build defines.
- Priority order: `stored runtime config` -> `--dart-define` fallback.
- This prevents accidental "Relay off" installs when a run happens without defines.

Example:

```bash
flutter run \
  --dart-define=PRSM_RELAY_BASE_URL=https://relay.example \
  --dart-define=PRSM_RELAY_INBOUND_MAILBOX_ID=your-inbound-id \
  --dart-define=PRSM_RELAY_OUTBOUND_MAILBOX_ID=your-outbound-id \
  --dart-define=PRSM_RELAY_WAKE_HMAC_SECRET=optional-wake-secret \
  --dart-define=PRSM_RELAY_PEER_WAKE_TOKEN=optional-peer-token
```
