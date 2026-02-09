# Hoster AVV/DPA + Incident-SLA Checkliste (PRIV-002)

Stand: 2026-02-09  
Zuordnung: `PRIV-002` aus `docs/grant-roadmap.md`

## Ziel
Vertragliche und organisatorische Punkte mit dem Hoster strukturiert finalisieren, inklusive belastbarer Nachweise.

## Statuslegende
- `open`: noch nicht bearbeitet
- `in_review`: mit Hoster in Klaerung
- `done`: schriftlich bestaetigt (Vertrag oder Ticketnachweis)

## Steuerung (bis `done` verpflichtend)
- Owner: Projektteam PRSM
- Follow-up-Kadenz: alle 3 Werktage bis alle AVV-* Punkte auf `done` stehen
- Arbeitsprotokoll:
  1. Neue Hoster-Antwort in `docs/hoster-avv-dpa-response-log.md` erfassen.
  2. Je AVV-* Punkt Status/Nachweis in dieser Checkliste aktualisieren.
  3. Wenn AVV-01..AVV-08 alle `done` sind, `docs/grant-roadmap.md` auf erledigt setzen.

## Pflichtpunkte
| ID | Punkt | Status | Nachweis | Letzter Kontakt | Naechster Schritt |
| --- | --- | --- | --- | --- | --- |
| AVV-01 | AVV/DPA abgeschlossen (Signatur beider Parteien) | in_review | Anfragepaket `docs/hoster-avv-dpa-request-v1.md`; Antwortlog `docs/hoster-avv-dpa-response-log.md` | 2026-02-09 | Hoster-Antwort einpflegen und Signatur-Nachweis verlinken |
| AVV-02 | Hosting-Region EU/EWR vertraglich festgehalten | in_review | Anfragepaket `docs/hoster-avv-dpa-request-v1.md`; Antwortlog `docs/hoster-avv-dpa-response-log.md` | 2026-02-09 | Vertragsklausel oder schriftliche Bestaetigung ablegen |
| AVV-03 | Liste Unterauftragsverarbeiter einsehbar und aktuell | in_review | Anfragepaket `docs/hoster-avv-dpa-request-v1.md`; Antwortlog `docs/hoster-avv-dpa-response-log.md` | 2026-02-09 | Aktuelle Subprozessor-Liste mit Standdatum dokumentieren |
| AVV-04 | TOMs dokumentiert (Verschluesselung, Zugriff, Backup) | in_review | Anfragepaket `docs/hoster-avv-dpa-request-v1.md`; Antwortlog `docs/hoster-avv-dpa-response-log.md` | 2026-02-09 | TOM-Dokument/PDF verlinken und auf Vollstaendigkeit pruefen |
| AVV-05 | Log-Retention beim Hoster geklaert (Dauer, Zugriff, Loeschung) | in_review | Anfragepaket `docs/hoster-avv-dpa-request-v1.md`; Antwortlog `docs/hoster-avv-dpa-response-log.md` | 2026-02-09 | Retention-Fristen in Policy uebernehmen und Nachweis verlinken |
| AVV-06 | Backup/Restore-Fristen + Loeschfristen abgestimmt | in_review | Anfragepaket `docs/hoster-avv-dpa-request-v1.md`; Antwortlog `docs/hoster-avv-dpa-response-log.md` | 2026-02-09 | Backup-/Restore-SLA dokumentieren und Loeschfristen eintragen |
| AVV-07 | Incident/Breach-Meldeprozess mit Zeitgrenzen geklaert | in_review | Anfragepaket `docs/hoster-avv-dpa-request-v1.md`; Antwortlog `docs/hoster-avv-dpa-response-log.md` | 2026-02-09 | Meldefristen aus Hoster-SLA gegen interne 72h-Regel abgleichen |
| AVV-08 | Kontaktweg fuer Security-Notfaelle (24/7 oder geschaeftszeit) dokumentiert | in_review | Anfragepaket `docs/hoster-avv-dpa-request-v1.md`; Antwortlog `docs/hoster-avv-dpa-response-log.md` | 2026-02-09 | Notfall-Kontaktkette mit Kanal und Erreichbarkeit dokumentieren |

## Incident-SLA Mindestfragen (an den Hoster)
- Wie schnell erfolgt Erstmeldung bei Security-Incidents (z. B. <= 24h)?
- Welche Infos liefert die Erstmeldung mindestens (Umfang, betroffene Systeme, Zeitfenster)?
- Wie werden Updates waehrend des Incidents bereitgestellt (Intervall, Kanal)?
- Wie schnell liefert der Hoster Abschlussbericht + Root-Cause?
- Gibt es separate Fristen fuer Datenabfluss vs. Verfuegbarkeitsstoerung?

## Evidence-Log (laufend)
| Datum | Ansprechpartner | Thema | Ergebnis | Referenz |
| --- | --- | --- | --- | --- |
| 2026-02-09 | Hoster Support (offen) | Checklist initialisiert | Vorbereitung abgeschlossen | Dieses Dokument |
| 2026-02-09 | Hoster Support (offen) | Vollstaendiges Anfragepaket fuer AVV/SLA erstellt | Externe Klaerung gestartet (`in_review`) | `docs/hoster-avv-dpa-request-v1.md` |
| 2026-02-09 | Intern (PRSM Team) | Antwort-/Nachweislog strukturiert angelegt | Abschlussstrecke fuer `PRIV-002` vorbereitet | `docs/hoster-avv-dpa-response-log.md` |

## Naechste externe Aktion
1. Anfrage aus `docs/hoster-avv-dpa-request-v1.md` an den Hoster senden bzw. Ticket-Referenz erfassen.
2. Jede Rueckmeldung sofort in `docs/hoster-avv-dpa-response-log.md` dokumentieren.
3. Nachweise pro AVV-* Punkt in dieser Checkliste verlinken und Status schrittweise auf `done` umstellen.

## DoD fuer PRIV-002
- Alle Punkte `AVV-01` bis `AVV-08` auf `done`.
- Nachweise liegen versioniert in `docs/` oder als verlinkte Vertragsablage vor.
- `docs/grant-roadmap.md` markiert `PRIV-002` als erledigt.
