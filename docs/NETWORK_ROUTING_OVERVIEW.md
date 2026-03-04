# Network & Routing Overview — Open-Desk EU

Verbindliche Referenz für alle Port-, Routing- und DNS-Entscheidungen.
Muss bei jeder Netzwerk- oder Routing-Änderung aktualisiert werden.

---

## 1. Traffic-Pfad (Außen → Innen)

```
Browser (LAN/WAN)
  │
  │ HTTPS :443
  ▼
nginx (Host: 192.168.10.20)
  │  /etc/nginx/sites-available/opendesk
  │  TLS-Terminierung (Self-Signed → Let's Encrypt bei Go-Live)
  │  proxy_pass http://192.168.10.20:8443
  │  Setzt X-Forwarded-For, X-Real-IP, Host
  │
  │ HTTP :8443
  ▼
Traefik (Container: opendesk_traefik)
  │  Bound: 192.168.10.20:8443 (temporär, → 127.0.0.1 vor Production)
  │  Routing via Host()-Rules + Labels
  │  Middlewares: security-headers, rate-limit, default-chain, collabora-chain
  │
  │ HTTP :80/:9980/:8080
  ▼
Ziel-Container (Nextcloud, Collabora, Keycloak, ...)
```

**Wichtig:** TLS endet bei nginx. Zwischen nginx → Traefik → Container ist alles HTTP.

---

## 2. Host-Ports

| Port | Protokoll | Gebunden an | Dienst | Firewall (UFW) |
|------|-----------|-------------|--------|-----------------|
| 443 | TCP/TLS | 0.0.0.0 | nginx (openDesk + Produktiv) | ALLOW Anywhere |
| 80 | TCP | 192.168.10.0/24 | nginx (HTTP→HTTPS Redirect) | ALLOW LAN |
| 8443 | TCP | 192.168.10.20 | Traefik Ingress | ALLOW LAN (temporär!) |
| 8890 | TCP | 127.0.0.1 | Traefik Dashboard/API | Kein UFW (nur lokal) |
| 8085 | TCP | 0.0.0.0 | Produktiv-Nextcloud (alt) | ALLOW LAN |
| 3307 | — | — | ~~nextcloud-db-dev~~ (entfernt) | — |

⚠️ **Port 8443 muss vor Production zurück auf 127.0.0.1** (siehe PRE_PRODUCTION_CHECKLIST).

---

## 3. Docker-Netzwerke

| Netzwerk | Subnet | Internal | Zweck |
|----------|--------|----------|-------|
| opendesk_frontend | 172.31.1.0/24 | Nein | Traefik ↔ Web-Container |
| opendesk_backend | 172.31.2.0/24 | Nein | Keycloak-Backchannel |
| opendesk_db | 172.31.3.0/24 | **Ja** | Datenbanken (kein Internet) |
| opendesk_mail | 172.31.4.0/24 | Nein | Mail-Relay (reserviert) |
| opendesk_wopi | 172.31.5.0/24 | **Ja** | Collabora ↔ Nextcloud WOPI |

---

## 4. Traefik-Routing (Host-Rules)

| Domain | Router | Ziel-Container | Port | Middleware | Netzwerk |
|--------|--------|----------------|------|------------|----------|
| cloud.sine-math.com | nextcloud@docker | opendesk_nextcloud | 80 | default-chain, nextcloud-redirects | frontend |
| id.sine-math.com | keycloak@docker | opendesk_keycloak | 8080 | default-chain | frontend+backend |
| office.sine-math.com | collabora@docker | opendesk_collabora | 9980 | **collabora-chain** | frontend |

**collabora-chain:** Wie default-chain, aber OHNE `frameDeny: true` (Collabora wird als iframe in Nextcloud eingebettet).

---

## 5. Container-Netzwerk-Zuordnung

| Container | frontend | backend | db | wopi | Begründung |
|-----------|----------|---------|-----|------|-----------|
| opendesk_traefik | ✅ | ✅ | — | — | Routing zu allen Web-Containern |
| opendesk_keycloak | ✅ | ✅ | — | — | Web + Backchannel |
| opendesk_keycloak_db | — | — | ✅ | — | Nur DB-Zugriff |
| opendesk_nextcloud | ✅ | — | ✅ | ✅ | Web + DB + WOPI-Callbacks |
| opendesk_nextcloud_db | — | — | ✅ | — | Nur DB-Zugriff |
| opendesk_nextcloud_redis | — | — | ✅ | — | Cache, nur intern |
| opendesk_nextcloud_cron | — | — | ✅ | — | Cron-Jobs, DB-Zugriff |
| opendesk_collabora | ✅ | — | — | ✅ | Web (Editor-UI) + WOPI |

---

