# Open-Desk EU — On-Premises Stack

Souveräne Office-Suite auf Docker/Compose, deployed auf CREA-think (192.168.10.20).

## Verzeichnisstruktur

| Pfad | Zweck | Storage |
|---|---|---|
| `~/docker/opendesk/` | Compose-Files, Config, Scripts, Secrets, Docs | SSD (Home) |
| `/mnt/docker-data/opendesk/` | Persistente Daten (Volumes, DB, Logs, Dumps) | 4 TB NVMe |

## Compose & Config (`~/docker/opendesk/`)

- `compose/` — Service-spezifische Compose-Dateien (traefik, keycloak, nextcloud, …)
- `config/` — Service-Konfigurationen (TLS, Traefik Middleware, …)
- `secrets/` — Credentials, API Keys (chmod 700, git-ignored)
- `scripts/` — Backup, Deployment, Update-Scripts
- `docs/` — ADRs, Runbooks, Architektur-Dokumentation
- `docker-compose.yml` — Root Orchestrator

## Persistente Daten (`/mnt/docker-data/opendesk/`)

- `nextcloud/`, `postgres/`, `mariadb/`, `mongodb/` — Service-Daten
- `keycloak/`, `rocketchat/`, `vaultwarden/`, `openproject/` — Service-Daten
- `logs/` — Traefik Access/Error Logs, zentrales Logging
- `db-dumps/` — Pre-Backup Datenbank-Dumps (pg_dump, mysqldump, mongodump)

## Dokumentation

- Product Backlog: siehe Projektordner (höchste Version)
- Runbook: `RUNBOOK.md`
- ADRs: im Backlog Abschnitt 1a
