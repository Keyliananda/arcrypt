# Grant Roadmap – PRSM Remote (EU, E2EE, eigener Server) – Feb 2026

Ziel: Remote-Zustellung ueber den eigenen Server (inkl. Wake), maximaler Schutz gegen Abhoeren (Inhalte) und stark reduzierte Metadaten, ohne Accounts/Telefonnummern. EU/DE-rechtlich (DSGVO) sauber durch Datenminimierung, kurze Retention und klare Verarbeitung.

Kontext:
- Phase 1 (heute): BLE Chat in Naehe. Specs existieren: `docs/security-spec-v1.md`, `docs/transport-spec-v1.md`, `docs/chat-spec-v1.md`.
- Server existiert: Silent Wake Relay, kein Message-Relay. Siehe `docs/server-roadmap.md`, `server/README.md`.
- Ziel hier: Phase 2+ “Remote Messaging” mit eigenem Relay, aber weiterhin “Server ist untrusted”.

## Leitprinzipien (entscheidend)
- Ende-zu-Ende Verschluesselung ist Pflicht: Server sieht nur Ciphertext.
- Kein globaler Identifier (keine Telefonnummer, keine E-Mail, kein Username).
- Kontaktaufnahme/Trust-on-first-use nur mit Out-of-Band: QR / manuell / BLE-Handshake mit SAS.
- Metadaten minimieren: rotierende Mailbox-IDs, kurze Speicherung, minimale Logs.
- Robustheit: Store-and-Forward fuer Offline-Peers, Push nur als Wake-Up (keine Inhalte im Push).

## Grobe Schritte bis zum finalen Ergebnis
1. Sicherheitsfundament finalisieren und implementieren (Handshake + Trust + Key-Management).
2. “Message Relay” auf dem eigenen Server bauen (separat vom Wake-Relay, aber gleiche Deployment-Story).
3. Client: Transport-Abstraktion auf “BLE-Link oder Internet-Link” erweitern, inkl. Queue/Retry/Delivery-Status.
4. Privacy/DSGVO Paket: Datenfluesse dokumentieren, Retention/Logs, AVV/DPA mit Hoster, Incident-Prozess.
5. Beta mit 10–20 Nutzern: Threat-Model-Review, pen-testbare Oberflaechen, Telemetrie bewusst = none/minimal.
6. Finalisierung: Security Review (intern) + externes Audit (wenn Budget), “Security Claims” konservativ formulieren.

## Nebenroadmaps (erste 3, fuer die Umsetzung)
- Security v2 (Handshake + Ratchet + Storage Hardening): `docs/roadmap-security-v2.md`
- Message Relay v1 (Store-and-Forward + Mailboxes + Push-Wake Integration): `docs/roadmap-message-relay-v1.md`
- Client Remote Transport v1 (Queue, Poll/Push, Link-Switch BLE<->Internet): `docs/roadmap-client-remote-transport-v1.md`

## Ausfuehrungsregel: "Naechster Task"
Wenn in einem neuen Chat nur "fuehre den naechsten Task aus" steht, ist die Erwartung:
1. Starte hier: `docs/grant-roadmap.md`.
2. Nimm den ersten nicht-erledigten Task aus der "Taskliste" in der Reihenfolge:
   - `docs/roadmap-security-v2.md` (SEC-*), dann
   - `docs/roadmap-message-relay-v1.md` (SRV-*), dann
   - `docs/roadmap-client-remote-transport-v1.md` (CLI-*).
3. Wenn ein Task eine Spezifikation benoetigt, verweise auf die v1 Specs:
   - `docs/security-spec-v1.md`
   - `docs/transport-spec-v1.md`
   - `docs/chat-spec-v1.md`
   - Server/Wake: `docs/server-roadmap.md` und `server/README.md`
4. Nach Umsetzung: Task in der jeweiligen Nebenroadmap abhaken und kurz notieren, was sich geaendert hat (Dateipfade).

