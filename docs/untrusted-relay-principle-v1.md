# Untrusted Relay Prinzip v1 - PRSM Remote

Stand: 2026-02-08
Scope: Message Relay v1 (Store-and-Forward), nicht Wake-only Relay.

## Ziel
Der Server ist ein untrusted Transportknoten. Er darf fuer Zustellung noetig sein, aber er darf keine Nachrichteninhalte und keine stabilen sozialen Graphdaten kennen.

## Trust Modell
- Endgeraete sind vertrauenswuerdig fuer Klartext und Schluesselverwaltung.
- Der Relay-Server ist nicht vertrauenswuerdig fuer Vertraulichkeit.
- Angreifer darf Server-Datenbank, Server-Logs und Netzwerkverkehr sehen.

Folge:
- Klartext und Langzeitschluessel duerfen nie am Server landen.
- Alle Serverdaten muessen fuer Inhalte "ciphertext-only" bleiben.

## Datenfluss (v1)
1. Sender verschluesselt Nachricht lokal (E2EE) und berechnet mailbox_id aus Shared Secret (rotierend).
2. Sender ruft `POST /v1/mailbox/push` auf und uebergibt nur mailbox_id, ciphertext, expiry, optional padding.
3. Server speichert nur den Ciphertext-Blob mit minimalen Relay-Metadaten.
4. Empfaenger ruft `POST /v1/mailbox/pull` auf (mailbox_id + cursor/limit) und erhaelt Ciphertext-Objekte.
5. Empfaenger bestaetigt mit `POST /v1/mailbox/ack` (message_id) oder per pull-delete Semantik.
6. Optionaler Wake bleibt separat (`/v1/wake`), ohne Message-Inhalte.

## Erlaubte gespeicherte Felder
Nur folgende Kategorien sind fuer Message Relay erlaubt:
- `mailbox_id_hash`: Hash der mailbox_id (nie raw mailbox_id persistent speichern).
- `message_id`: zufaellige, serverseitig eindeutige ID.
- `ciphertext`: kompletter verschluesselter Payload (inkl. AEAD tag).
- `created_at`, `expires_at`, `acked_at`: technische Zeitstempel.
- `status`: `queued` | `delivered` | `acked` | `expired` (oder aequivalent).
- `size_bytes`: technische Groesse fuer Limits/Abuse Guard.

Verboten:
- Klartextfelder (`from`, `to`, `username`, Telefonnummer, Email, Inhalt, Suchtext).
- Persistente Kontaktlisten/Graphdaten.
- Device Fingerprints oder Advertising IDs.
- Analytics-Events pro Nutzer.

## Retention (hart)
- Standard fuer ungeackte Nachrichten: max 7 Tage oder frueheres `expires_at` (kleinerer Wert gewinnt).
- Nach ACK: Loeschung schnellstmoeglich, spaetestens innerhalb von 15 Minuten durch Cleanup Job.
- Abgelaufene Nachrichten: Loeschung spaetestens innerhalb von 15 Minuten durch Cleanup Job.
- Backups mit Relay-Inhalten muessen dieselbe oder kuerzere Aufbewahrung erzwingen.

## Log Policy (minimal)
- Applikationslogs enthalten nur Betriebsdaten: route, status code, dauer, groessenklasse, anzahl.
- Keine Logs mit `ciphertext`, raw `mailbox_id`, Push-Token oder HMAC/PoP Material.
- IP-Adressen nur fuer kurzfristige Abuse-Erkennung; getrennt von Relay-Objekten und kurz aufbewahrt (max 24h).
- Fehlerlogs werden redigiert (keine Request-Bodies in Stacktraces/Debug-Logs).

## Technische Leitplanken
- TLS-only fuer alle Endpunkte.
- Request-Proof pro Mailbox (HMAC/PoP) und Rate-Limits sind Pflicht.
- Mailbox-IDs rotieren clientseitig, serverseitig keine stabile globale User-ID.
- Wake-Service bleibt logisch getrennt vom Message Relay.

## Security Claims (konservativ)
Wir claimen:
- Server kann Inhalte nicht im Klartext lesen (bei korrekter E2EE Implementierung).
- Server speichert nur minimal benoetigte Relay-Metadaten mit kurzer Retention.

Wir claimen nicht:
- Vollstaendige Unbeobachtbarkeit gegen globale Traffic-Korrelation.
- Schutz, wenn Endgeraete kompromittiert sind.
