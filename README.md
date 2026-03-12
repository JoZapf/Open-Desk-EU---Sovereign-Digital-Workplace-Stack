# Open-Desk EU — Sovereign Digital Workplace Stack

Containerized, self-hosted digital workplace suite designed for EU data sovereignty. Deployed with Docker Compose behind Traefik reverse proxy, following Zero Trust principles with Defense-in-Depth security hardening.

<p align="center">
  <img src="Open-Desk-EU-Defense-in-Depth-Architecture_work_in_process.svg" width="1100" alt="Open-Desk-EU-Defense-in-Depth-Architecture_work_in_process.svg">
</p>

## Architecture

```
Internet → nginx (TLS termination) → Traefik (routing) → Service containers
                                                           ├── Nextcloud 31 (file sync & collaboration)
                                                           │   ├── notify_push (WebSocket push)
                                                           │   └── Whiteboard (real-time drawing)
                                                           ├── Keycloak 26.5 (SSO / OIDC identity provider)
                                                           ├── Collabora Online (document editing via WOPI)
                                                           ├── Vaultwarden (password management)
                                                           ├── Overleaf CE (LaTeX editor)
                                                           │   ├── MongoDB 8.0 (document store)
                                                           │   └── Redis 7 (session cache)
                                                           ├── Prometheus + Grafana (metrics & dashboards)
                                                           ├── Netdata (real-time system monitoring)
                                                           ├── Wiki (Material for MkDocs)
                                                           ├── Rocket.Chat (messaging) [planned]
                                                           └── Jitsi Meet (video conferencing) [planned]
```

## Security

Full security architecture and audit results are documented in [`SECURITY.md`](SECURITY.md).

Key principles:

- **Network Segmentation** — 6 isolated Docker networks; database, WOPI, and LaTeX-DB networks are fully internal (no internet access)
- **Least Privilege** — `cap_drop: ALL` on every container, minimal `cap_add` per service; `no-new-privileges` per container (documented exceptions for Collabora, Netdata, and Overleaf)
- **Secrets as Files** — Docker Compose `secrets:` block, no plaintext credentials in compose files
- **Immutable Infrastructure** — Read-only filesystems where possible, explicit tmpfs for runtime data
- **Centralized IAM** — Keycloak OIDC with Authorization Code Flow + PKCE for all services
- **Host Intrusion Prevention** — CrowdSec with geoblocking and community threat intelligence
- **Repository Hygiene** — All secrets, credentials, and infrastructure-identifying data (domains, IPs, usernames, zone IDs) are excluded from version control via `.gitignore`

## Repository Structure

```
compose/
├── traefik/          Reverse proxy + TLS termination + middleware definitions
├── keycloak/         Identity provider (production build) + PostgreSQL
├── nextcloud/        File sync + MariaDB + Redis + Cron + notify_push
├── collabora/        Document editing (CODE) + seccomp profile
├── latex/            LaTeX editor (Overleaf CE) + MongoDB + Redis
├── vaultwarden/      Password manager
├── whiteboard/       Real-time collaborative whiteboard (WebSocket)
├── observability/    Prometheus + Grafana + Netdata
└── mkdocs/           Wiki (Material for MkDocs, oauth2-proxy + nginx)
wiki/                 MkDocs source files (Markdown + mkdocs.yml)
secrets/              Credential files (git-ignored, chmod 700)
scripts/              Verification, backup, deployment, DDNS scripts
docker-compose.yml    Root orchestrator (network definitions)
.env.example          Template for deployment-specific configuration
```

