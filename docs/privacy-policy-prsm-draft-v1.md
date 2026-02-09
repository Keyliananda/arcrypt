# Privacy Policy Draft (PRSM, PRIV-003)

Stand: 2026-02-09  
Status: Entwurf, nicht final

## 1) Verantwortliche Stelle
- Name/Firma: `TBD`
- Anschrift: `TBD`
- Kontakt: `TBD`

## 2) Welche Daten wir verarbeiten
Wir verarbeiten nur Daten, die fuer den Betrieb des verschluesselten Nachrichtendiensts erforderlich sind:
- technische Zustelldaten fuer Wake-Benachrichtigungen (z. B. Push-Token),
- pseudonyme technische Kennungen (z. B. `mailbox_id_hash`, `message_id`),
- technische Betriebsdaten (z. B. Rate-Limit-Counter, Fehlercodes).

Nachrichteninhalte liegen auf dem Server nur als Ciphertext vor.

## 3) Zwecke der Verarbeitung
- Zustellung verschluesselter Nachrichten (Store-and-Forward)
- Ausloesen optionaler Wake-Benachrichtigungen
- Missbrauchsschutz und Betriebssicherheit (Rate Limits, Replay-Schutz)

## 4) Rechtsgrundlagen
Rechtsgrundlagen werden durch den Betreiber final eingetragen.  
Aktueller Platzhalter: `TBD`.

## 5) Speicherdauer
- Nachrichten werden bei Ablauf (`expires_at`) oder nach ACK + Grace geloescht.
- Nonces und Rate-Limit-Counter werden nur kurzfristig gespeichert.
- Push-Token werden bei Unregister oder Ablauf entfernt.

Details: `docs/privacy-dsgvo-message-relay-v1.md`.

## 6) Empfaenger und Auftragsverarbeiter
- Infrastruktur-Hoster (Auftragsverarbeitung)
- Apple APNs fuer Wake-Benachrichtigungen

Vertragliche Details (AVV/DPA) werden separat gepflegt: `docs/hoster-avv-dpa-checklist.md`.

## 7) Drittlandtransfer
Einsatz und Rechtsgrundlagen fuer Drittlandtransfers werden durch den Betreiber final dokumentiert (`TBD`).

## 8) Betroffenenrechte
Betroffene koennen Auskunft, Berichtigung, Loeschung und Einschraenkung anfragen.  
Das Verfahren im Minimaldatenmodell ist dokumentiert in:
- `docs/privacy-dsgvo-message-relay-v1.md` (Abschnitt Betroffenenrechte)

## 9) Sicherheit
Wir setzen technische und organisatorische Massnahmen ein, u. a.:
- TLS-only Betrieb,
- HMAC/Proof-Verifikation,
- Replay-Schutz und Rate Limits,
- Datenminimierung und kurze Retention.

## 10) Kontakt fuer Datenschutzanfragen
- E-Mail: `TBD`
- Prozessinternes Ticketing: `TBD`

## 11) Aenderungen dieser Datenschutzhinweise
Diese Hinweise koennen aktualisiert werden, wenn sich Funktionen, Rechtsgrundlagen oder Empfaenger aendern.  
Versionierung erfolgt in Git.
