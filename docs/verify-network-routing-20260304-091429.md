# Network & Routing Verification — 2026-03-04 09:14:29

PASS: 59 | FAIL: 4 | WARN: 2


## 1. Host-Ports
- ✅ PASS: Port 443 (nginx TLS) — lauscht
- ✅ PASS: Port 80 (nginx HTTP→HTTPS) — lauscht
- ✅ PASS: Port 8443 (Traefik) — lauscht auf 192.168.10.20:8443
- ⚠️  WARN: Port 8443 — auf LAN-IP gebunden (temporär OK, vor Production ändern!)
- ✅ PASS: Port 8890 (Dashboard) — nur lokal gebunden
- ✅ PASS: Port 3307 (nextcloud-db-dev) — korrekt geschlossen

## 2. Docker-Netzwerke
- ✅ PASS: opendesk_db — Subnet 172.31.3.0/24
- ✅ PASS: opendesk_db — Internal=true
- ✅ PASS: opendesk_backend — Subnet 172.31.2.0/24
- ✅ PASS: opendesk_backend — Internal=false
- ✅ PASS: opendesk_wopi — Subnet 172.31.5.0/24
- ✅ PASS: opendesk_wopi — Internal=true
- ✅ PASS: opendesk_frontend — Subnet 172.31.1.0/24
- ✅ PASS: opendesk_frontend — Internal=false
- ✅ PASS: opendesk_mail — Subnet 172.31.4.0/24
- ✅ PASS: opendesk_mail — Internal=false

## 3. Container-Status
- ✅ PASS: opendesk_traefik — running (healthy)
- ✅ PASS: opendesk_keycloak — running (healthy)
- ✅ PASS: opendesk_keycloak_db — running (healthy)
- ✅ PASS: opendesk_nextcloud — running (healthy)
- ✅ PASS: opendesk_nextcloud_db — running (healthy)
- ✅ PASS: opendesk_nextcloud_redis — running (healthy)
- ✅ PASS: opendesk_nextcloud_cron — running (no-healthcheck)
- ✅ PASS: opendesk_collabora — running (healthy)

## 4. Container-Netzwerk-Zuordnung
- ✅ PASS: opendesk_traefik — korrekt in: opendesk_frontend, opendesk_backend
- ✅ PASS: opendesk_keycloak — korrekt in: opendesk_frontend, opendesk_backend
- ✅ PASS: opendesk_keycloak_db — korrekt in: opendesk_db
- ✅ PASS: opendesk_nextcloud — korrekt in: opendesk_frontend, opendesk_db, opendesk_wopi
- ✅ PASS: opendesk_nextcloud_db — korrekt in: opendesk_db
- ✅ PASS: opendesk_nextcloud_redis — korrekt in: opendesk_db
- ✅ PASS: opendesk_nextcloud_cron — korrekt in: opendesk_db
- ✅ PASS: opendesk_collabora — korrekt in: opendesk_frontend, opendesk_wopi

## 5. Traefik-Routing (Host-Rules)
- ✅ PASS: Traefik API erreichbar
- ✅ PASS: Router nextcloud — Host(cloud.sine-math.com) registriert
- ✅ PASS: Router keycloak — Host(id.sine-math.com) registriert
- ✅ PASS: Router collabora — Host(office.sine-math.com) registriert
- ✅ PASS: Middleware default-chain@file — registriert
- ✅ PASS: Middleware collabora-chain@file — registriert
- ✅ PASS: Middleware security-headers@file — registriert
- ✅ PASS: Middleware rate-limit@file — registriert

## 6. HTTP-Routing End-to-End
- ✅ PASS: Nextcloud via Traefik — HTTP 200
- ✅ PASS: Keycloak via Traefik — HTTP 200
- ✅ PASS: Collabora via Traefik — HTTP 200
- ✅ PASS: Nextcloud via nginx+TLS — HTTPS 200
- ❌ FAIL: Keycloak via nginx+TLS — HTTPS 000000 (erwartet 302)
- ❌ FAIL: Collabora via nginx+TLS — HTTPS 000000 (erwartet 200)

## 7. Security Headers
- ✅ PASS: Nextcloud — Header X-Content-Type-Options vorhanden
- ❌ FAIL: Nextcloud — Header Strict-Transport-Security FEHLT
- ✅ PASS: Nextcloud — Header X-Robots-Tag vorhanden
- ✅ PASS: Collabora — kein X-Frame-Options: DENY (iframe erlaubt)
- ✅ PASS: Nextcloud CSP — office.sine-math.com in frame-src

## 8. Container-DNS (extra_hosts)
- ✅ PASS: Nextcloud → id.sine-math.com = 172.31.1.3 (Traefik)
- ⚠️  WARN: Collabora → cloud.sine-math.com = 2606:4700:3031::ac43:8e09
2606:4700:3032::6815:4956 (erwartet 192.168.10.20)

## 9. Backchannel-Konnektivität
- ✅ PASS: Nextcloud → Keycloak Backchannel — HTTP 200
- ✅ PASS: Collabora → Nextcloud WOPI-Callback — HTTPS 200
- ✅ PASS: Nextcloud → Collabora Discovery (intern) — HTTP 200

## 10. WOPI-Konfiguration
- ✅ PASS: wopi_url = http://opendesk_collabora:9980
- ✅ PASS: public_wopi_url = https://office.sine-math.com
- ✅ PASS: Collabora Discovery — URLs zeigen auf office.sine-math.com
- ✅ PASS: Collabora aliasgroup1 = https://cloud.sine-math.com:443
- ✅ PASS: Collabora server_name = office.sine-math.com

## 11. Nextcloud-Konfiguration
- ✅ PASS: overwriteprotocol = https
- ✅ PASS: overwritehost = cloud.sine-math.com
- ❌ FAIL: Nextcloud → Redis — Verbindung fehlgeschlagen (
Warning: file_get_contents(/run/secrets/redis_nextcloud_password): Failed to open stream: Permission denied in Command line code on line 4

Fatal error: Uncaught RedisException: WRONGPASS invalid username-password pair or user is disabled. in Command line code:5
Stack trace:
#0 Command line code(5): Redis->auth(Object(SensitiveParameterValue))
#1 {main}
  thrown in Command line code on line 5
FAIL)

## 12. Traefik IP-Prüfung
- ✅ PASS: Traefik Frontend-IP = 172.31.1.3 (wie in extra_hosts referenziert)

