# Silent Wake Relay (Server)

Minimal API skeleton for the silent wake relay, matching Phase 1 of `docs/server-roadmap.md`.

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
- `MAX_BODY_BYTES` (default: 8192)
- `HMAC_SECRET` (required for `/v1/wake`)
- `HMAC_MAX_SKEW_SEC` (default: 300)
- `RATE_LIMIT_WINDOW_SEC` (default: 3600)
- `RATE_LIMIT_TOKEN_PER_WINDOW` (default: 30)
- `RATE_LIMIT_IP_PER_WINDOW` (default: 120)
- `DB_DRIVER` (`memory` or `sqlite`, `mysql` optional)
- `DB_FILENAME` (SQLite filename)
- `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME` (MySQL optional)

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

## Rate limiting

Rate limits apply per token and per IP, per window. The counters are stored in
`rate_limits` with a window start timestamp.
