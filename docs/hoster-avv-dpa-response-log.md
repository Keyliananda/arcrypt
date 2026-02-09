# Hoster Antwort- und Nachweislog (PRIV-002)

Stand: 2026-02-09  
Zuordnung: `PRIV-002` aus `docs/grant-roadmap.md`

## Zweck
Zentrale Sammelstelle fuer alle eingehenden Hoster-Antworten zu AVV/DPA und Incident-SLA.

## Nutzung
1. Jede neue Rueckmeldung (Mail/Ticket/Vertragsdokument) als neuen Eintrag in der Chronik erfassen.
2. Fuer betroffene AVV-* Punkte die Detailtabelle aktualisieren.
3. Erst wenn ein Punkt mit belastbarem Nachweis belegt ist, in `docs/hoster-avv-dpa-checklist.md` auf `done` setzen.
4. Bei ausgehendem Versand immer Ticket-/Mailreferenz und Versandzeit im Outbound-Tracking nachziehen.

## Statuskriterien
- `open`: keine verwertbare Antwort vorliegend
- `in_review`: Antwort vorhanden, aber Nachweis oder Verbindlichkeit noch unklar
- `done`: schriftlicher Nachweis liegt vor (Vertrag, SLA-Anlage oder belastbare Ticketaussage)

## Detailmatrix AVV-01..AVV-08
| ID | Erwarteter Nachweis | Aktueller Status | Letzte Hoster-Antwort | Bewertet am | Ergebnis/Gap | Naechste Aktion |
| --- | --- | --- | --- | --- | --- | --- |
| AVV-01 | Signierter AVV/DPA oder verbindliche Bereitstellung inkl. Zeitpunkt | in_review | ausstehend | 2026-02-09 | Signaturdokument fehlt | Hoster-Rueckmeldung eintragen und Nachweislink hinterlegen |
| AVV-02 | Vertragliche Festlegung EU/EWR Region | in_review | ausstehend | 2026-02-09 | Vertragsklausel fehlt | Region-Nachweis abfragen/verlinken |
| AVV-03 | Subprozessorliste mit Standdatum | in_review | ausstehend | 2026-02-09 | Liste fehlt | Liste anfordern und versionieren |
| AVV-04 | TOM-Dokument (Verschluesselung, Zugriff, Backup) | in_review | ausstehend | 2026-02-09 | TOM-Nachweis fehlt | TOM-Dokument anfordern und auf Vollstaendigkeit pruefen |
| AVV-05 | Log-Retention Angaben (Dauer, Zugriff, Loeschung) | in_review | ausstehend | 2026-02-09 | Fristen fehlen | Retention-Antwort eintragen und Privacy-Policy abgleichen |
| AVV-06 | Backup/Restore- und Loeschfristen | in_review | ausstehend | 2026-02-09 | Fristen fehlen | SLA/Runbook-Nachweis eintragen |
| AVV-07 | Incident/Breach-Meldeprozess mit Zeitgrenzen | in_review | ausstehend | 2026-02-09 | Zeitgrenzen fehlen | Incident-SLA schriftlich bestaetigen lassen |
| AVV-08 | Security-Notfallkontakt und Erreichbarkeit | in_review | ausstehend | 2026-02-09 | Kontaktweg fehlt | Notfallkanal + Servicezeiten dokumentieren |

## Outbound-Tracking (Ticketversand + Follow-ups)
| Tracking-ID | Kanal | Status | Versand bestaetigt am | Ticket-/Mailreferenz | Naechster Termin | Referenz |
| --- | --- | --- | --- | --- | --- | --- |
| HOSTER-REQ-2026-02-09 | Mail/Ticket | versandbereit, Ticketreferenz ausstehend | ausstehend | ausstehend | 2026-02-12 (Follow-up 1) | `docs/hoster-avv-dpa-request-v1.md` |

## Antwort-Chronik
| Datum | Quelle | Betroffene IDs | Kurzinhalt | Nachweis-Link |
| --- | --- | --- | --- | --- |
| 2026-02-09 | Intern | AVV-01..AVV-08 | Logstruktur erstellt, wartet auf externe Antworten | Dieses Dokument |
| 2026-02-09 | Intern | AVV-01..AVV-08 | Outbound-Tracking und feste Follow-up-Termine ergaenzt | Dieses Dokument |
| 2026-02-09 | Intern | AVV-01..AVV-08 | Follow-up- und Eskalationsvorlagen fuer alle Timeline-Termine vorbereitet | `docs/hoster-avv-dpa-followup-templates-v1.md` |
