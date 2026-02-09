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
| AVV-01 | AVV/DPA abgeschlossen (Signatur beider Parteien) | in_review | Anfragepaket `docs/hoster-avv-dpa-request-v1.md` |
| AVV-02 | Hosting-Region EU/EWR vertraglich festgehalten | in_review | Anfragepaket `docs/hoster-avv-dpa-request-v1.md` |
| AVV-03 | Liste Unterauftragsverarbeiter einsehbar und aktuell | in_review | Anfragepaket `docs/hoster-avv-dpa-request-v1.md` |
| AVV-04 | TOMs dokumentiert (Verschluesselung, Zugriff, Backup) | in_review | Anfragepaket `docs/hoster-avv-dpa-request-v1.md` |
| AVV-05 | Log-Retention beim Hoster geklaert (Dauer, Zugriff, Loeschung) | in_review | Anfragepaket `docs/hoster-avv-dpa-request-v1.md` |
| AVV-06 | Backup/Restore-Fristen + Loeschfristen abgestimmt | in_review | Anfragepaket `docs/hoster-avv-dpa-request-v1.md` |
| AVV-07 | Incident/Breach-Meldeprozess mit Zeitgrenzen geklaert | in_review | Anfragepaket `docs/hoster-avv-dpa-request-v1.md` |
| AVV-08 | Kontaktweg fuer Security-Notfaelle (24/7 oder geschaeftszeit) dokumentiert | in_review | Anfragepaket `docs/hoster-avv-dpa-request-v1.md` |

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

## Naechste externe Aktion
1. Anfrage aus `docs/hoster-avv-dpa-request-v1.md` an den Hoster senden.
2. Rueckmeldung als Nachweis (Ticket/Vertrag/PDF) in den Spalten "Nachweis" eintragen.
3. Status pro AVV-* Punkt auf `done` umstellen, sobald schriftliche Bestaetigung vorliegt.

## DoD fuer PRIV-002
- Alle Punkte `AVV-01` bis `AVV-08` auf `done`.
- Nachweise liegen versioniert in `docs/` oder als verlinkte Vertragsablage vor.
- `docs/grant-roadmap.md` markiert `PRIV-002` als erledigt.
