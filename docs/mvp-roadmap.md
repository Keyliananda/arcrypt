# MVP Roadmap – PRSM (Feb 2026)

**Kontext**
- Zielgruppe: 10–20 Freunde, die sich regelmäßig treffen
- Priorität: Sicherheit > Tempo, kein Zeitdruck
- Plattform: Android zuerst, iOS mit klaren Einschränkungen
- Identität: keine dauerhafte IDs, nur lokale Nicknames

---

## Annahmen & Korrekturen (kritisch zuerst)

### 1) BLE‑Rollenrealität (größter Blocker)
- `flutter_blue_plus` ist **Central‑only** (Scan/Connect/Notify/Write), **kein GATT‑Server/Advertising**.
- Für echtes P2P braucht ihr **zwei Plugins**:
  - Central: `flutter_blue_plus`
  - Peripheral: `flutter_ble_peripheral` (oder `bluetooth_low_energy`)
- **iOS**: Peripheral‑Mode ist stark limitiert (praktisch kein Custom‑GATT‑Server).  
  Advertising geht nur sehr eingeschränkt (UUID‑Beacon‑Art), **kein stabiler Custom‑Service**.
- **MVP‑Konsequenz**: iOS kann realistisch **nur Central** sein.  
  Android übernimmt Peripheral‑Rolle (Advertising + GATT‑Service).

**Workaround‑Regel (MVP):**
- Android‑User klickt „Sichtbar machen“ → wird Peripheral (Advertising).
- iOS‑User scannt (Central) und verbindet.
- Fallback: Android muss Pairing starten, iOS kann im MVP nicht zuverlässig advertisen.

### 2) Treffen‑Regel (finalisiert)
- Trigger: **erfolgreicher Re‑Connect + Zeit seit letztem Kontakt > 10 Minuten + Verbindung stabil >= 15 Sekunden**.
- UX: Auto‑Refresh + Undo (10s). Bei Undo/Fehler → alter Key bleibt, optionaler Prompt als Fallback.
- Ziel: Drops/Flaps nicht als „Treffen“ werten.

### 3) iOS Background (klar kommunizieren)
- Background‑Advertising auf iOS: **nicht möglich** (kein Custom‑GATT im Hintergrund).
- Background‑Scanning: nur kurzzeitige Wake‑Ups (~10 Sek.) und nur als `bluetooth‑central`.
- MVP: „App offen halten“ + Hinweis im UI.  
  BLE‑Weckung nur bei **bekannten Peripherals** nach erstem Pairing.
- Später optional: Silent‑Push‑Wake (eigener Server, Phase 2+).

---

## MVP‑Zielbild (Phase 1)
- 1:1 BLE‑Chat nur in Nähe
- Key‑Refresh bei jedem physischen Treffen
- Keine Server, keine Metadaten, keine dauerhaften IDs
- Lokale History (unbegrenzt), Export verschlüsselt

---

## Roadmap (fokussiert & realistisch)

**Status-Legende:** [done] erledigt, [wip] in Arbeit, [todo] offen

### 0) Definition & Freeze (1–2 Tage)
- [done] Finalisiere Regeln (Treffen‑Trigger, Refresh‑Flow)
- [done] Entscheide über UX: Auto‑Refresh + Undo (10s)
- [done] Dokumentiere BLE‑Test‑Matrix in `docs/ble-spike-results.md`

### 1) BLE‑Spike (3–5 Tage)
- Status: [done] Foreground‑Tests abgeschlossen, Background‑Tests offen
- [done] Test‑App mit **2 Plugins**: Central + Peripheral
- [done] Foreground‑Tests:
  - [done] iOS → Advertising funktioniert
  - [done] Android (SHIFT6m) → Scan mit UUID‑Filter funktioniert
  - [done] Connect iPhone↔Android erfolgreich (2026‑02‑01)
  - [done] ZTE Blade A32: Advertising schlägt fehl (Error 18 – Gerät unterstützt BLE Peripheral nicht zuverlässig)
- [todo] **Background‑Tests (offen, nicht vergessen!):**
  - [todo] Android: Background Advertising + Scan Verhalten
  - [todo] iOS: Background Scan Verhalten (nur kurze Wake‑Ups erwartet)
