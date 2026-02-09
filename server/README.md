# Silent Wake + Message Relay (Server)

Node server for wake relay (`/v1/wake`) plus message relay v1 mailboxes (`/v1/mailbox/*`), matching `docs/server-roadmap.md` and `docs/roadmap-message-relay-v1.md`.

## Quick start

```bash
node src/server.js
```

Memory store is the default. For SQLite, install the driver and set env vars:

```bash
npm install sqlite3
```

```bash
export DB_DRIVER=sqlite
export DB_FILENAME=./data.sqlite
```

Apply the schema:

```bash
sqlite3 ./data.sqlite < schema_sqlite.sql
```

Run pending message-relay migrations:

```bash
npm run migrate
```

## Deployment (Server)

Files not in git that must exist on the server:

- `server/.env` (secrets + config; created manually, not committed)
- `server/data.sqlite` (SQLite DB file; create on the server or copy if you need to keep data)

Minimal server steps (from the repo root or inside `server/`):

```bash
cd /path/to/repo/server
cp /path/to/secure/.env ./ .env
npm install --omit=dev
sqlite3 ./data.sqlite < schema_sqlite.sql
npm run migrate
node src/server.js
```

Note: `dotenv` is loaded in `src/server.js`, so `.env` is picked up automatically.

## SQLite smoke test

The SQLite smoke test runs by default (in-memory) via:

```bash
node --test
```

## Environment variables

- `SERVER_ENABLED` (default: true) - Enable/disable server via watchdog
- `PORT` (default: 3000)
- `MAX_BODY_BYTES` (default: 131072)
- `SECURITY_TLS_ONLY` (default: false; reject non-TLS requests with `426 tls_required`)
- `SECURITY_TRUST_PROXY` (default: true; trust `X-Forwarded-Proto`/`X-Forwarded-SSL` from reverse proxy)
- `SECURITY_HSTS_ENABLED` (default: false; add HSTS response header on TLS requests)
- `SECURITY_HSTS_MAX_AGE_SEC` (default: 15552000)
- `SECURITY_HSTS_INCLUDE_SUBDOMAINS` (default: false)
- `SECURITY_HSTS_PRELOAD` (default: false)
- `HMAC_SECRET` (required for `/v1/wake`)
- `HMAC_MAX_SKEW_SEC` (default: 300)
- `RATE_LIMIT_WINDOW_SEC` (default: 3600)
- `RATE_LIMIT_TOKEN_PER_WINDOW` (default: 30)
- `RATE_LIMIT_IP_PER_WINDOW` (default: 120)
- `WAKE_TOKEN_TTL_SEC` (default: 2592000; 30 days; set `<= 0` to disable token expiry)
- `DB_DRIVER` (`memory` or `sqlite`, `mysql` optional)
- `DB_FILENAME` (SQLite filename)
- `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME` (MySQL optional)
- `RELAY_ACK_DELETE_GRACE_SEC` (default: 900; grace for deleting acked relay messages)
- `RELAY_PROOF_MAX_SKEW_SEC` (default: 300)
- `RELAY_NONCE_TTL_SEC` (default: 900)
- `RELAY_DEFAULT_EXPIRY_SEC` (default: 86400)
- `RELAY_MIN_EXPIRY_SEC` (default: 60)
- `RELAY_MAX_EXPIRY_SEC` (default: 604800)
- `RELAY_MAX_CIPHERTEXT_BYTES` (default: 65536)
- `RELAY_PULL_LIMIT_DEFAULT` (default: 50)
- `RELAY_PULL_LIMIT_MAX` (default: 100)
- `RELAY_ACK_MAX_IDS` (default: 100)
- `RELAY_RATE_LIMIT_PUSH_PER_MAILBOX` (default: 120)
- `RELAY_RATE_LIMIT_PULL_PER_MAILBOX` (default: 360)
- `RELAY_RATE_LIMIT_ACK_PER_MAILBOX` (default: 360)
- `RELAY_RATE_LIMIT_PUSH_PER_IP` (default: 1200)
- `RELAY_RATE_LIMIT_PULL_PER_IP` (default: 1200)
- `RELAY_RATE_LIMIT_ACK_PER_IP` (default: 1200)
- `APNS_ENABLED` (default: true)
- `APNS_ENV` (`sandbox` or `prod`)
- `APNS_KEY_ID` (Key ID from Apple)
- `APNS_TEAM_ID` (Team ID, not the email)
- `APNS_TOPIC` (Bundle Identifier)
- `APNS_KEY_PATH` (path to AuthKey_*.p8 on the server)
- `APNS_TIMEOUT_MS` (default: 5000)