> **Note:** Directories containing deployment-specific values (secrets, environment files, compose files with hardcoded domains, scripts with zone IDs, documentation with infrastructure details) are excluded from this repository via `.gitignore`. See [Configuration](#configuration) for setup instructions.

## Project Status

| Component | Status |
|---|---|
| Host Security (firewall, auditd, CrowdSec) | Complete |
| Docker Network Segmentation | 6 networks, DB + WOPI + LaTeX-DB internal |
| Traefik Reverse Proxy | Security headers, rate limiting, HSTS |
| Keycloak 26.5 IAM | Production build, OIDC clients, 2FA (TOTP + WebAuthn) |
| Nextcloud 31 | OIDC SSO, performance-tuned (OPcache/JIT, APCu, InnoDB) |
| Nextcloud High Performance Backend | notify_push (WebSocket push notifications) |
| Collabora Online | WOPI integration, document editing, seccomp-sandboxed |
| Whiteboard | Real-time collaborative drawing via WebSocket |
| Vaultwarden | Password management, Keycloak SSO |
| Overleaf CE (LaTeX) | Browser-based LaTeX editor, MongoDB replica set |
| Observability (Prometheus + Grafana + Netdata) | Metrics collection + dashboards |
| Wiki (Material for MkDocs) | Static site, Keycloak-protected via oauth2-proxy |
| TLS (Let's Encrypt) | Planned for DNS go-live |
| Rocket.Chat | Planned |
| Jitsi Meet | Planned |

## Technology Stack

- **Containerization:** Docker + Docker Compose (~18 containers across 8 compose projects)
- **Reverse Proxy:** Traefik v3 with automatic service discovery
- **Identity Management:** Keycloak 26.5 (OIDC / OAuth 2.0, production build)
- **File Sync:** Nextcloud 31 with Redis caching + notify_push
- **Document Editing:** Collabora Online (CODE) via WOPI protocol
- **LaTeX:** Overleaf Community Edition (browser-based LaTeX IDE) + MongoDB 8.0 + Redis 7
- **Password Management:** Vaultwarden (Bitwarden-compatible)
- **Real-time Collaboration:** Whiteboard (Excalidraw-based, WebSocket)
- **Databases:** PostgreSQL 16 (Keycloak), MariaDB 11 (Nextcloud), MongoDB 8.0 (Overleaf)
- **Caching:** Redis 7 (session + file locking), APCu (local PHP object cache)
- **Monitoring:** Prometheus + Grafana (metrics), Netdata (real-time), auditd (host audit)
- **Wiki:** Material for MkDocs (static site generator) + oauth2-proxy (OIDC authentication)
- **Host Security:** CrowdSec (IPS with geoblocking), UFW (firewall)
- **Backup:** BorgBackup (segmented pipeline with pre/post hooks, encrypted, deduplicated)
- **Host OS:** Ubuntu Server

## Configuration

All deployment-specific values are centralized in a single `.env` file. Compose files reference these variables via `${VAR}` interpolation — no hardcoded domains, IPs, or paths in any compose file.

```bash
cp .env.example .env
# Edit .env with your deployment values
```

| Variable | Purpose | Example |
|---|---|---|
| `DOMAIN_CLOUD` | Nextcloud domain | `cloud.example.com` |
| `DOMAIN_IAM` | Keycloak domain | `id.example.com` |
| `DOMAIN_OFFICE` | Collabora domain | `office.example.com` |
| `DOMAIN_DOCS` | Wiki domain | `docs.example.com` |
| `DOMAIN_LATEX` | Overleaf domain | `latex.example.com` |
| `HOST_IP` | Server LAN IP (for port bindings and WOPI routing) | `192.168.1.100` |
| `LAN_SUBNET` | Local network CIDR | `192.168.1.0/24` |
| `DATA_DIR` | Base path for persistent volumes | `/srv/opendesk-data` |

See [`.env.example`](.env.example) for the complete template with all variables and defaults.

## Quick Start

```bash
# 1. Clone and configure
cp .env.example .env
# Edit .env — at minimum set DOMAIN_*, HOST_IP, and DATA_DIR

# 2. Create secrets
mkdir -p secrets && chmod 700 secrets
# Generate credentials — see .env.example for the full list

# 3. Create data directories
sudo mkdir -p /srv/opendesk-data/{keycloak/db,mariadb,nextcloud,prometheus,grafana,latex/{data,mongo,redis}}
sudo chmod 700 /srv/opendesk-data

# 4. Create Docker networks (see SECURITY.md for subnet details)
# 6 networks: frontend, backend, db, mail, wopi, latex_db
# Mark db, wopi, and latex_db as internal (no internet access)

# 5. Deploy services (order matters)
docker compose --env-file .env -f compose/traefik/docker-compose.yml up -d
docker compose --env-file .env -f compose/keycloak/docker-compose.yml up -d
docker compose --env-file .env -f compose/nextcloud/docker-compose.yml up -d
docker compose --env-file .env -f compose/collabora/docker-compose.yml up -d
docker compose --env-file .env -f compose/vaultwarden/docker-compose.yml up -d
docker compose --env-file .env -f compose/latex/docker-compose.yml up -d
docker compose --env-file .env -f compose/whiteboard/docker-compose.yml up -d
docker compose --env-file .env -f compose/observability/docker-compose.yml up -d
docker compose --env-file .env -f compose/mkdocs/docker-compose.yml up -d
```

## What's Not in This Repo

This is a public repository. The following categories are excluded via `.gitignore` to protect infrastructure identity:

| Category | Examples | Why excluded |
|---|---|---|
| Secrets | Passwords, tokens, API keys | Security |
| Environment | `.env` with domains, IPs, credentials | Infrastructure identity |
| Sensitive compose files | Files with hardcoded SMTP addresses, redirect URLs | Infrastructure identity |
| Scripts with infrastructure values | DDNS zone IDs, domain-specific logic | Infrastructure identity |
| Documentation with infrastructure details | Runbooks, wiki docs, architecture docs with concrete IPs/domains | Infrastructure identity |

The architecture, patterns, and generic configuration remain public. Only values that make this specific installation identifiable or mappable are excluded.

## License

This repository contains infrastructure configuration for a personal project. No license is granted for commercial use.
