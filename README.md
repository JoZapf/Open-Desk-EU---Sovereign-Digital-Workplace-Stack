# Open-Desk EU — Sovereign Digital Workplace Stack

Containerized, self-hosted digital workplace suite designed for EU data sovereignty. Deployed with Docker Compose behind Traefik reverse proxy, following Zero Trust principles with Defense-in-Depth security hardening.

## Architecture

```
Internet → nginx (TLS termination) → Traefik (routing) → Service containers
                                                           ├── Nextcloud 30 (file sync & collaboration)
                                                           ├── Keycloak 26.1 (SSO / OIDC identity provider)
                                                           ├── Collabora Online (document editing) [planned]
                                                           ├── Rocket.Chat (messaging) [planned]
                                                           ├── Jitsi Meet (video conferencing) [planned]
                                                           ├── OpenProject (project management) [planned]
                                                           └── Vaultwarden (password management) [planned]
```

## Security

All services follow the container hardening baseline documented in [`docs/CONTAINER_HARDENING_BASELINE.md`](docs/CONTAINER_HARDENING_BASELINE.md). Full security architecture and audit results are documented in [`SECURITY.md`](SECURITY.md).

Key principles:

- **Network Segmentation** — 5 isolated Docker networks; database and WOPI networks are fully internal (no internet access)
- **Least Privilege** — `cap_drop: ALL` on every container, minimal `cap_add` per service
- **Secrets as Files** — Docker Compose `secrets:` block, no plaintext credentials in compose files or environment variables
- **Immutable Infrastructure** — Read-only filesystems where possible, explicit tmpfs for runtime data
- **Centralized IAM** — Keycloak OIDC with Authorization Code Flow + PKCE for all services

## Repository Structure

```
compose/
├── traefik/          Reverse proxy + middleware definitions
├── keycloak/         Identity provider + PostgreSQL
└── nextcloud/        File sync + MariaDB + Redis + Cron
config/               Service configurations
docs/                 Architecture Decision Records, hardening baseline
secrets/              Credential files (git-ignored, chmod 700)
scripts/              Backup, deployment, update scripts
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
| TLS (Let's Encrypt) | ⏳ Planned for DNS go-live |
| Collabora Online | ⏳ Next sprint |
| Rocket.Chat | ⏳ Planned |
| Jitsi Meet | ⏳ Planned |
| OpenProject | ⏳ Planned |
| Vaultwarden | ⏳ Planned |

## Technology Stack

- **Containerization:** Docker + Docker Compose
- **Reverse Proxy:** Traefik v3.6 with automatic service discovery
- **Identity Management:** Keycloak 26.1 (OIDC / OAuth 2.0)
- **File Sync:** Nextcloud 30 with Redis caching
- **Databases:** PostgreSQL 16, MariaDB 11
- **Host OS:** Ubuntu Server
- **Monitoring:** auditd (Docker socket + daemon config)

## License

This repository contains infrastructure configuration for a personal project. No license is granted for commercial use.
