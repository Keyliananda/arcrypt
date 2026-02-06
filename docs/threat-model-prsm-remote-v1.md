# Threat Model – PRSM Remote (E2EE, eigener Relay, kein Account) – v1 (Feb 2026)

Zweck: Dieses Dokument beschreibt das Bedrohungsmodell fuer “PRSM Remote” (Internet-Transport ueber eigenen, **untrusted** Server) und leitet daraus explizite Security-Claims ab: was wir versprechen – und was explizit **nicht**.

## Systemuebersicht (Scope)
- Zwei Peers (Mobile Apps) tauschen Nachrichten Ende-zu-Ende verschluesselt aus.
- Erstkontakt/Trust erfolgt **Out-of-Band** (QR / BLE-Handshake mit SAS); danach Peer-Keys werden gepinnt (TOFU mit Verifikation).
- Ein eigener Relay-Server uebernimmt Store-and-Forward und ggf. Push/Wake (ohne Inhalte).

## Schutzgueter (Assets)
- Nachrichteninhalte (Vertraulichkeit, Integritaet, Authentizitaet).
- Langzeit-Identitaetskeys / Peer-Pinning-Daten.
- Session-/Ratchet-States (falls genutzt), Nonce/Counter-States.
- Kontaktgraph/Metadaten (wer spricht wann mit wem, wie oft, groesse).
- Verfuegbarkeit (Nachrichten sollen ankommen, sobald beide online sind).

## Angreifer & Faehigkeiten
- **A1: Lokaler Angreifer in BLE-Reichweite** (MITM beim Erstkontakt/Handshake).
- **A2: Netzwerkangreifer/Beobachter** (ISP/WLAN, kann Traffic sehen, blocken, korrelieren).
- **A3: Server kompromittiert / boesartig** (liest DB/Logs, liefert manipulierte Antworten aus, loescht/delayed).
- **A4: Geraet kompromittiert / Diebstahl** (physisch oder malware; Zugriff auf App-Speicher moeglich).
- **A5: Remote-Spam/Abuse** (DoS gegen Server oder gegen Mailboxes).

## Annahmen
- Kryptoprimitive sind korrekt implementiert (NaCl/libsodium/OS Crypto) und sicher konfiguriert.
- OS Secure Storage (iOS Keychain / Android Keystore) ist “best effort” gegen reine App-Sandbox-Angriffe, aber nicht gegen vollstaendige Geraet-Kompromittierung.
- Push/Wake (APNs/FCM) kann Metadaten leaken (z. B. dass App installiert ist / Wake Events).

## Security-Ziele
1. **Inhalte schuetzen**: Dritte (inkl. Server) koennen Inhalte nicht lesen oder unbemerkt veraendern.
2. **MITM-resistenter Erstkontakt**: Beim Pairing ist ein Angreifer in der Naehe nicht in der Lage, sich einzuklinken, ohne dass Nutzer es merkt (SAS/QR).
3. **Forward Secrecy** (mind. pro Session; besser: Ratchet/Post-Compromise Security).
4. **Nonce/Counter-Sicherheit**: Keine Nonce/Key-Wiederverwendung durch Neustart/Crash.
5. **Metadaten minimieren**: Keine stabilen globalen IDs; kurze Retention; minimale Logs.

## Explizite Security-Claims (was wir versprechen)
- **C1 (E2EE Vertraulichkeit):** Der Relay-Server sieht nur Ciphertext; kompromittierter Server offenbart **keine** Klartextnachrichten.
- **C2 (E2EE Integritaet/Auth):** Manipulierte Nachrichten/Frames werden vom Client erkannt und verworfen.
- **C3 (MITM beim Erstkontakt):** Pairing ist nur erfolgreich, wenn beide Nutzer SAS/QR bestaetigen; ohne diese Bestaetigung gibt es keinen “stillen” Trust.
- **C4 (Key-Pinning):** Nach bestaetigtem Erstkontakt wird der Peer-Identitaetskey gepinnt; spaetere Key-Aenderungen werden als Sicherheitsereignis behandelt (kein stilles Downgrade).
- **C5 (Crash/Restart Safety):** Persistenzregeln verhindern Nonce/Counter-Reset und damit Nonce-Reuse.
- **C6 (Datenminimierung am Server):** Server speichert nur das Minimum fuer Store-and-Forward und loescht automatisch nach kurzer Retention; Logs enthalten keine Inhalte.

## Nicht-Claims (was wir NICHT versprechen)
- **N1 (Metadaten-Freiheit):** Wir koennen Traffic-Korrelation nicht vollstaendig verhindern (Zeitpunkt/Groesse/Push-Wakes bleiben beobachtbar).
- **N2 (Verfuegbarkeit):** Ein boesartiger Server/Netzwerk kann Nachrichten droppen, delayen oder DoS betreiben.
- **N3 (Komplettes Device-Compromise):** Bei kompromittiertem Endgeraet kann ein Angreifer Inhalte/Keys abgreifen (auch trotz Secure Storage).
- **N4 (Screenshot/Shoulder-Surfing):** Schutz vor lokalem Abfilmen/Abfotografieren ist out of scope.
- **N5 (Anonymitaet):** Keine Zusage von “anonym gegenueber Peer”; beim Pairing lernen sich Peers kennen (OOB).

## Hauptbedrohungen -> geplante Gegenmassnahmen (Mapping)
- MITM beim Erstkontakt (A1) -> SAS/QR verpflichtend, klare UI, Abbruch bei Unsicherheit, danach Key-Pinning.
- Server-Manipulation (A3) -> E2EE Auth/AEAD, Replay/Out-of-Order Regeln, keine stillen Downgrades.
- Replay/Nonce-Reuse (A2/A3) -> persistente Counter/States, atomare Updates, Duplicate/Reorder Handling.
- Metadaten-Exzess (A2/A3) -> rotierende Mailbox-IDs, kurze Retention, minimale/abgeschaltete Access-Logs, Push nur als Wake.
- DoS/Abuse (A5) -> Rate Limits, mailbox-scope quotas, einfache Abuse-Signale ohne Nutzer-Tracking.

## Residual Risk (bewusst akzeptiert)
- Beobachter kann Kommunikationsmuster teilweise korrelieren (auch mit Rotationen/Retention).
- Server kann Service verweigern; Clients brauchen klare “nicht zugestellt” Signale.

