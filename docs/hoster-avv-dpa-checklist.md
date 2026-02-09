# Hoster AVV/DPA + Incident-SLA Checkliste (PRIV-002)

Stand: 2026-02-09  
Zuordnung: `PRIV-002` aus `docs/grant-roadmap.md`

## Ziel
Vertragliche und organisatorische Punkte mit dem Hoster strukturiert finalisieren, inklusive belastbarer Nachweise.

## Statuslegende
- `open`: noch nicht bearbeitet
- `in_review`: mit Hoster in Klaerung
- `done`: schriftlich bestaetigt (Vertrag oder Ticketnachweis)

## Pflichtpunkte
| ID | Punkt | Status | Nachweis |
| --- | --- | --- | --- |
| AVV-01 | AVV/DPA abgeschlossen (Signatur beider Parteien) | open | Vertragskopie |
| AVV-02 | Hosting-Region EU/EWR vertraglich festgehalten | open | Vertrag/Anlage |
| AVV-03 | Liste Unterauftragsverarbeiter einsehbar und aktuell | open | URL/PDF + Datum |
| AVV-04 | TOMs dokumentiert (Verschluesselung, Zugriff, Backup) | open | TOM-Dokument |
| AVV-05 | Log-Retention beim Hoster geklaert (Dauer, Zugriff, Loeschung) | open | Ticketantwort |
| AVV-06 | Backup/Restore-Fristen + Loeschfristen abgestimmt | open | Runbook + Vertrag |
| AVV-07 | Incident/Breach-Meldeprozess mit Zeitgrenzen geklaert | open | SLA/Vertrag |
| AVV-08 | Kontaktweg fuer Security-Notfaelle (24/7 oder geschaeftszeit) dokumentiert | open | Kontaktblatt |

## Incident-SLA Mindestfragen (an den Hoster)
- Wie schnell erfolgt Erstmeldung bei Security-Incidents (z. B. <= 24h)?
- Welche Infos liefert die Erstmeldung mindestens (Umfang, betroffene Systeme, Zeitfenster)?
- Wie werden Updates waehrend des Incidents bereitgestellt (Intervall, Kanal)?
- Wie schnell liefert der Hoster Abschlussbericht + Root-Cause?
- Gibt es separate Fristen fuer Datenabfluss vs. Verfuegbarkeitsstoerung?

## Evidence-Log (laufend)
| Datum | Ansprechpartner | Thema | Ergebnis | Referenz |
| --- | --- | --- | --- | --- |
| 2026-02-09 | TBD | Checklist initialisiert | Vorbereitung abgeschlossen | Dieses Dokument |

## DoD fuer PRIV-002
- Alle Punkte `AVV-01` bis `AVV-08` auf `done`.
- Nachweise liegen versioniert in `docs/` oder als verlinkte Vertragsablage vor.
- `docs/grant-roadmap.md` markiert `PRIV-002` als erledigt.
