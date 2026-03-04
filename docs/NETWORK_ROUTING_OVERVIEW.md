# Network & Routing Overview — Open-Desk EU

Authoritative reference for all port, routing, and DNS decisions.
Must be updated with every network or routing change.

---

## 1. Traffic Path (Outside → Inside)

```
Browser (LAN/WAN)
  │
  │ HTTPS :443
  ▼
nginx (Host)
  │  TLS termination (self-signed → Let's Encrypt at go-live)
  │  proxy_pass http://<HOST_IP>:8443
  │  Sets X-Forwarded-For, X-Real-IP, Host
  │
  │ HTTP :8443
  ▼
Traefik (Container)
  │  Bound: <HOST_IP>:8443 (temporary, → 127.0.0.1 before production)
  │  Routing via Host()-Rules + Labels
  │  Middlewares: security-headers, rate-limit, default-chain, collabora-chain
  │
  │ HTTP :80/:9980/:8080
  ▼
Target container (Nextcloud, Collabora, Keycloak, ...)
```

**Important:** TLS terminates at nginx. Everything between nginx → Traefik → containers is plain HTTP.

---

## 2. Host Ports

| Port | Protocol | Bound to | Service | Firewall (UFW) |
|------|----------|----------|---------|-----------------|
| 443 | TCP/TLS | 0.0.0.0 | nginx (OpenDesk + production) | ALLOW Anywhere |
| 80 | TCP | LAN subnet | nginx (HTTP→HTTPS redirect) | ALLOW LAN |
| 8443 | TCP | HOST_IP | Traefik ingress | ALLOW LAN (temporary!) |
| 8890 | TCP | 127.0.0.1 | Traefik dashboard/API | No UFW (localhost only) |

⚠️ **Port 8443 must be changed to 127.0.0.1 before production** (see PRE_PRODUCTION_CHECKLIST).

---

## 3. Docker Networks

| Network | Subnet | Internal | Purpose |
|---------|--------|----------|---------|
| opendesk_frontend | 172.31.1.0/24 | No | Traefik ↔ web containers |
| opendesk_backend | 172.31.2.0/24 | No | Keycloak backchannel |
| opendesk_db | 172.31.3.0/24 | **Yes** | Databases (no internet) |
| opendesk_mail | 172.31.4.0/24 | No | Mail relay (reserved) |
| opendesk_wopi | 172.31.5.0/24 | **Yes** | Collabora ↔ Nextcloud WOPI |

---

## 4. Traefik Routing (Host Rules)

| Domain | Router | Target Container | Port | Middleware | Network |
|--------|--------|-----------------|------|------------|---------|
| DOMAIN_CLOUD | nextcloud@docker | Nextcloud | 80 | default-chain, nextcloud-redirects | frontend |
| DOMAIN_IAM | keycloak@docker | Keycloak | 8080 | default-chain | frontend+backend |
| DOMAIN_OFFICE | collabora@docker | Collabora | 9980 | **collabora-chain** | frontend |

**collabora-chain:** Same as default-chain but WITHOUT `frameDeny: true` (Collabora is embedded as an iframe in Nextcloud).

---

## 5. Container Network Assignment

| Container | frontend | backend | db | wopi | Reason |
|-----------|----------|---------|-----|------|--------|
| Traefik | ✅ | ✅ | — | — | Routes to all web containers |
| Keycloak | ✅ | ✅ | — | — | Web + backchannel |
| Keycloak DB | — | — | ✅ | — | Database access only |
| Nextcloud | ✅ | — | ✅ | ✅ | Web + DB + WOPI callbacks |
| Nextcloud DB | — | — | ✅ | — | Database access only |
| Nextcloud Redis | — | — | ✅ | — | Cache, internal only |
| Nextcloud Cron | — | — | ✅ | — | Cron jobs, DB access |
| Collabora | ✅ | — | — | ✅ | Web (editor UI) + WOPI |

---

## 6. DNS Resolution (Container → Domains)

Containers cannot resolve the project domains via normal DNS (domains may not exist in public DNS yet). Three mechanisms:

