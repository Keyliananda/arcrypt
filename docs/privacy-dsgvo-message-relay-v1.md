# Privacy + DSGVO Paket (Message Relay v1)

Stand: 2026-02-09
Scope: `server/` Endpunkte `/v1/wake` und `/v1/mailbox/*`

## 1) Log-Policy (verbindlich)

Ziel: Betriebsfaehige Logs ohne Inhalte, ohne direkte Identifikatoren.

Erlaubt in Applikationslogs:
- Timestamp, Endpoint-Pfad, HTTP Statuscode, Fehlercode.
- Technische Felder ohne Personenbezug: Groesse (Bytes), Dauer (ms), Rate-Limit Scope (`ip`/`mailbox`), DB-Driver.
- Gekuerzte/abgeleitete Identifier nur gehasht (z. B. `mailbox_id_hash`), nie Rohwerte.

Verboten in Applikationslogs:
- APNs Device Token im Klartext.
- `mailbox_id`, `nonce`, `proof`, `ciphertext`, `client_msg_id` im Klartext.
- Kombination aus voller IP-Adresse und identifizierendem Token/Fingerprint in derselben Logzeile.

Regeln:
- Default Log-Level in Produktion: `info` oder strenger.
- Debug-Logging nur temporaer und mit Incident-/Ticket-Bezug aktivieren.
- Rotations-/Retention-Regeln fuer Host-Logs muessen mit der Hoster-Policy abgestimmt sein (siehe AVV-Checkliste).

## 2) Retention-Policy (verbindlich)

### Wake-Daten
- `device_tokens`: nur fuer Wake-Zustellung, mit `expires_at`.
- `wake_requests`: technische Zustellhistorie (Status/Attempts), keine Message-Inhalte.

### Relay-Daten
- `relay_messages`: Ciphertext-only; Loeschung bei `expires_at` oder nach ACK + Grace.
- `relay_nonces`: Replay-Schutz; kurze TTL.
- `rate_limits`: nur technische Counter je Zeitfenster.

### Technische Durchsetzung
- Cleanup Job: `npm run cleanup:relay` alle 5-15 Minuten per Cron.
- ACK-Grace: `RELAY_ACK_DELETE_GRACE_SEC` (default 900s).
- Expiry-Window: `RELAY_MIN_EXPIRY_SEC` bis `RELAY_MAX_EXPIRY_SEC`.

Retention-Leitplanken:
- "So kurz wie moeglich, so lang wie noetig" fuer Verfuegbarkeit.
- Keine Archivierung von Ciphertext nach Ablauf des fachlichen Zwecks.

## 3) Minimaler Record of Processing (Art. 30 DSGVO, Entwurf)

Verarbeitung: "Store-and-Forward Relay + Wake Trigger"

- Verantwortlicher: Betreiber des Dienstes (Projekt/Organisation eintragen).
- Zweck:
  - Zustellung von Ende-zu-Ende verschluesselten Nachrichten (Ciphertext-only).
  - Optionaler Wake-Trigger fuer mobile Clients.
- Kategorien betroffener Personen:
  - App-Nutzende (Sender/Empfaenger) ohne zentrale Accounts.
- Kategorien personenbezogener Daten:
  - Netz-Metadaten (IP in Transportebene/Host-Logs).
  - Pseudonyme technische Kennungen (`mailbox_id_hash`, message IDs).
  - APNs Token (nur fuer Wake, kein Inhaltsbezug).
- Empfaenger:
  - Infrastruktur-Hoster (Auftragsverarbeitung).
  - Apple APNs als technischer Push-Dienst (nur fuer Wake, kein Message-Inhalt).
- Drittlandtransfer:
  - Pruefen und dokumentieren (insb. APNs/Hoster-Region).
- Loeschfristen:
  - Relay-Nachrichten bis Expiry oder ACK+Grace.
  - Nonces und Rate-Limits nur kurzfristig.
  - Device-Tokens gemaess Expiry/Unregister.
- TOMs (technische/organisatorische Massnahmen):
  - TLS-only Transport.
  - HMAC/PoP Schutz fuer API Calls.
  - Rate Limits + Nonce Replay Schutz.
  - Datenminimierung (kein Klartextinhalt, keine Accounts).

## 4) Hoster-AVV/DPA Checkliste

Vor Produktion abhaken:

- [ ] AVV/DPA mit Hoster abgeschlossen.
- [ ] Hosting-Region (EU/EWR) dokumentiert.
- [ ] Unterauftragsverarbeiterliste vertraglich einsehbar.
- [ ] TOMs des Hosters dokumentiert (Verschluesselung, Backup, Zugriffsschutz).
- [ ] Incident-/Breach-Meldeprozess inkl. SLA geklaert.
- [ ] Log-Aufbewahrung beim Hoster geklaert (Dauer, Zugriff, Export, Loeschung).
- [ ] Backup/Restore-Strategie auf Datenminimierung und Retention abgestimmt.
- [ ] Zugangskontrolle fuer Deploy- und DB-Zugriffe dokumentiert.
- [ ] Verfahren fuer Betroffenenrechte definiert (Auskunft/Loeschung im Minimaldatenmodell).

## 5) Operative Mindestkontrollen

- Produktions-Config:
  - `SECURITY_TLS_ONLY=true`
  - `SECURITY_TRUST_PROXY=true`
  - `SECURITY_HSTS_ENABLED=true` (nach HTTPS-Stabilisierung)
- Reverse Proxy setzt `X-Forwarded-Proto=https`.
- Regelmaessige Pruefung, dass Cleanup-Cron aktiv ist.
