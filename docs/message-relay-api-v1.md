# Message Relay API v1 - PRSM Remote

Stand: 2026-02-08
Zuordnung: SRV-002 (`docs/roadmap-message-relay-v1.md`)
Basis: `docs/untrusted-relay-principle-v1.md`

## Ziel und Scope
Diese API beschreibt den untrusted Store-and-Forward Relay fuer E2EE Ciphertext.
Sie umfasst nur Message Relay:
- `POST /v1/mailbox/push`
- `POST /v1/mailbox/pull`
- `POST /v1/mailbox/ack`

Nicht enthalten:
- Pairing/Key Exchange (Client Security Layer)
- Wake API (`/v1/wake` bleibt separat)
- Contact Discovery / Accounts

## Transportkonventionen
- Nur `POST`, JSON UTF-8, `Content-Type: application/json`.
- Antworten immer JSON mit `ok: true|false`.
- Zeitstempel als Unix Sekunden (`ts`) und RFC3339 UTC fuer Serverzeiten.
- Alle Endpunkte sind TLS-only.

## Auth- und Request-Proof
Jeder Request auf mailbox Endpunkte muss Proof-of-Possession enthalten:
- `ts` (int, Unix Sekunden)
- `nonce` (base64url, 16 Bytes random)
- `proof` (hex, 64 chars = HMAC-SHA256)

Canonical string:
`<method>\n<path>\n<ts>\n<nonce>\n<body_sha256_hex>`

`body_sha256_hex` ist SHA-256 ueber den JSON-Body **ohne** Feld `proof`, mit stabiler Key-Sortierung.

Proof:
`proof = hex(HMAC_SHA256(mailbox_pop_key, canonical_string))`

Regeln:
- `ts` darf max +/-300s vom Server abweichen.
- `nonce` darf pro Mailbox innerhalb 15 Minuten nicht wiederverwendet werden.
- `mailbox_pop_key` ist mailbox-spezifisch und wird serverseitig nur als Verifier/Commitment gespeichert.

Implementierungsprofil (Server Stand 2026-02-09):
- Fuer v1 bootstrap wird `mailbox_pop_key = mailbox_id` verwendet.
- Server speichert dazu `pop_key_commitment = SHA256("pop:" + mailbox_id)` in `relay_mailboxes`.

## Objektmodell (API Ebene)
- `mailbox_id`: base64url, 16-48 Bytes Entropie, rotiert clientseitig.
- `message_id`: serverseitige opaque ID (UUIDv7 oder 128-bit random, als String).
- `ciphertext`: base64 (enthaelt kompletten E2EE Frame, inkl. AEAD Tag).
- `cursor`: opaque String fuer Pagination.

## Endpunkt: `POST /v1/mailbox/push`
Speichert genau eine Ciphertext-Nachricht fuer eine Mailbox.

Request:
```json
{
  "mailbox_id": "b64url_mailbox_id",
  "ciphertext": "base64_ciphertext_blob",
  "expires_in_sec": 86400,
  "client_msg_id": "optional-client-idempotency-key",
  "padding": "optional-base64-padding",
  "ts": 1765238400,
  "nonce": "5dLxKx0e5o5UaA0VxW4y4Q",
  "proof": "9f...64hex"
}
```

Validierung:
- `ciphertext` Pflicht, dekodiert max 65536 Bytes.
- `expires_in_sec` optional, default 86400, min 60, max 604800.
- `client_msg_id` optional, max 128 chars (idempotentes resend).

Response `202`:
```json
{
  "ok": true,
  "message_id": "msg_01J...",
  "expires_at": "2026-02-09T12:00:00Z",
  "status": "queued"
}
```

## Endpunkt: `POST /v1/mailbox/pull`
Liest Nachrichten aus einer Mailbox ohne implizites Loeschen.

Request:
```json
{
  "mailbox_id": "b64url_mailbox_id",
  "cursor": null,
  "limit": 50,
  "ts": 1765238410,
  "nonce": "Vf9K7QfK3fQmWjFrh0A0vA",
  "proof": "ab...64hex"
}
```

Validierung:
- `limit` default 50, min 1, max 100.
- `cursor` optional opaque String.

Response `200`:
```json
{
  "ok": true,
  "messages": [
    {
      "message_id": "msg_01J...",
      "ciphertext": "base64_ciphertext_blob",
      "created_at": "2026-02-08T12:00:00Z",
      "expires_at": "2026-02-09T12:00:00Z",
      "size_bytes": 742
    }
  ],
  "next_cursor": "opaque_cursor",
  "has_more": false
}
```

## Endpunkt: `POST /v1/mailbox/ack`
Bestaetigt Empfang und loest Loeschung aus.

Request:
```json
{
  "mailbox_id": "b64url_mailbox_id",
  "message_ids": ["msg_01J...", "msg_01K..."],
  "ts": 1765238420,
  "nonce": "O0v9gM9C4GLt5mC9r1Qf7w",
  "proof": "cd...64hex"
}
```

Validierung:
- `message_ids` Pflicht, 1..100 IDs pro Request.

Response `200`:
```json
{
  "ok": true,
  "acked": ["msg_01J..."],
  "unknown": [],
  "already_acked": ["msg_01K..."]
}
```

## Fehlercodes (v1)
Einheitliches Fehlerformat:
```json
{ "ok": false, "error": "error_code", "details": {} }
```

Definierte Fehler:
- `400 invalid_json`
- `400 missing_fields`
- `400 invalid_field`
- `400 invalid_cursor`
- `401 invalid_proof`
- `401 timestamp_out_of_range`
- `401 nonce_replay`
- `404 mailbox_not_found`
- `405 method_not_allowed`
- `413 body_too_large`
- `413 ciphertext_too_large`
- `429 rate_limit`
- `503 relay_unavailable`

## Limits (v1 Defaults)
- Max request body: 128 KiB.
- Max ciphertext pro Nachricht: 64 KiB.
- Max `message_ids` pro ack: 100.
- Max pull limit: 100.
- Max retention ungeackt: 7 Tage (604800s).
- Ack/Delete Verarbeitung: spaetestens 15 Minuten.
- Rate Limits:
  - Push: 120/h pro Mailbox, 1200/h pro IP.
  - Pull: 360/h pro Mailbox, 1200/h pro IP.
  - Ack: 360/h pro Mailbox, 1200/h pro IP.

## Privacy-Regeln auf API-Ebene
- Kein Feld fuer `from`, `to`, user handles oder Contact IDs.
- `mailbox_id` wird persistent nur als `mailbox_id_hash` gespeichert.
- Server darf niemals Ciphertext in Logs schreiben.
- Fehlermeldungen bleiben absichtlich generisch (keine Enumeration-Hilfen).

## Kompatibilitaet und Versionierung
- Prefix bleibt `/v1/...`.
- Breaking Changes nur mit neuem Prefix (`/v2`).
- Additive Felder in Responses sind erlaubt; Clients muessen unbekannte Felder ignorieren.
