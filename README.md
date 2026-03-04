# Open-Desk EU — Sovereign Digital Workplace Stack

Containerized, self-hosted digital workplace suite designed for EU data sovereignty. Deployed with Docker Compose behind Traefik reverse proxy, following Zero Trust principles with Defense-in-Depth security hardening.

## Architecture

```
Internet → nginx (TLS termination) → Traefik (routing) → Service containers
                                                           ├── Nextcloud 30 (file sync & collaboration)
                                                           ├── Keycloak 26.1 (SSO / OIDC identity provider)
                                                           ├── Collabora Online (document editing)
                                                           ├── Rocket.Chat (messaging) [planned]
                                                           ├── Jitsi Meet (video conferencing) [planned]
                                                           ├── OpenProject (project management) [planned]
                                                           └── Vaultwarden (password management) [planned]
```

## Security

All services follow the container hardening baseline documented in [`docs/CONTAINER_HARDENING_BASELINE.md`](docs/CONTAINER_HARDENING_BASELINE.md). Full security architecture and audit results are documented in [`SECURITY.md`](SECURITY.md).

Key principles:

- **Network Segmentation** — 5 isolated Docker networks; database and WOPI networks are fully internal (no internet access)
- **Least Privilege** — `cap_drop: ALL` on every container, minimal `cap_add` per service; `no-new-privileges` per container (documented exception for Collabora, see [`docs/NO_NEW_PRIVILEGES_PARADIGM.md`](docs/NO_NEW_PRIVILEGES_PARADIGM.md))
- **Secrets as Files** — Docker Compose `secrets:` block, no plaintext credentials in compose files or environment variables
- **Immutable Infrastructure** — Read-only filesystems where possible, explicit tmpfs for runtime data
- **Centralized IAM** — Keycloak OIDC with Authorization Code Flow + PKCE for all services
- **Automated Verification** — [`scripts/verify-network-routing.sh`](scripts/verify-network-routing.sh) runs 66 checks across 12 areas (ports, networks, routing, headers, WOPI, DNS)

## Repository Structure

```
compose/
├── traefik/          Reverse proxy + middleware definitions
├── keycloak/         Identity provider + PostgreSQL
├── nextcloud/        File sync + MariaDB + Redis + Cron
└── collabora/        Document editing (CODE) + seccomp profile
config/               Service configurations
docs/                 Architecture decisions, hardening baseline, network routing reference
secrets/              Credential files (git-ignored, chmod 700)
scripts/              Verification, backup, deployment scripts
docker-compose.yml    Root orchestrator (network definitions)
```

## Project Status

| Component | Status |
|---|---|
| Host Security Baseline | ✅ Complete |
| Docker Network Segmentation | ✅ 5 networks, DB + WOPI internal |
| Traefik v3.6 Reverse Proxy | ✅ Security headers + rate limiting |
| Keycloak 26.1 IAM | ✅ Realm + OIDC clients configured |
| Nextcloud 30 | ✅ Deployed with OIDC SSO verified end-to-end |
| Collabora Online | ✅ WOPI integration verified, document editing working |
| TLS (Let's Encrypt) | ⏳ Planned for DNS go-live |
| Rocket.Chat | ⏳ Planned |
| Jitsi Meet | ⏳ Planned |
| OpenProject | ⏳ Planned |
| Vaultwarden | ⏳ Planned |

## Technology Stack

- **Containerization:** Docker + Docker Compose
- **Reverse Proxy:** Traefik v3.6 with automatic service discovery
- **Identity Management:** Keycloak 26.1 (OIDC / OAuth 2.0)
- **File Sync:** Nextcloud 30 with Redis caching
- **Document Editing:** Collabora Online (CODE) 25.04 via WOPI protocol
- **Databases:** PostgreSQL 16, MariaDB 11
- **Host OS:** Ubuntu Server
- **Monitoring:** auditd (Docker socket + daemon config)

## Key Documentation

| Document | Purpose |
|---|---|
| [`docs/NETWORK_ROUTING_OVERVIEW.md`](docs/NETWORK_ROUTING_OVERVIEW.md) | Authoritative reference for all port, routing, and DNS decisions |
| [`docs/CONTAINER_HARDENING_BASELINE.md`](docs/CONTAINER_HARDENING_BASELINE.md) | Mandatory security directives for every container |
| [`docs/NO_NEW_PRIVILEGES_PARADIGM.md`](docs/NO_NEW_PRIVILEGES_PARADIGM.md) | Per-container no-new-privileges strategy and Collabora exception |
| [`SECURITY.md`](SECURITY.md) | Full security architecture and audit results |
| [`scripts/verify-network-routing.sh`](scripts/verify-network-routing.sh) | Automated 66-check verification across 12 areas |
| [`.env.example`](.env.example) | Template for deployment-specific configuration (domains, IPs, ports) |

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
| `HOST_IP` | Server LAN IP (used for port bindings and WOPI routing) | `192.168.1.100` |
| `LAN_SUBNET` | Local network CIDR | `192.168.1.0/24` |
| `TRAEFIK_PORT` | Traefik HTTPS entrypoint (host-side) | `8443` |
| `TRAEFIK_DASHBOARD_PORT` | Traefik dashboard (localhost only) | `8890` |
| `TRAEFIK_FRONTEND_IP` | Traefik container IP on frontend network (for Keycloak backchannel) | `172.31.1.3` |
| `NET_FRONTEND` .. `NET_WOPI` | Docker network subnets | `172.31.1.0/24` .. `172.31.5.0/24` |
| `DATA_DIR` | Base path for persistent volumes | `/srv/opendesk-data` |
| `CT_*` | Container names (used by verification script) | `opendesk_traefik`, ... |
| `REPORT_DIR` | Output directory for verification reports | `/path/to/opendesk/docs` |

See [`.env.example`](.env.example) for the complete template with all variables and defaults.

## Quick Start

```bash
# 1. Clone and configure
cp .env.example .env
# Edit .env — at minimum set DOMAIN_*, HOST_IP, and DATA_DIR

# 2. Create data directories
sudo mkdir -p /srv/opendesk-data/{keycloak/db,mariadb,nextcloud,logs/traefik}
sudo chmod 700 /srv/opendesk-data

# 3. Create Docker networks
# See docs/NETWORK_ROUTING_OVERVIEW.md Section 3

# 4. Deploy services (order matters — always from project root)
docker compose -f compose/traefik/docker-compose.yml up -d
docker compose -f compose/keycloak/docker-compose.yml up -d
docker compose -f compose/nextcloud/docker-compose.yml up -d
docker compose -f compose/collabora/docker-compose.yml up -d

# 5. Verify
bash scripts/verify-network-routing.sh
```

## License

This repository contains infrastructure configuration for a personal project. No license is granted for commercial use.
