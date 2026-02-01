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
