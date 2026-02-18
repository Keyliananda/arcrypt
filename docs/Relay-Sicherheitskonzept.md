# Relay-Sicherheitskonzept

Stand: 18. Februar 2026

## 1. Ziel

Dieses Konzept loest zwei Anforderungen gleichzeitig:

1. Relay-Konfiguration bleibt auch nach Reinstall robust und reproduzierbar.
2. Geheimnisse bleiben ausserhalb des mobilen Clients und sind serverseitig rotierbar.

Die Architektur ist fuer mehrere Gruppen (Mandanten) ausgelegt, bei denen jede Gruppe einen eigenen Server inkl. Relay und Daten betreibt.

## 2. Sicherheitsprinzipien

- Keine langlebigen Secrets im Client-Binary (`--dart-define` nur fuer nicht-sensitive Defaults).
- Runtime-Konfiguration im Secure Storage ist nur Cache, nie Root-of-Trust.
- Reinstall darf keine manuelle Support-Operation erzwingen.
- Fehlerszenarien muessen als klare Diagnosecodes sichtbar sein.
- Release-Build ohne gueltige Relay-Basis darf nicht unbemerkt ausgerollt werden.

## 3. Zielarchitektur (Produktion)

### 3.1 Nicht-sensitive Build-Defaults

Pro Flavor/Gruppe werden nur nicht-sensitive Werte gesetzt, mindestens:

- `PRSM_RELAY_BASE_URL`

Optional zusaetzlich fuers Bootstrap:

- `PRSM_RELAY_INBOUND_MAILBOX_ID`
- `PRSM_RELAY_OUTBOUND_MAILBOX_ID`

Wichtig: Das sind keine Geheimnisse, sondern nur Startwerte.

### 3.2 Bootstrap bei Erststart / nach Reinstall

Ablauf:

1. App startet.
2. Wenn keine gueltige Runtime-Konfiguration existiert, werden gueltige Build-Defaults in Secure Storage gespiegelt.
3. Danach greift normal die Prioritaet `Runtime -> Build`.

Damit ist der Reinstall-Pfad stabil, auch wenn lokale Daten geloescht wurden.

### 3.3 Geheimnisse und sensitive Parameter

Sensitive Daten (z. B. Wake-Secrets, kurzlebige Zugriffstoken, tenant-spezifisches Schluesselmaterial) kommen nur aus serverseitigem Provisioning nach Authentifizierung und werden nicht als Build-Define ausgeliefert.

Vorgaben:

- Kurzlebige Tokens.
- Serverseitige Rotation und Revocation.
- Erneutes Provisioning nach Verlust lokaler Daten.

### 3.4 Multi-Tenant-Betrieb

Jede Gruppe betreibt eigenes Backend/Relay. Die App wird pro Gruppe per Flavor oder Distributionskanal mit passender Bootstrap-Basis ausgerollt. Secrets verbleiben tenant-lokal auf dem jeweiligen Server.

## 4. Dev-Shortcut (nur Debug/Profile)

Um schnelle Neuinstallationstests zu ermoeglichen:

- Debug-only Build-Defines `PRSM_DEV_RELAY_*` sind erlaubt.
- Diese Overrides werden nur ausserhalb von Release ausgewertet.
- In Release werden diese Werte strikt ignoriert.

Ziel: schneller lokaler Bootstrap fuer Entwicklung ohne Produktionsrisiko.

## 5. Release-Guard

Release-Builds ohne `PRSM_RELAY_BASE_URL` sind unzulaessig.

Guard-Strategie:

- Harte Laufzeit-Sperre direkt beim App-Start im Produktivmodus.
- Optional CI-Check im Build-Job, damit Fehler frueh im Pipeline-Lauf auffallen.

## 6. Diagnose und Observability

Beim Start werden maschinenlesbare Konfigurationszustands-Codes erzeugt, z. B.:

- `runtime_invalid_fallback_environment`
- `runtime_invalid_no_fallback`
- `environment_invalid`
- `missing_runtime_and_environment`

Damit kann Support klar zwischen Konfigurationsverlust, Build-Fehler und inkonsistenten Runtime-Werten unterscheiden.

## 7. Konkrete Umsetzung in diesem Repo

- Runtime-Store bleibt `flutter_secure_storage`.
- Resolver liefert Source + Diagnosecode.
- First-launch Bootstrap spiegelt gueltige Build-Defaults in Runtime-Store.
- Debug-Override ist explizit und Release-sicher getrennt.
- Release-Guard blockiert fehlende Basis-URL im Produktivmodus.

## 8. Nicht-Ziele

- Keine Speicherung langlebiger API-Secrets im Client.
- Kein Vertrauen in obfuskiertes Hardcoding als Sicherheitsmassnahme.
- Kein manueller Konfigurationszwang nach jeder Neuinstallation.
