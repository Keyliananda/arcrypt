# Art.-30 Verarbeitungsverzeichnis (Entwurf, PRIV-003)

Stand: 2026-02-09  
Zuordnung: `PRIV-003` aus `docs/grant-roadmap.md`

## 1) Verantwortlicher
- Organisation: `TBD`
- Adresse: `TBD`
- Kontakt E-Mail: `TBD`
- Datenschutzkontakt (falls vorhanden): `TBD`

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
- APNs Transferpruefung: `TBD`
- Hoster-Standorte: `TBD`
- Rechtsgrundlage fuer Transfers: `TBD`

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

## 9) Rechtsgrundlage (durch Betreiber zu finalisieren)
- Primare Grundlage: `TBD`
- Betroffene Services/Funktionen: `TBD`

## 10) Offene Felder vor Finalisierung
- Verantwortlichen-Stammdaten eintragen
- Hoster- und Drittlandangaben vertraglich bestaetigen
- Rechtsgrundlage final abstimmen

## DoD fuer PRIV-003 (Art.-30 Teil)
- Alle `TBD` Felder ersetzt.
- Version mit Datum freigegeben.
- `docs/grant-roadmap.md` Update erfolgt.