### 6a. extra_hosts (Docker Compose)

Static `/etc/hosts` entries inside the container. **Critical: target IP depends on the routing path!**

| Container | Domain | Target IP | Why this IP? |
|-----------|--------|-----------|--------------|
| Nextcloud | DOMAIN_IAM | TRAEFIK_FRONTEND_IP | Backchannel via Traefik (same issuer URL as browser) |
| Collabora | DOMAIN_CLOUD | **HOST_IP** (nginx) | WOPI callback must go through nginx→Traefik→Nextcloud because Collabora expects HTTPS and TLS terminates at nginx |

#### Why Not Always Use the Traefik IP?

```
Nextcloud → DOMAIN_IAM
  Traefik IP works because:
  - Nextcloud is on the frontend network (same as Traefik)
  - Traefik listens on :8443 HTTP
  - Nextcloud speaks HTTP for the backchannel

Collabora → DOMAIN_CLOUD
  Traefik IP does NOT work because:
  - Collabora makes an HTTPS request (WOPI requires TLS)
  - Traefik has no TLS certificate (TLS terminates at nginx)
  - Therefore: Collabora → nginx (HOST_IP:443, TLS) → Traefik → Nextcloud
```

### 6b. dnsmasq (Host)

Required for PHP `dns_get_record()` (which ignores `/etc/hosts` and `extra_hosts`):

```
# /etc/dnsmasq.d/opendesk.conf
address=/DOMAIN_IAM/<TRAEFIK_FRONTEND_IP>
```

### 6c. /etc/hosts (Host)

```
# Only for local testing — REMOVE before DNS go-live
<HOST_IP> <DOMAIN_CLOUD>
<HOST_IP> <DOMAIN_IAM>
<HOST_IP> <DOMAIN_OFFICE>
```

---

## 7. WOPI Communication (Collabora ↔ Nextcloud)

```
Browser
  │ wss://DOMAIN_OFFICE/cool/.../ws
  ▼
nginx → Traefik → Collabora (WebSocket)
                      │
                      │ HTTPS callback: DOMAIN_CLOUD
                      │ (CheckFileInfo, GetFile, PutFile)
                      ▼
                    nginx → Traefik → Nextcloud
```

**Configuration in Nextcloud (richdocuments):**

| Setting | Value | Purpose |
|---------|-------|---------|
| wopi_url | http://opendesk_collabora:9980 | Nextcloud → Collabora (internal, Docker DNS) |
| public_wopi_url | https://DOMAIN_OFFICE | Browser → Collabora (external) |

**Configuration in Collabora:**

| Env Variable | Value | Purpose |
|-------------|-------|---------|
| aliasgroup1 | https://DOMAIN_CLOUD:443 | Allowed WOPI client |
| server_name | DOMAIN_OFFICE | Public hostname for discovery URLs |

---

## 8. Decision Matrix: extra_hosts IP Selection

When a container needs to reach a project domain:

```
Does the request require TLS (HTTPS)?
  │
  ├── No  → Traefik IP (TRAEFIK_FRONTEND_IP on frontend network)
  │          Container must be on the frontend network
  │
  └── Yes → Host IP (HOST_IP)
             Request goes via nginx (TLS termination) → Traefik → target
             Container does NOT need to be on the frontend network (uses Docker bridge)
```

---

## 9. Known Static IPs

| Resource | IP | Network | Note |
|----------|----|---------|------|
| Traefik | TRAEFIK_FRONTEND_IP | frontend | Assigned by Docker, may change on recreate! |
| Host/nginx | HOST_IP | LAN | Statically configured |

⚠️ **Docker assigns IPs dynamically.** The Traefik IP is not guaranteed. After a recreate, verify:
```bash
docker inspect <traefik_container> --format '{{range .NetworkSettings.Networks}}{{.NetworkID}} {{.IPAddress}}{{"\n"}}{{end}}'
```

---

*Last updated: 2026-03-04*
*Change reason: Collabora deployment — extra_hosts, server_name, collabora-chain middleware*