## 6. DNS-Auflösung (Container → Domänen)

Container können `*.sine-math.com` nicht über normales DNS auflösen (Domänen existieren nur lokal). Drei Mechanismen:

### 6a. extra_hosts (Docker Compose)

Statische `/etc/hosts`-Einträge im Container. **Entscheidend: Ziel-IP hängt vom Routing-Pfad ab!**

| Container | Domain | Ziel-IP | Warum diese IP? |
|-----------|--------|---------|-----------------|
| opendesk_nextcloud | id.sine-math.com | 172.31.1.3 (Traefik) | Backchannel über Traefik (gleiche Issuer-URL wie Browser) |
| opendesk_collabora | cloud.sine-math.com | **192.168.10.20** (Host/nginx) | WOPI-Callback muss über nginx→Traefik→Nextcloud laufen, weil Collabora HTTPS erwartet und TLS bei nginx terminiert |

#### Warum nicht immer Traefik-IP?

```
Nextcloud → id.sine-math.com
  Traefik-IP (172.31.1.3) funktioniert, weil:
  - Nextcloud ist im frontend-Netzwerk (gleich wie Traefik)
  - Traefik lauscht auf :8443 HTTP
  - Nextcloud spricht HTTP zum Backchannel

Collabora → cloud.sine-math.com
  Traefik-IP funktioniert NICHT, weil:
  - Collabora macht HTTPS-Request (WOPI erfordert TLS)
  - Traefik hat kein TLS-Zertifikat (TLS terminiert bei nginx)
  - Also: Collabora → nginx (192.168.10.20:443, TLS) → Traefik → Nextcloud
```

### 6b. dnsmasq (Host)

Für PHP `dns_get_record()` (ignoriert `/etc/hosts` und `extra_hosts`):

```
# /etc/dnsmasq.d/opendesk.conf
address=/id.sine-math.com/172.31.1.3
```

### 6c. /etc/hosts (Host)

```
# Nur für lokale Tests — ENTFERNEN vor DNS-Go-Live
192.168.10.20 cloud.sine-math.com
192.168.10.20 id.sine-math.com
192.168.10.20 office.sine-math.com
```

---

## 7. WOPI-Kommunikation (Collabora ↔ Nextcloud)

```
Browser
  │ wss://office.sine-math.com/cool/.../ws
  ▼
nginx → Traefik → Collabora (WebSocket)
                      │
                      │ HTTPS callback: cloud.sine-math.com
                      │ (CheckFileInfo, GetFile, PutFile)
                      ▼
                    nginx → Traefik → Nextcloud
```

**Konfiguration in Nextcloud (richdocuments):**

| Setting | Wert | Zweck |
|---------|------|-------|
| wopi_url | http://opendesk_collabora:9980 | Nextcloud → Collabora (intern, Docker-DNS) |
| public_wopi_url | https://office.sine-math.com | Browser → Collabora (extern) |

**Konfiguration in Collabora:**

| Env-Variable | Wert | Zweck |
|--------------|------|-------|
| aliasgroup1 | https://cloud.sine-math.com:443 | Erlaubter WOPI-Client |
| server_name | office.sine-math.com | Öffentlicher Hostname für Discovery-URLs |

---

## 8. Entscheidungsmatrix: extra_hosts IP-Wahl

Wenn ein Container eine `*.sine-math.com`-Domain erreichen muss:

```
Braucht der Request TLS (HTTPS)?
  │
  ├── Nein → Traefik-IP (172.31.1.3 im frontend-Netz)
  │          Container muss im frontend-Netzwerk sein
  │
  └── Ja  → Host-IP (192.168.10.20)
             Request geht über nginx (TLS-Terminierung) → Traefik → Ziel
             Container muss NICHT im frontend-Netz sein (geht über Docker-Bridge)
```

---

## 9. Bekannte Statische IPs

| Ressource | IP | Netzwerk | Hinweis |
|-----------|----|----------|---------|
| Traefik | 172.31.1.3 | frontend | Vergeben durch Docker, kann sich bei Recreate ändern! |
| Traefik | 172.31.2.2 | backend | Vergeben durch Docker |
| Host/nginx | 192.168.10.20 | LAN | Statisch konfiguriert |

⚠️ **Docker vergibt IPs dynamisch.** Die Traefik-IP 172.31.1.3 ist nicht garantiert. Bei Problemen nach Recreate prüfen:
```bash
docker inspect opendesk_traefik --format '{{range .NetworkSettings.Networks}}{{.NetworkID}} {{.IPAddress}}{{"\n"}}{{end}}'
```

---

*Letzte Aktualisierung: 2026-03-04*
*Änderungsgrund: Collabora-Deployment — extra_hosts, server_name, collabora-chain Middleware*
