# Deployment Runbook (server/, Sparse Checkout, TLS Hardening)

Ziel: Nur `server/` aus dem Monorepo deployen und den Betrieb fuer Produktion haerten.

## 1) Initiales Checkout auf dem Host (empfohlen)

```bash
mkdir -p ~/deploy/prsm
cd ~/deploy/prsm
git clone --filter=blob:none --sparse --depth=1 <repo-url> .
git sparse-checkout set server
cd server
```

Fallback fuer aelteres Git:

```bash
mkdir -p ~/deploy/prsm
cd ~/deploy/prsm
git init
git remote add origin <repo-url>
git config core.sparseCheckout true
echo "server/" > .git/info/sparse-checkout
git pull origin main
cd server
```

## 2) Runtime vorbereiten

```bash
cp /path/to/secure/.env ./.env
npm install --omit=dev
sqlite3 ./data.sqlite < schema_sqlite.sql
npm run migrate
```

Empfohlene `.env` Mindestwerte fuer Produktion:

```env
NODE_ENV=production
SECURITY_TLS_ONLY=true
SECURITY_TRUST_PROXY=true
SECURITY_HSTS_ENABLED=true
SECURITY_HSTS_MAX_AGE_SEC=15552000
SECURITY_HSTS_INCLUDE_SUBDOMAINS=false
SECURITY_HSTS_PRELOAD=false
```

Hinweis: `SECURITY_HSTS_ENABLED` erst aktivieren, wenn HTTPS stabil und vollstaendig erzwungen ist.

## 3) Start/Restart

Minimal ohne Process Manager:

```bash
nohup node src/server.js > ./server.log 2>&1 &
echo $! > ./server.pid
```

Restart:

```bash
kill "$(cat ./server.pid)" || true
nohup node src/server.js > ./server.log 2>&1 &
echo $! > ./server.pid
```

## 4) Cleanup-Cron (Retention Enforcement)

Relay Cleanup alle 10 Minuten:

```cron
*/10 * * * * cd /home/<user>/deploy/prsm/server && npm run cleanup:relay >> ./cleanup.log 2>&1
```

## 5) Nginx Reverse Proxy (TLS-only + Forwarded Proto)

Wichtig:
- HTTP (Port 80) immer auf HTTPS redirecten.
- Bei Proxy auf Node immer `X-Forwarded-Proto https` setzen.

Beispielauszug:

```nginx
server {
  listen 80;
  server_name api.example.tld;
  return 301 https://$host$request_uri;
}

server {
  listen 443 ssl http2;
  server_name api.example.tld;

  add_header Strict-Transport-Security "max-age=15552000" always;

  location / {
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_pass http://127.0.0.1:3000;
  }
}
```

## 6) Update-Prozess

Im Deploy-Verzeichnis:

```bash
cd ~/deploy/prsm
git pull
cd server
npm install --omit=dev
npm run migrate
kill "$(cat ./server.pid)" || true
nohup node src/server.js > ./server.log 2>&1 &
echo $! > ./server.pid
```

## 7) Smoke Checks

```bash
curl -sS -X POST https://api.example.tld/v1/health
```

Erwartet:
- `200` und `{ "ok": true, "status": "ok" }`
- HSTS Header vorhanden (wenn aktiviert)
- Plain HTTP Request wird umgeleitet oder mit `426 tls_required` abgewiesen

## 8) Optional: Deploy-Branch nur fuer server/

Lokal:

```bash
git subtree split --prefix server -b server-deploy
git push <server-remote> server-deploy:main
```

Server:

```bash
git clone <server-remote> .
```

## 9) Zugangskontrolle (Deploy + DB)

Mindestregeln fuer Produktion:
- Eigener Deploy-User ohne `sudo`; Login nur per SSH-Key, Passwortlogin deaktivieren.
- Schreibrechte auf `~/deploy/prsm/server` nur fuer Deploy-User; keine geteilten Accounts.
- `.env` nur lokal auf dem Host, nie im Git; Dateirechte auf `600`.
- SQLite-Datei (`data.sqlite`) nur fuer Deploy-User les-/schreibbar; Dateirechte auf `600`.
- Rotierbare Secrets (`HMAC_SECRET`, APNs Key) nur ueber gesicherten Admin-Kanal austauschen und Wechsel im Incident-/Change-Ticket dokumentieren.
- DB-Zugriffe fuer Betrieb/Support nur need-to-know und ticketgebunden.

Beispielrechte (SQLite Deploy):

```bash
chmod 700 /home/<user>/deploy/prsm
chmod 700 /home/<user>/deploy/prsm/server
chmod 600 /home/<user>/deploy/prsm/server/.env
chmod 600 /home/<user>/deploy/prsm/server/data.sqlite
```