- Hinweis: **Reconnect‑Tests sind vorerst verschoben** → Phase 6 (Stabilität & Beta)
- [done] Ergebnis dokumentieren → siehe `docs/ble-spike-results.md`

### 2) Security‑Spec v1 (3–4 Tage)
- [done] Noise‑Handshake + Key‑Rotation‑Flow (Draft in `docs/security-spec-v1.md`)
- [done] Message‑Format + Nonce/Tag (Draft in `docs/security-spec-v1.md`)
- [done] State‑Machine: Idle → Pairing → Chat → Refresh (Draft in `docs/security-spec-v1.md`)

### 3) Transport‑Layer (1–2 Wochen)
- [done] GATT‑Service + **2 Characteristics** (RX: Write, TX: Notify) → `docs/transport-spec-v1.md`
- [done] Packet‑Layer (Chunking + **Stop‑and‑Wait ACK**, Duplicate‑Filter) → `docs/transport-spec-v1.md`
- [done] MTU‑Budget: iOS ~185 Bytes → **Max‑Payload 180 Bytes**, Auto‑Fragment + Seq‑Nr → `docs/transport-spec-v1.md`
- [done] **Session‑Reset‑Regel**: bei Disconnect neue Session‑ID (kein Resume im MVP) → `docs/transport-spec-v1.md`
- [todo] **Transport‑Harness** (Loopback/Mock) für Chunking/ACK vor BLE‑Integration

### 4) Chat‑Layer (1–2 Wochen)
- [todo] Encrypt/Decrypt, per‑message Ephemeral
- [todo] Local Storage (Hive)
- [todo] Nickname‑Contact‑Mapping

### 5) UI‑Flow (1 Woche)
- [todo] Scan/Connect Screen
- [todo] In‑Reichweite‑Status
- [todo] Chat + Refresh‑Status + „App offen halten“ Hinweis

### 6) Stabilität & Beta (1–2 Wochen)
- [todo] 20–50 Nachrichten, disconnect/reconnect
- [todo] iOS: Foreground‑Only getestet
- [todo] 5–10 Freundes‑Beta

---

## Risiken (Top 3)
1) BLE‑Role‑Limitations (Plugin‑Kombi instabil)
2) iOS Background‑Limits (Pairing/Refresh nur Foreground)
3) iOS GATT‑Peripheral praktisch nicht möglich → **asymmetrische Rollen**
4) MTU/Chunking (Fragmentierung & Reliability)

---

## Nächste Schritte (konkret)
1) [done] Transport‑Layer‑Spezifikation anstoßen (GATT + Packet‑Layer + Session‑Reset) → `docs/transport-spec-v1.md`
2) [todo] Kleinen **Transport‑Harness** bauen und 1/5/10 KB Payload testen
3) [todo] Security‑Spec v1 kurz gegen Transport‑Header/Session‑ID gegenlesen

---

## Codex Memory – Arbeitsplan & Test‑Rhythmus

**Arbeitsregeln (kurz)**
- Jede Aufgabe in kleine, prüfbare Schritte zerlegen (max. 1–2 Tage je Schritt).
- Nach *jedem* Schritt: Test/Check durchführen, Ergebnis dokumentieren, Status aktualisieren.
- Tests/Checks immer in `docs/ble-spike-results.md` oder im jeweiligen Schritt notieren.
- Erst danach den nächsten Schritt beginnen.

**Standard‑Testablauf (je Schritt)**
- **Doku‑Check**: Entscheidungen/Änderungen in diesem Dokument festhalten.
- **Repo‑Check**: Falls Code existiert, passende Test‑/Lint‑Befehle im Projekt suchen und ausführen.
- **Manual‑Check**: UX/BLE‑Flow einmal end‑to‑end durchspielen (wenn anwendbar).
- **Risiko‑Check**: Gibt es neue iOS/Android Einschränkungen? Falls ja, notieren.

---

## Zerlegte Parts mit Tests (DoD pro Schritt)

