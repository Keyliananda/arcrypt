# Nebenroadmap 2 – Message Relay v1 (Server, Store-and-Forward, Wake) – Feb 2026

Ziel: Remote-Zustellung ueber eigenen Server, ohne dass der Server Inhalte lesen kann und mit minimaler Metadaten-Oberflaeche. Wake (APNs) ist bereits als “Silent Wake Relay” vorhanden; hier kommt “Message Relay” hinzu.

Nicht-Ziele:
- Accounts/Logins.
- Contact Discovery im Server.
- Analytics/Tracking.

## Taskliste (in Reihenfolge)
- [x] SRV-001: “Untrusted Relay” Prinzip dokumentieren: Datenfluss, gespeicherte Felder, Retention, Logs (kurz, aber eindeutig). (done 2026-02-08; added `docs/untrusted-relay-principle-v1.md`)
- [x] SRV-002: API v1 spezifizieren (Request/Response, Fehlercodes, Limits) fuer push/pull/ack. (done 2026-02-08; added `docs/message-relay-api-v1.md`)
- [ ] SRV-003: Datenmodell + Migration (SQLite + optional MySQL) implementieren, inkl. expiry cleanup.
- [ ] SRV-004: Abuse-Guard: size limits, rate limits, und Request-Proof (HMAC/PoP) pro Mailbox.
- [ ] SRV-005: Implementierung im Node Server (neue Endpoints) inkl. Tests (`node --test`).
- [ ] SRV-006: Wake Integration: Client-seitig Workflow definieren (push -> optional wake), Server-seitig bleibt Wake separat (wie `docs/server-roadmap.md`).
- [ ] SRV-007: Privacy/DSGVO: Log-Policy, Retention-Policy, minimaler “Record of Processing” Entwurf, und Hoster-AVV Checkliste.
- [ ] SRV-008: Deployment Runbook aktualisieren (Sparse Checkout), plus “prod hardening” (TLS-only, HSTS falls moeglich).

## Architektur (kurz)
- Server bietet “Mailboxes” an, adressiert ueber rotierende IDs (aus einem Shared Secret abgeleitet).
- Client legt Ciphertext-Nachrichten in die Mailbox, Empfaenger pollt und loescht nach ACK.
- APNs/FCM Push ist nur Wake-Up Trigger (keine Inhalte, keine Kontakt-IDs).

## Schritte
1. API Design (v1)
- `POST /v1/mailbox/push` (mailbox_id, ciphertext, expiry, optional padding)
- `POST /v1/mailbox/pull` (mailbox_id, cursor/limit)
- `POST /v1/mailbox/ack` (message_id) oder “pull-delete” Semantik
- Replays/Abuse: Rate Limits, size limits, proof-of-possession (HMAC o. a.)

2. Datenmodell
- Nachrichten: mailbox_id_hash, message_id, ciphertext, created_at, expires_at, status.
- Keine Klartext-Metadaten wie “to/from”.
- Retention: harte Loeschung nach expiry oder nach ACK.

3. Auth/Abuse-Guard
- Kein User-Login; stattdessen Request Proof (z. B. HMAC ueber mailbox_id + ts).
- IP Logging minimieren; getrennte Logs ohne Identifier.

4. Integration mit Wake Relay
- Wenn Client push’t, kann er zusaetzlich `/v1/wake` aufrufen (existiert).
- Server muss nicht “wissen”, wer Empfaenger ist; Wake-Token ist separat verwaltet.

5. EU/DSGVO-Hardening
- Retention Policy dokumentieren und enforced.
- Export/Deletion Prozesse fuer alles, was am Server laeuft (auch wenn minimal).
- AVV/DPA mit Hoster; EU-Region; TLS-only; HSTS wenn moeglich.

6. Deployment
- Gemeinsam mit bestehendem `server/` deploybar (Monorepo Sparse Checkout ist dokumentiert).
- DB: SQLite fuer MVP ok, MySQL optional.

## DoD
- Remote Zustellung funktioniert: Sender offline/online, Empfaenger offline/online.
- Server kompromittiert => Inhalte bleiben geheim (Ciphertext-only).
- Retention/Loeschung ist technisch erzwungen.
- Rate limiting + request proof verhindern triviales Spamming.

## Offene Entscheidungen
- WebSocket vs HTTP Polling (WS reduziert Latenz, Polling reduziert State am Server).
- Multi-Relay Support (optional fuer Resilienz/Anti-Correlation).
- Padding/Cover Traffic (Security vs Battery/Cost).