## Status
- Stand: 2026-02-09
- Security-Block abgeschlossen: `SEC-001` bis `SEC-009` in `docs/roadmap-security-v2.md` sind erledigt.
- Message-Relay-Block abgeschlossen: `SRV-001` bis `SRV-008` in `docs/roadmap-message-relay-v1.md` sind erledigt.
- Letztes Update: `CLI-008` abgeschlossen (Integrationstests gegen lokalen Server fuer happy path, offline + retry und dedupe) in `apps/ble_spike/test/relay_link_local_server_integration_test.dart` und `docs/roadmap-client-remote-transport-v1.md`.
- Naechster auszufuehrender Block nach Regel "Naechster Task": keiner in den aktuellen SEC/SRV/CLI Nebenroadmaps (alle Tasks erledigt).
- Privacy/DSGVO gestartet: Betroffenenrechte-Verfahren + interner Incident-Prozess dokumentiert (siehe `docs/privacy-dsgvo-message-relay-v1.md`, done 2026-02-09).
- PRIV-002 vorbereitet: AVV/DPA + Incident-SLA Checkliste erstellt (`docs/hoster-avv-dpa-checklist.md`, 2026-02-09), vertragliche Klaerung mit Hoster bleibt offen.
- PRIV-003 vorbereitet: Drafts fuer Art.-30 Eintrag und Privacy Policy erstellt (`docs/art30-record-prsm-v1.md`, `docs/privacy-policy-prsm-draft-v1.md`, 2026-02-09), finale Betreiberdaten fehlen noch.
- Server-Roadmap Phase 3 Luecke geschlossen: Wake-Token TTL + Cleanup-Job implementiert (`server/scripts/cleanup_wake_tokens.js`, `WAKE_TOKEN_TTL_SEC`, done 2026-02-09).
- Naechster konkreter Task: Vertrags-/Providerdetails einholen und die `TBD`-Felder finalisieren.

## Taskliste (high level, nur Navigation)
- [x] SEC-001..SEC-009 : siehe `docs/roadmap-security-v2.md` (done 2026-02-08)
- [x] SRV-001..SRV-008 : siehe `docs/roadmap-message-relay-v1.md` (done 2026-02-09)
- [x] CLI-001..CLI-008 : siehe `docs/roadmap-client-remote-transport-v1.md` (done 2026-02-09)
- [x] SRV-WAKE-CLEANUP: Wake Token TTL + Expiry-Cleanup-Job implementiert (`server/scripts/cleanup_wake_tokens.js`, done 2026-02-09)
- [x] PRIV-001: Betroffenenrechte-Verfahren + interner Incident-Prozess dokumentiert (`docs/privacy-dsgvo-message-relay-v1.md`, done 2026-02-09)
- [ ] PRIV-002: AVV/DPA + Incident-SLA mit Hoster finalisieren (extern, vertraglich; Vorbereitung in `docs/hoster-avv-dpa-checklist.md`, 2026-02-09)
- [ ] PRIV-003: Betreiberdaten fuer finalen Art.-30 Eintrag und Privacy Policy final ergaenzen (Drafts in `docs/art30-record-prsm-v1.md` und `docs/privacy-policy-prsm-draft-v1.md`, 2026-02-09)

## Zwei alternative Ausloeser (gleiches Verhalten)
Diese Formulierungen sollen identisch behandelt werden wie "fuehre den naechsten Task aus":
1. "Mach mit dem naechsten offenen Punkt aus der Grant Roadmap weiter."
2. "Arbeite den naechsten offenen SEC-/SRV-/CLI-Task ab und hake ihn ab."

## Definition of Done (final)
- Zwei Peers koennen nach einem Treffen (QR/BLE) remote Nachrichten austauschen.
- Server kann kompromittiert werden, ohne Inhalte preiszugeben (Ciphertext-only).
- Minimale Metadaten am Server: keine stabilen IDs; Retention begrenzt und automatisiert.
- App uebersteht Neustarts ohne Key/Nonce-Reuse und ohne Silent Data Loss.
- DS-GVO Artefakte vorhanden: Verarbeitungsverzeichnis (kurz), Privacy Policy, Retention Policy, AVV mit Hoster, Log-Policy.
