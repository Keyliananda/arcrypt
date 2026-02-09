# Nebenroadmap 3 – Client Remote Transport v1 (Queue, Poll/Push, Link-Switch) – Feb 2026

Ziel: Client kann Nachrichten sowohl ueber BLE (nahe) als auch ueber Internet (remote) zustellen, ohne die Krypto- und Storage-Garantien zu verletzen.

## Taskliste (in Reihenfolge)
- [x] CLI-001: Link-Abstraktion finalisieren: `TransportLink` erweitern/sauber halten, so dass BLE und Relay identisch nutzbar sind. (done 2026-02-09; updated `apps/ble_spike/lib/transport/transport.dart`, `apps/ble_spike/lib/ble/gatt_client.dart`, `apps/ble_spike/lib/ble/gatt_server.dart`, `apps/ble_spike/lib/ble_chat_bridge.dart`, `apps/ble_spike/tool/transport_harness.dart`)
- [x] CLI-002: RelayLink entwerfen (HTTP zuerst, optional WebSocket spaeter): push/pull/ack Calls, Retry/Backoff, timeouts. (done 2026-02-09; added `apps/ble_spike/lib/transport/relay_link.dart`; covered by `apps/ble_spike/test/relay_link_test.dart`)
- [x] CLI-003: Persistente Outbox implementieren (send pending ueber Restarts), inkl. idempotentem Resend (keine Double-Sends). (done 2026-02-09; added `apps/ble_spike/lib/transport/relay_outbox.dart`, updated `apps/ble_spike/lib/transport/relay_link.dart`, added `apps/ble_spike/test/relay_outbox_test.dart`)
- [x] CLI-004: Persistente Inbox + Dedupe implementieren (message_id), out-of-order tolerant. (done 2026-02-09; added `apps/ble_spike/lib/transport/relay_inbox.dart`, updated `apps/ble_spike/lib/transport/relay_link.dart`, added `apps/ble_spike/test/relay_inbox_test.dart` and updated `apps/ble_spike/test/relay_link_test.dart`)
- [ ] CLI-005: Polling-Loop implementieren (Intervall + jitter), “pull-delete” oder ack-flows passend zu SRV-API.
- [ ] CLI-006: Wake Integration: bei Push ein Wake triggern (wenn Token vorhanden), und nach Wake sofort pollen.
- [ ] CLI-007: UX Mindestset: “Remote verfuegbar”, “trusted/untrusted”, Fehlerbilder, und “keine stillen Downgrades”.
- [ ] CLI-008: Testpaket: Integrationstests gegen lokalen Server (happy path, offline peer, retries, dedupe).

## Schritte
1. Transport Abstraktion stabilisieren
- Bestehendes `TransportLink` Konzept beibehalten (BLE ist ein Link).
- Neuen Link einfuehren: `RelayLink` (HTTP/WS), gleicher “bytes in/out” Vertrag.

2. Outbox/Inbox Queue
- Outbox persistent: “send pending” ueber App-Restarts.
- Inbox persistent: dedupe nach message_id; out-of-order tolerant (wichtig fuer remote).
- Delivery States: pending/sent/failed plus retry/backoff.

3. Polling + Push Wake
- Default: Poll in Intervallen (konfigurierbar), jitter zur Metadaten-Reduktion.
- Push (APNs/FCM) nur als Wake: nach Wake sofort poll.
- Hintergrundlimits iOS beachten: Polling konservativ, Wake-Handling minimal.

4. Key/Session Interaktion
- Pairing/Trust aus `docs/roadmap-security-v2.md` nutzen.
- Mailbox-IDs rotieren aus Shared Secret (kein serverseitiger Identifier).
- Sicherstellen: kein Nonce-Reuse trotz Retry/Resend.

5. UX/Fehlerbilder
- “Remote erreichbar” vs “nur in Naehe” klar anzeigen.
- “Sicherheitsstatus” sichtbar: trusted/untrusted, SAS bestaetigt ja/nein.
- Recovery: wenn State desync, controlled re-handshake, keine stillen Downgrades.

## DoD
- Nachricht kann remote zugestellt werden, auch wenn Apps neu starten.
- BLE und Relay koennen koexistieren (z. B. wenn beide online in Naehe).
- Kein Datenverlust bei Retries, kein Duplicate Spam beim Empfaenger (dedupe).

## Offene Entscheidungen
- “Always Relay” vs “Prefer BLE when nearby”.
- Synchronisationsfenster fuer Polling (Battery vs Privacy).
- Attachments: out of scope fuer v1.
