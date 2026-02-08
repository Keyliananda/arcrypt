# Nebenroadmap 1 – Security v2 (Handshake, Ratchet, Key-Storage) – Feb 2026

Ziel: “Abhoersicher” im Sinne von starker E2EE (Vertraulichkeit + Integritaet), MITM-resistent beim Erstkontakt (durch SAS/QR), Forward Secrecy, und keine Nonce/Key-Wiederverwendung bei App-Restarts.

Scope:
- Basierend auf `docs/security-spec-v1.md` (Noise + SAS) und `docs/chat-spec-v1.md` (Frames).
- Erweitert fuer Remote und Langzeitbetrieb.

## Taskliste (in Reihenfolge)
- [x] SEC-001: Threat Model finalisieren (1 Seite) und explizite Security-Claims definieren (was wir versprechen / was nicht). (done 2026-02-06; added `docs/threat-model-prsm-remote-v1.md`)
- [x] SEC-002: Krypto-Entscheidung festziehen: minimaler MasterKey-Refresh vs Double Ratchet (Empfehlung: Ratchet). (done 2026-02-06; decision: Double Ratchet fuer Remote; BLE-Spike bleibt bei master_key + counter bis Ratchet-Implementierung)
- [x] SEC-003: Pairing implementieren: Noise XX + SAS/QR bestaetigen; danach Peer-Static-Key pinnen. (done 2026-02-06; implemented in Flutter BLE spike: `apps/ble_spike/lib/security/noise_xx.dart`, `apps/ble_spike/lib/security/pairing_session.dart`, `apps/ble_spike/lib/chat/chat_storage.dart`, `apps/ble_spike/lib/main.dart`)
- [x] SEC-004: Reconnect implementieren: Noise IK (oder XX mit Pinning) fuer bekannte Peers, inkl. “no silent downgrade”. (done 2026-02-06; implemented Noise XX + pinning + auto-SAS confirm for trusted peers in Flutter BLE spike: `apps/ble_spike/lib/security/pairing_session.dart`, `apps/ble_spike/lib/security/pairing_storage.dart`, `apps/ble_spike/lib/chat/chat_storage.dart`, `apps/ble_spike/lib/main.dart`, `apps/ble_spike/test/pairing_session_reconnect_test.dart`)
- [x] SEC-005: Key-Rotation “Treffen-Trigger” + Two-Phase Commit implementieren (ACK vor Delete), wie in `docs/security-spec-v1.md`. (done 2026-02-08; implemented reconnect refresh trigger + key reuse path + explicit prepare/ack/commit flow in `apps/ble_spike/lib/security/pairing_session.dart`, `apps/ble_spike/lib/security/pairing_storage.dart`, `apps/ble_spike/lib/chat/chat_storage.dart`, `apps/ble_spike/lib/main.dart`; covered by `apps/ble_spike/test/pairing_session_reconnect_test.dart`)
- [ ] SEC-006: Secure Storage: Secrets/States in iOS Keychain + Android Keystore; Backup-Policy entscheiden und umsetzen.
- [x] SEC-007: Nonce/Counter Safety: Persistenz und Crash-Safety so, dass kein Counter-Reset zu Nonce-Reuse fuehrt. (done 2026-02-08; implemented persistent session counter state + tx reservation + rx commit in `apps/ble_spike/lib/chat/chat_models.dart`, `apps/ble_spike/lib/chat/chat_storage.dart`, `apps/ble_spike/lib/chat/chat_session.dart`, `apps/ble_spike/lib/main.dart`; covered by `apps/ble_spike/test/chat_session_test.dart`)
- [ ] SEC-008: Remote-tauglich machen: Out-of-order/duplicate/replay Regeln spezifizieren und implementieren (Ratchet erfordert das sowieso).
- [ ] SEC-009: Testpaket: deterministische Testvektoren, Property/Fuzz Tests fuer Replay/Out-of-order, und Migration Tests. (started 2026-02-08; added targeted regression tests for rotation trigger/2PC and counter persistence in `apps/ble_spike/test/pairing_session_reconnect_test.dart`, `apps/ble_spike/test/chat_session_test.dart`)

## Schritte
1. Threat Model festziehen (konkret)
- Angreifer in BLE-Reichweite (MITM).
- Server kompromittiert.
- Netzwerkbeobachter (ISP) kann Traffic-Korrelation versuchen.
- Geraet-Diebstahl (At-Rest).

2. Pairing/Trust (Erstkontakt)
- Implementiere Noise Handshake (XX) fuer Erstkontakt.
- Implementiere SAS/QR Bestätigung (muss im UI “hart” sein, nicht optional, wenn “max sicher”).
- Speichere Peer Static Public Key nach bestaetigtem Erstkontakt.

3. Reconnect (authentisiert)
- Implementiere Noise IK (oder XX mit Pinning) fuer bekannte Peers.
- Rotationsregeln aus `docs/security-spec-v1.md` umsetzen (Refresh Window, Two-Phase Commit).

4. Nachrichtenkrypto (Langzeit sicher)
- Entscheiden: “Minimal” (master_key + counter) vs “Best” (Double Ratchet).
- Empfehlung fuer “max sicher”: Double Ratchet fuer Post-Compromise Security.
- Message IDs, Replay-Schutz, Out-of-Order Handling spezifizieren (Remote braucht das).

5. Secure Storage
- iOS: Keychain, Android: Keystore-backed storage fuer Secrets.
- Persistente Counter/States so speichern, dass nach Crash kein Nonce-Reuse moeglich ist.
- Backups: bewusst entscheiden (default: kein Cloud-Backup fuer Secrets).

6. Testbarkeit
- Testvektoren fuer Handshake und Frames.
- Fuzz/Property Tests fuer Replay/Out-of-Order.
- Migration Tests fuer Key-Rotation und State-Upgrade.

## DoD
- Erstkontakt ist MITM-resistent (SAS/QR bestaetigt).
- Keine Key/Nonce-Reuse auch nach App-Neustart/Crash.
- Forward Secrecy aktiv (per Session/ephemeral) und Ratchet (wenn gewaehlt) validiert.
- Secrets liegen nur in OS Secure Storage, nicht in Klartext in App-DB.

## Offene Entscheidungen (muss frueh entschieden werden)
- Double Ratchet: ja/nein (wenn nein, muessen Claims stark eingeschraenkt werden).
- SAS: zwingend vs optional (fuer “max sicher” zwingend).
- Multi-Device: out of scope (bewusst nicht unterstuetzen, um Komplexitaet zu reduzieren).
