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
- Cleanup Job: `npm run cleanup:wake` alle 5-15 Minuten per Cron (abgelaufene `device_tokens`).
- ACK-Grace: `RELAY_ACK_DELETE_GRACE_SEC` (default 900s).
- Expiry-Window: `RELAY_MIN_EXPIRY_SEC` bis `RELAY_MAX_EXPIRY_SEC`.
- Token-TTL: `WAKE_TOKEN_TTL_SEC` (default 2592000s / 30 Tage).

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

Arbeitsdokumente: `docs/hoster-avv-dpa-checklist.md` und `docs/hoster-avv-dpa-response-log.md` (initial angelegt am 2026-02-09).

- [ ] AVV/DPA mit Hoster abgeschlossen.
- [ ] Hosting-Region (EU/EWR) dokumentiert.
- [ ] Unterauftragsverarbeiterliste vertraglich einsehbar.
- [ ] TOMs des Hosters dokumentiert (Verschluesselung, Backup, Zugriffsschutz).
- [ ] Incident-/Breach-Meldeprozess inkl. SLA geklaert.
- [ ] Log-Aufbewahrung beim Hoster geklaert (Dauer, Zugriff, Export, Loeschung).
- [ ] Backup/Restore-Strategie auf Datenminimierung und Retention abgestimmt.
- [x] Zugangskontrolle fuer Deploy- und DB-Zugriffe dokumentiert. (done 2026-02-09; siehe `docs/notes/deployment_server.md`, Abschnitt "9) Zugangskontrolle (Deploy + DB)")
- [x] Verfahren fuer Betroffenenrechte definiert (Auskunft/Loeschung im Minimaldatenmodell). (done 2026-02-09; siehe Abschnitt 6)

## 5) Operative Mindestkontrollen

- Produktions-Config:
  - `SECURITY_TLS_ONLY=true`
  - `SECURITY_TRUST_PROXY=true`
  - `SECURITY_HSTS_ENABLED=true` (nach HTTPS-Stabilisierung)
- Reverse Proxy setzt `X-Forwarded-Proto=https`.
- Regelmaessige Pruefung, dass Cleanup-Cron aktiv ist.

## 6) Verfahren fuer Betroffenenrechte (Minimaldatenmodell)

Ziel: Rechteabwicklung ohne zentrale Accounts und ohne Klartextinhalte.

Eingang und Fristen:
- Eingangskanal: dedizierte Support-Adresse mit Ticket-ID.
- Erstreaktion innerhalb von 72h, Abschluss innerhalb von 30 Tagen (Regelfall).
- Jeder Fall wird als "privacy-request" protokolliert (nur Ticket-ID + Zeitstempel + Ergebnis).

Identifikation (ohne globale IDs):
- Wake-bezogene Anfrage: Nachweis ueber Besitz des Device Tokens (Token muss vom Geraet geliefert werden).
- Relay-bezogene Anfrage: Nachweis ueber Besitz der mailbox_id (oder mailbox_id_hash) des betroffenen Clients.
- Wenn kein plausibler Nachweis vorliegt, erfolgt nur allgemeine Auskunft zum Datenmodell, keine objektscharfe Auskunft.

Auskunft (Art. 15, minimal):
- Mitgeteilt werden nur technische Kategorien und gespeicherte Datensaetze:
  - Device-Token-Eintrag (vorhanden/nicht vorhanden, env, last_seen, expires_at).
  - Wake-Request-Metadaten (status/attempts/created_at).
  - Relay-Metadaten je mailbox_id_hash (Anzahl un-acked Messages, aeltester/newester Zeitstempel, keine Inhalte).
- Es werden keine Ciphertext-Inhalte ausgegeben.

Loeschung (Art. 17, minimal):
- Wake-Daten: `device_tokens` Eintrag loeschen, zugehoerige kuenftige Wake-Nutzung stoppen.
- Relay-Daten: alle offenen/acked Nachrichten, Nonces und optional Rate-Limit-Counter zur mailbox_id_hash entfernen.
- Ergebnis als Ticketabschluss dokumentieren (Zeitpunkt, welche Tabellen betroffen waren, ohne Roh-Token im Tickettext).

Einschraenkung:
- Ohne stabile Nutzerkonten kann keine personenbezogene Profil-Auskunft erstellt werden.
- Das Verfahren ist daher strikt datenobjekt-basiert (Token/mailbox_id_hash), nicht personenbasiert.

## 7) Incident-/Breach-Prozess (intern)

Ziel: schnelle Eindammung, belastbare Dokumentation, rechtzeitige Bewertung der Meldepflicht.

T0 - Erkennung und Triage (0-4h):
- Incident Ticket anlegen (`security-incident-<date>-<id>`), Severity S1-S3 setzen.
- Sofortpruefung: betrifft es Vertraulichkeit, Integritaet oder Verfuegbarkeit?
- Erste Schutzmassnahmen: Schluesselrotation, Token-Rotation, Rate-Limits verschaerfen, notfalls Endpoint temporaer deaktivieren.

T1 - Eindammung und Analyse (bis 24h):
- Betroffene Systeme/Tabellen identifizieren (`device_tokens`, `wake_requests`, `relay_*`, Host-Logs).
- Umfang bestimmen: Datentypen, Zeitfenster, Anzahl Datensaetze, moeglicher Abfluss.
- Forensik-Artefakte sichern (Logs, DB-Snapshots, Config-Stand), Zugriffsrechte auf Incident-Kreis begrenzen.

T2 - Bewertung und Meldung (24-72h):
- DSGVO-Bewertung durch Verantwortliche Stelle: Risiko fuer Betroffene ja/nein.
- Falls meldepflichtig: Meldung an Aufsichtsbehoerde innerhalb 72h vorbereiten und absenden.
- Falls hohes Risiko fuer Betroffene: Benachrichtigung der Betroffenen nach Rechtspruefung vorbereiten.

T3 - Abschluss und Nacharbeit:
- Root-Cause und Corrective Actions dokumentieren.
- Konkrete Follow-ups mit Owner + Due Date festhalten.
- Runbooks, Hoster-AVV-Checkliste und technische Kontrollen nachziehen.

Hinweis:
- Externe SLA-/Meldepflichten mit dem Hoster bleiben separat in Abschnitt 4 offen, bis vertraglich bestaetigt.
