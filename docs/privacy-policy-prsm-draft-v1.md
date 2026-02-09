# Privacy Policy Draft (PRSM, PRIV-003)

Stand: 2026-02-09  
Status: v1 erstellt; vertragliche Hoster-Nachweise laufen separat in `PRIV-002`

## 1) Verantwortliche Stelle
- Name/Firma: PRSM Projekt (Betreiber: Kilian Volz)
- Anschrift: Betreiberanschrift in Deutschland (wird ausserhalb des Repos gepflegt)
- Kontakt: kilian@piano-volz.de

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
Wir verarbeiten Daten auf Basis von:
- Art. 6 Abs. 1 lit. b DSGVO (Bereitstellung der Messaging-/Wake-Funktion),
- Art. 6 Abs. 1 lit. f DSGVO (Missbrauchsschutz, Rate-Limits, Betriebssicherheit).

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
Fuer APNs kann ein Drittlandbezug (insb. USA) bestehen.  
Rechtsgrundlage sind geeignete Garantien nach Art. 46 DSGVO (z. B. SCC) bzw. ein anwendbarer Angemessenheitsbeschluss.

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
- E-Mail: kilian@piano-volz.de
- Prozessinternes Ticketing: `security-incident-<date>-<id>` / `privacy-request-<date>-<id>`

## 11) Aenderungen dieser Datenschutzhinweise
Diese Hinweise koennen aktualisiert werden, wenn sich Funktionen, Rechtsgrundlagen oder Empfaenger aendern.  
Versionierung erfolgt in Git.
