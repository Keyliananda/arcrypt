# Relay Ops Hardening (Post-Fix)

Ziel: verbleibende Betriebsrisiken nach TLS/Proxy-Fix entschärfen.

## 1) Nginx direkt auf Node (PHP-Abhängigkeit entfernen)

1. VHost-Datei deployen:
   - Vorlage: `server/deploy/nginx/arcrypt.pisspeter.de.conf`
2. Aktivieren und testen:
   - `sudo nginx -t`
   - `sudo systemctl reload nginx`
3. Smoke-Test:
   - `curl -i -X POST https://arcrypt.pisspeter.de/v1/health`
4. Erwartung:
   - Kein `403` aus php/.htaccess.
   - API-Antwort vom Relay (normalerweise `200`).

## 2) Node als systemd-Service (502-Risiko minimieren)

1. Unit deployen:
   - Vorlage: `server/deploy/systemd/prsm-relay.service`
2. Platzhalter ersetzen:
   - `<DEPLOY_USER>`
3. Aktivieren:
   - `sudo systemctl daemon-reload`
   - `sudo systemctl enable --now prsm-relay`
4. Verifikation:
   - `systemctl status prsm-relay --no-pager`
   - `journalctl -u prsm-relay -n 100 --no-pager`
   - `curl -i -X POST http://127.0.0.1:3000/v1/health`

## 3) Externes Monitoring und Alarm

Minimale Variante per Cron (jede Minute):

```cron
* * * * * curl -fsS -m 8 -X POST https://arcrypt.pisspeter.de/v1/health >/dev/null || logger -t prsm-relay "healthcheck failed"
```

Empfohlen:
- Uptime/Alerting (z. B. Uptime Kuma, Hetrix, Better Stack) mit Alarm an Mail/Signal.
- Trigger bei `!=200` oder Timeout > 8s.

## 4) Legacy-Pfad entfernen

Wenn der alte Pfad nicht mehr benötigt wird:

1. Backup:
   - `cp -a /home/w18416/web/public_html/relay /home/w18416/web/public_html/relay.bak.$(date +%F-%H%M%S)`
2. Entfernen:
   - `rm -rf /home/w18416/web/public_html/relay`
3. Optional hart blocken (zusätzliche Absicherung im Webserver):
   - `location ^~ /relay { return 410; }`

## 5) Abschluss-Checks

1. `curl -i -X POST https://arcrypt.pisspeter.de/v1/health`
2. `curl -i -X POST https://arcrypt.pisspeter.de/v1/mailbox/pull -d '{}' -H 'content-type: application/json'`
3. Erwartung:
   - Kein `403`/`.htaccess` Fehler.
   - API-spezifischer Fehler oder Erfolgscode vom Relay.