## Endpoints (POST only)

### `/v1/health`
Returns `{ ok: true, status: "ok" }`.

### `/v1/register`
Body:

```json
{
  "token": "apns_token",
  "topic": "com.example.app",
  "env": "sandbox"
}
```

### `/v1/unregister`
Body:

```json
{
  "token": "apns_token"
}
```

### `/v1/wake`
Body:

```json
{
  "token": "apns_token",
  "ts": 1738533200,
  "proof": "<hex hmac>"
}
```

`proof` is computed as:

```
hex(HMAC_SHA256(HMAC_SECRET, token + ":" + ts))
```

Requests older/newer than `HMAC_MAX_SKEW_SEC` are rejected.

If APNs config is present, `/v1/wake` attempts a silent push immediately and
adds an `apns` field in the response with the result. If not configured, it
only queues the wake request.

### `/v1/mailbox/push`
Body:

```json
{
  "mailbox_id": "b64url_mailbox_id",
  "ciphertext": "base64_ciphertext_blob",
  "expires_in_sec": 86400,
  "client_msg_id": "optional-idempotency-key",
  "ts": 1738533200,
  "nonce": "b64url_nonce_16_bytes_min",
  "proof": "<hex hmac>"
}
```

Response: `202` with `{ ok, message_id, expires_at, status }`.

### `/v1/mailbox/pull`
Body:

```json
{
  "mailbox_id": "b64url_mailbox_id",
  "cursor": null,
  "limit": 50,
  "ts": 1738533200,
  "nonce": "b64url_nonce_16_bytes_min",
  "proof": "<hex hmac>"
}
```

Response: `200` with `{ ok, messages, next_cursor, has_more }`.

### `/v1/mailbox/ack`
Body:

```json
{
  "mailbox_id": "b64url_mailbox_id",
  "message_ids": ["msg_..."],
  "ts": 1738533200,
  "nonce": "b64url_nonce_16_bytes_min",
  "proof": "<hex hmac>"
}
```

Response: `200` with `{ ok, acked, unknown, already_acked }`.

Mailbox proof canonical string:

```
POST\n<path>\n<ts>\n<nonce>\n<body_sha256_hex_without_proof_field>
```

Proof:

```
hex(HMAC_SHA256(mailbox_id, canonical_string))
```

Mailbox requests reject timestamps outside `RELAY_PROOF_MAX_SKEW_SEC` and
reject nonce re-use inside `RELAY_NONCE_TTL_SEC`.

## Rate limiting

Wake rate limits apply per token and per IP. Mailbox rate limits apply per
mailbox hash and per IP, scoped by action (`push`, `pull`, `ack`). Counters are
stored in `rate_limits` with a window start timestamp.

## Relay expiry cleanup

Run one cleanup pass for expired relay rows and aged acked rows:

```bash
npm run cleanup:relay
```

Use cron to run this every 5-15 minutes.

## Wake token expiry cleanup

Run one cleanup pass for expired wake tokens (`device_tokens.expires_at`):

```bash
npm run cleanup:wake
```

Use cron to run this every 5-15 minutes.

## TLS-only + HSTS (production)

For production behind nginx:

- Set `SECURITY_TLS_ONLY=true`
- Keep `SECURITY_TRUST_PROXY=true`
- Forward `X-Forwarded-Proto https` from nginx
- Optionally set `SECURITY_HSTS_ENABLED=true` once HTTPS is stable

This enforces TLS at the app layer and allows adding HSTS centrally.
