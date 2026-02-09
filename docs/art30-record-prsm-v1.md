# Art.-30 Verarbeitungsverzeichnis (v1, PRIV-003)

Stand: 2026-02-09  
Zuordnung: `PRIV-003` aus `docs/grant-roadmap.md`

## 1) Verantwortlicher
- Organisation: PRSM Projekt (Betreiber: Kilian Volz)
- Adresse: Betreiberanschrift in Deutschland (ausserhalb des Repos gepflegt)
- Kontakt E-Mail: kilian@piano-volz.de
- Datenschutzkontakt (falls vorhanden): kilian@piano-volz.de

## 2) Verarbeitungstaetigkeit
- Name: Store-and-Forward Message Relay + Wake Trigger
- Systeme: `server/` API (`/v1/mailbox/*`, `/v1/wake`)
- Zweck:
  - Zustellung von Ende-zu-Ende verschluesselten Nachrichten (Ciphertext-only)
  - Wake-Benachrichtigung fuer Clients (ohne Inhaltsdaten)

## 3) Kategorien betroffener Personen
- Nutzerinnen und Nutzer der App (Sender/Empfaenger)

## 4) Kategorien personenbezogener Daten
- APNs Device Token (Wake-Zweck)
- IP-/Transportmetadaten in Infrastruktur-Logs
- Pseudonyme technische IDs (`mailbox_id_hash`, `message_id`)
- Keine Klartext-Nachrichteninhalte

## 5) Kategorien von Empfaengern
- Infrastruktur-Hoster (Auftragsverarbeiter)
- Apple APNs (technischer Push-Dienst fuer Wake)

## 6) Drittlandtransfer
- APNs Transferpruefung: moeglicher Drittlandbezug (insb. USA) bei Apple Push Notification Service.
- Hoster-Standorte: EU/EWR-only als Projektvorgabe; vertragliche Bestaetigung wird in `PRIV-002` abgeschlossen.
- Rechtsgrundlage fuer Transfers: Art. 46 DSGVO (geeignete Garantien, z. B. SCC) bzw. Angemessenheitsbeschluss, soweit anwendbar.

## 7) Loeschfristen / Retention
- `relay_messages`: bis Expiry oder ACK + Grace (`RELAY_ACK_DELETE_GRACE_SEC`)
- `relay_nonces`: kurze TTL (`RELAY_NONCE_TTL_SEC`)
- `rate_limits`: nur je Zeitfenster
- `device_tokens`: bis Expiry oder Unregister
- Referenz: `docs/privacy-dsgvo-message-relay-v1.md`

## 8) TOMs (technisch/organisatorisch)
- TLS-only Betrieb (`SECURITY_TLS_ONLY=true`)
- HMAC/PoP Schutz fuer API Requests
- Replay-Schutz ueber Nonce + Timestamp
- Rate Limits pro Scope
- Datenminimierung: keine Accounts, kein Klartextinhalt

## 9) Rechtsgrundlage
- Primare Grundlage: Art. 6 Abs. 1 lit. b DSGVO (Bereitstellung Messaging/Wake) und Art. 6 Abs. 1 lit. f DSGVO (Missbrauchsschutz, Rate-Limits, Betriebssicherheit).
- Betroffene Services/Funktionen: `server/` Endpunkte `/v1/mailbox/*`, `/v1/wake`, `/v1/register`, `/v1/unregister`.

## 10) Offene Felder vor Finalisierung
- Externe Hoster-Nachweise aus `PRIV-002` als Referenz anhaengen (AVV/SLA).
- Bei Betreiberwechsel die Stammdaten in Abschnitt 1 aktualisieren.

## DoD fuer PRIV-003 (Art.-30 Teil)
- Keine Platzhalterfelder offen.
- Version mit Datum freigegeben.
- `docs/grant-roadmap.md` Update erfolgt.
