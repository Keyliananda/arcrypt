# AGENTS.md

## Scope
Diese Regeln gelten fuer das gesamte Repository `Arcrypt`.

## Pflichtregeln fuer Android DEV-Install (ble_spike)

1. Fuer Installationen auf beide Android-Testgeraete ist ausschliesslich dieser Befehl zu verwenden:
   - `apps/ble_spike/tool/install_dev_android_pair.sh`
2. Direkte Einzel-Installationen mit `flutter run -d ...` sind nur erlaubt, wenn der User explizit nur ein einzelnes Geraet verlangt.
3. Der Agent darf eine Installation niemals als "erfolgreich" melden, bevor beide Pflicht-Verifikationen abgeschlossen sind.

## Pflicht-Verifikation nach jeder Dual-Installation

1. Versionspruefung auf beiden Geraeten:
   - `adb -s PM19765BA13A2302806 shell dumpsys package com.arcrypt.ble_spike | rg "versionName|versionCode"`
   - `adb -s S5ME1218P002406 shell dumpsys package com.arcrypt.ble_spike | rg "versionName|versionCode"`
2. Relay-Default-Pruefung auf beiden Geraeten (UI/Runtime sichtbar):
   - App starten
   - `Relay konfigurieren` oeffnen
   - Nachweis, dass Base URL + Inbound/Outbound gesetzt sind (nicht leer)
3. Ergebnisbericht muss fuer **jedes** Geraet getrennt enthalten:
   - Geraet
   - versionName/versionCode
   - Relay Base URL
   - Inbound Mailbox
   - Outbound Mailbox

## Berichtspflicht

1. Verboten ist eine pauschale Aussage wie "beide aktualisiert", wenn nur Build/Install-Logs vorliegen.
2. Zulaessig ist nur eine Aussage nach verifizierten Device-Checks.
3. Wenn ein Check nicht moeglich war, muss das explizit als Blocker genannt werden.

## Sicherheitsregeln (Release)

1. `PRSM_DEV_RELAY_*` ist nur fuer Debug/Profile.
2. Release darf niemals auf DEV-Defines basieren.
3. Release-Guards fuer Relay-Konfig duerfen nicht umgangen werden.

## Wenn Unsicherheit besteht

1. Nicht raten.
2. Sofort nachmessen (ADB/UI/Logs).
3. Erst danach Ergebnis melden.