### 0) Definition & Freeze
**Zerlegung**
- Treffen‑Trigger final definieren (inkl. Zeitfenster).
- Refresh‑Flow entscheiden (Auto vs. Prompt).
- BLE‑Test‑Matrix konkretisieren.

**Tests/Checks**
- Konsistenz‑Check der Regeln (keine Widersprüche).
- Review der Annahmen: iOS‑Limits und Rollenmodell bestätigt.

**DoD**
- Regeln + UX‑Entscheid dokumentiert, Matrix in `docs/ble-spike-results.md` vorbereitet.

---

### 1) BLE‑Spike
**Zerlegung**
- Test‑App mit Central + Peripheral Plugins aufsetzen.
- Android: Advertising + GATT‑Service verifizieren.
- iOS: Central‑Scan + Connect verifizieren.
- Background‑Verhalten testen (Android/iOS).

**Tests/Checks**
- Manuelle Test‑Matrix (Android/iOS, Foreground/Background).
- Reconnect‑Test nach 10+ Minuten.

**DoD**
- Ergebnisliste „geht/geht nicht/Workaround“ in `docs/ble-spike-results.md`.

---

### 2) Security‑Spec v1
**Zerlegung**
- Noise‑Handshake Flow skizzieren.
- Key‑Rotation‑Regeln definieren.
- Message‑Format (Nonce/Tag) beschreiben.
- State‑Machine als Diagramm/Sequenz.

**Tests/Checks**
- Threat‑Review: Replay, MITM, Key‑Reuse, State‑Desync.

**DoD**
- Konsistente Spec mit eindeutigen Zuständen und Nachrichtenformat.

---

### 3) Transport‑Layer
**Zerlegung**
- GATT‑Service + 2 Characteristics definieren (RX: Write, TX: Notify).
- Packet‑Layer spezifizieren: **Stop‑and‑Wait** (Seq + ACK) + Duplicate‑Filter.
- MTU‑Budget fix (Max‑Payload 180 Bytes).
- **Session‑Reset‑Regel** definieren (Disconnect → neue Session‑ID, kein Resume).
- **Transport‑Harness** (Loopback/Mock) für Chunking/ACK, bevor BLE integriert wird.

**Tests/Checks (vorerst nicht)**
- [vorerst nicht] Übertragungs‑Test: 1/5/10 KB Payload im Harness.
- [vorerst nicht] Loss/Retry‑Test: künstliches Drop‑Pattern im Harness (ohne Reconnect).
- [vorerst nicht] Disconnect mid‑message: Buffer leeren, kein Resume.

**DoD**
- Transport‑Spezifikation + Harness + minimaler Testplan dokumentiert.

---

### 4) Chat‑Layer
**Zerlegung**
- Encrypt/Decrypt‑Flow festlegen.
- Per‑Message Ephemeral Keys definieren.
- Local Storage (Hive) Schema festlegen.
- Nickname‑Mapping definieren.

**Tests/Checks**
- Verschlüsselung: Korruptes Paket → korrekt abgewiesen.
- Storage‑Test: Persistenz über App‑Restart.

**DoD**
- Chat‑Layer‑Spezifikation + Storage‑Schema dokumentiert.

---

### 5) UI‑Flow
**Zerlegung**
- Scan/Connect Screen Wireframe.
- In‑Reichweite‑Statuslogik.
- Chat‑Screen + Refresh‑Status.
- „App offen halten“ Hinweis.

**Tests/Checks**
- Manuelle UX‑Tour: Scan → Connect → Chat → Refresh.

**DoD**
- UI‑Flow dokumentiert, Screens konsistent mit BLE‑Limitations.

---

### 6) Stabilität & Beta
**Zerlegung**
- 20–50 Nachrichten‑Stress‑Test.
- Disconnect/Reconnect‑Szenarien (inkl. 10+ Minuten).
- iOS Foreground‑Only Verhalten verifizieren.
- 5–10 Freundes‑Beta vorbereiten.

**Tests/Checks**
- Crash/Leak‑Check, Wiederanlauf nach Abbruch.

**DoD**
- Stabilitäts‑Ergebnis dokumentiert, Beta‑Kriterien erfüllt.
