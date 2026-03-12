# Security Architecture — Open-Desk EU

**Last updated:** 2026-03-12
**Project:** Open-Desk EU — Sovereign Digital Workplace Stack

---

## 1. Security Philosophy

This project follows a Zero Trust approach with Defense-in-Depth strategy. Each layer — host, network, container, application — implements its own security controls, ensuring that a failure in one layer does not compromise the entire system.

Core principles:

- **Least Privilege:** Containers receive only the minimum required Linux capabilities
- **Network Segmentation:** Isolated Docker networks with defined communication paths
- **Secrets as Files:** No credentials in compose files or plaintext environment variables
- **Immutable Infrastructure:** Read-only filesystems where possible, explicit tmpfs for runtime data
- **Host Intrusion Prevention:** CrowdSec with geoblocking and community threat intelligence
- **Audit Trail:** auditd monitors Docker socket and daemon configuration changes

---

## 2. Host Security

### 2.1 Firewall

Default policy: **deny (incoming), allow (outgoing), deny (routed)**

Open ports are restricted to the local network (LAN-only), with the exception of port 443 (HTTPS).

### 2.2 Intrusion Prevention (CrowdSec)

CrowdSec runs on the host as an IPS (Intrusion Prevention System) with:

- **Geoblocking:** Only traffic from allowed countries is accepted
- **Community Intelligence:** Shared blocklists from the CrowdSec network
- **Prometheus Metrics:** Exposed on localhost for Grafana dashboards (alert visualization, blocked IPs, geoblocking activity)

### 2.3 Docker Daemon

Global `no-new-privileges` enforcement via daemon configuration prevents privilege escalation via `setuid`/`setgid` binaries across all containers. Each container additionally sets this flag explicitly as Defense in Depth.

**Architecture Decision (ADR-06):** `userns-remap` was deliberately not implemented. Rationale: incompatibility with existing bind mounts and volume permissions, increased complexity for secret file access, and marginal security gain given the already implemented `cap_drop: ALL` + `no-new-privileges`.

### 2.4 Audit Monitoring

auditd monitors security-critical Docker files (socket and daemon configuration) for read, write, execute, and attribute changes.

---

## 3. Network Architecture

### 3.1 Docker Networks

Six isolated bridge networks with fixed subnets:

| Network | Internal | Purpose |
|---|---|---|
| Frontend | No | Reverse proxy ↔ services (HTTP routing) |
| Backend | No | Service-to-service communication (OIDC backchannel) |
| Database | **Yes** | Database access (no internet connectivity) |
| Mail | No | Email delivery (planned) |
| WOPI | **Yes** | Collabora ↔ Nextcloud (no internet connectivity) |
| LaTeX DB | **Yes** | Overleaf ↔ MongoDB + Redis (no internet connectivity) |

`internal: true` means containers in this network have no internet access and are unreachable from outside. Only containers explicitly attached to the same network can communicate.

### 3.2 Container Network Assignment

| Container | Frontend | Backend | Database | WOPI | LaTeX DB | Rationale |
|---|---|---|---|---|---|---|
| Traefik | x | x | — | — | — | Reverse proxy, reaches routable services |
| Keycloak | x | x | x | — | — | Frontend (routing), backend (OIDC), DB |
| Keycloak DB | — | — | x | — | — | Database access only |
| Nextcloud | x | — | x | x | — | Frontend (routing), DB, WOPI (Collabora) |
| Nextcloud DB | — | — | x | — | — | Database access only |
| Nextcloud Redis | — | — | x | — | — | Cache access from database network only |
| Nextcloud Cron | — | — | x | — | — | Background jobs, DB + Redis access |
| notify_push | x | — | x | — | — | WebSocket push, needs DB (Redis) + frontend |
| Collabora | x | — | — | x | — | Frontend (routing) + WOPI (Nextcloud) |
| Whiteboard | x | — | — | — | — | Frontend only (WebSocket via Traefik) |
| Vaultwarden | x | — | — | — | — | Frontend (routing), SQLite (local) |
| Overleaf | x | — | — | — | x | Frontend (routing) + LaTeX DB |
| Overleaf MongoDB | — | — | — | — | x | LaTeX DB access only |
| Overleaf Redis | — | — | — | — | x | LaTeX DB access only |
| Prometheus | — | x | — | — | — | Backend only (scrapes metrics) |
| Grafana | — | x | — | — | — | Backend only (queries Prometheus) |
| Netdata | host | host | host | host | host | Host network mode (system monitoring) |

### 3.3 Ingress Architecture

```
Internet → nginx (TLS termination) → Traefik (host-based routing) → Service containers
```

Traefik binds exclusively to the loopback interface — no direct access from outside is possible. nginx terminates TLS and forwards traffic to Traefik. Traefik routes based on Host headers to individual services.

Monitoring dashboards (Grafana, Netdata) are bound to localhost only and accessible exclusively via SSH tunnel.

---

## 4. Container Hardening Baseline

### 4.1 Audit Results (2026-03-12)

All containers were audited against the hardening baseline:

| Container | NoNewPrivs | CapDrop ALL | Minimal CapAdd | ReadOnly | Memory Limit | CPU Limit |
|---|---|---|---|---|---|---|
| Traefik | x | x | None | x | x | x |
| Keycloak | x | x | DAC_READ_SEARCH | — | x (1024M) | x |
| Keycloak DB | x | x | CHOWN, FOWNER, SETUID, SETGID, DAC_READ_SEARCH | — | x (256M) | x |
| Nextcloud | x | x | CHOWN, DAC_OVERRIDE, FOWNER, SETUID, SETGID, DAC_READ_SEARCH, NET_BIND_SERVICE | — | x (2048M) | x |
| Nextcloud DB | x | x | CHOWN, FOWNER, SETUID, SETGID, DAC_READ_SEARCH | — | x (1536M) | x |
| Nextcloud Redis | x | x | DAC_READ_SEARCH | x | x (256M) | x |
| Nextcloud Cron | x | x | CHOWN, DAC_OVERRIDE, FOWNER, SETUID, SETGID, DAC_READ_SEARCH | — | x (512M) | x |
| notify_push | x | x | DAC_READ_SEARCH | — ¹ | x (256M) | x |
| Collabora | — ² | x | SYS_CHROOT, FOWNER, CHOWN, MKNOD | — | x (1536M) | x |
| Whiteboard | x | x | DAC_READ_SEARCH | — | x (256M) | x |
| Vaultwarden | x | x | None | — | x (256M) | x |
| Overleaf | — ³ | x | CHOWN, SETUID, SETGID, DAC_OVERRIDE | — | x (2048M) | x |
| Overleaf MongoDB | x | x | CHOWN, SETUID, SETGID | — | x (512M) | x |
| Overleaf Redis | x | x | CHOWN, SETUID, SETGID | x | x (128M) | x |
| Prometheus | x | x | None | x | x (512M) | x |
| Grafana | x | x | None | x | x (256M) | x |
| Netdata | — ⁴ | — ⁴ | SYS_PTRACE, SYS_ADMIN | — | x (512M) | x |

¹ Volume mounted read-only (`:ro`)
² Documented exception — Collabora uses Linux file capabilities (`setcap`) for jail setup, which requires `no-new-privileges` to be disabled. Compensated by custom seccomp profile, WOPI network isolation, and `cap_drop: ALL`.
³ Documented exception — Overleaf uses Phusion baseimage with `my_init`, which requires `setuid()`/`setgid()` to start services under different user contexts (www-data, node). Compensated by `cap_drop: ALL`, isolated LaTeX DB network (`internal: true`), no Docker socket access, memory/CPU limits.
⁴ Documented exception — Netdata requires host-level access for system monitoring (`pid: host`, `network_mode: host`). Mitigated by localhost-only access (SSH tunnel), read-only host mounts, and memory/CPU limits.

### 4.2 Assessment

**14/17 containers** comply with all critical controls (`no-new-privileges`, `cap_drop: ALL`, memory/CPU limits). Collabora, Overleaf, and Netdata are documented exceptions with compensating controls.

**Read-only filesystem:** Traefik, Nextcloud Redis, Overleaf Redis, Prometheus, and Grafana run with `read_only: true` (5/17). Databases, application servers, and monitoring agents require filesystem write access — documented exceptions per the hardening baseline.

**Capabilities:** Each container receives only the minimum required capabilities. `cap_drop: ALL` removes all Linux capabilities first; `cap_add` selectively restores only those needed by the respective process.

---

## 5. Secrets Management

### 5.1 Architecture

Secrets are stored as files on the host and mounted into containers via Docker Compose `secrets:` block under `/run/secrets/`. No secret appears as a plaintext environment variable in compose files.

The secrets directory is protected with `chmod 700`, individual secret files with `chmod 600`. The directory and all secret files are excluded from version control via `.gitignore`.

### 5.2 Secret Access in Containers

Secrets inside containers are owned by the host user with permissions `600`. Only root can read them inside the container.

**Design decision:** The container entrypoint runs as root, reads `_FILE` variables, and writes the values into the respective application configuration. The application user (e.g., www-data) accesses only the configuration at runtime, never the secret files directly.

For services that do not natively support `_FILE` suffixes (Keycloak, Redis, Whiteboard), a shell wrapper is used as entrypoint to read the secret file and pass the value via environment variable to the service process.

### 5.3 Repository Hygiene

This is a public repository. The `.gitignore` protects all data that makes the installation identifiable or mappable:

| Category | Paths | Content |
|---|---|---|
| Secrets | `secrets/` | Passwords, tokens, API keys |
| Environment | `.env`, `*.env`, `.env.*` | Domains, IPs, subnets, credentials |
| Project instructions | `CLAUDE.md` | Infrastructure details, admin users |
| Sensitive compose files | `compose/vaultwarden/`, `compose/collabora/`, `compose/latex/`, `compose/traefik/dynamic/middlewares.yml` | SMTP addresses, redirect URLs, domains |
| Sensitive scripts | `scripts/ddns/`, `scripts/keycloak/`, `scripts/gather-network-info*`, `scripts/verify-network-routing*` | Zone IDs, domains, IPs |
| Documentation | `wiki/docs/`, `docs/`, `RUNBOOK*`, `OPEN-DESK_Product_Backlog*` | Network topology, pentest reports, infrastructure details |

**What remains public:** Architecture patterns, generic compose structures, network design, hardening baseline, `.env.example` template — everything needed to understand and replicate the approach without revealing the specific deployment.

### 5.4 Application Config — Risk Assessment

Some applications (e.g., Nextcloud) store database passwords and session secrets in plaintext configuration files. These files reside on Docker volumes and are readable only by root and the application user.

**Assessment: Acceptable residual risk.** The applications provide no mechanism to read these values from files at runtime. Mitigation is provided through volume permissions and the fact that database networks are configured as `internal: true` — even with knowledge of a DB password, the database is unreachable from outside.

---

## 6. Secret Rotation Strategy

All secrets generated during development are tracked for rotation before production go-live. A pre-production checklist tracks:

- Secrets that were visible in terminal sessions during debugging
- Secrets that were initially hardcoded and later migrated to file-based storage
- Temporary passwords set during initial deployment

Each secret has a documented rotation procedure specifying the exact commands and service restarts required. The rotation schedule follows a 60–90 day cycle for production.

Previously resolved issues:

| Issue | Resolution |
|---|---|
| Cache password hardcoded in compose file | Migrated to secret file with shell wrapper |
| Admin password shared with database root | Separated into dedicated secret |
| Bruteforce protection temporarily disabled during debugging | Re-enabled after successful testing |

---

## 7. Temporary Configurations (Pre-Production)

The following settings exist for the development phase and are tracked for review before production go-live:

| Category | Risk | Action Required |
|---|---|---|
| SSRF protection relaxed for internal OIDC backchannel | **Medium** | Evaluate removal after DNS go-live |
| Static host entries for container-internal DNS resolution | Low | Remove when public DNS is active |
| Self-signed TLS certificate for LAN testing | Low | Replace with Let's Encrypt |
| Reverse proxy temporarily bound to LAN interface | **Medium** | Restrict to loopback before production |

Previously resolved:

| Category | Resolution |
|---|---|
| Identity provider running in development mode | Switched to production build (`start --optimized`, multi-stage Dockerfile) |

---

## 8. OIDC Security Architecture

### 8.1 Authentication Flow

```
Browser → Application → 303 Redirect → Identity Provider Login
Identity Provider → Authorization Code + PKCE → Callback
Application → Backchannel Token Exchange → Identity Provider
Identity Provider → ID Token + Access Token → Application → Session created
```

### 8.2 Implemented Security Controls

- **PKCE (Proof Key for Code Exchange)** with S256: Prevents authorization code interception
- **Authorization Code Flow** (not Implicit): Tokens are never exposed in the browser
- **Backchannel Token Exchange**: Application exchanges the code directly with the identity provider, not via the browser
- **Client Secret**: Additional protection of the token endpoint (confidential client)
- **Scope Limitation**: Only `openid email profile` — no excessive access to identity provider data
- **2FA (Two-Factor Authentication)**: TOTP and WebAuthn configured for admin accounts

### 8.3 Verification Status

| Check | Status |
|---|---|
| OIDC Discovery endpoint reachable (container-internal) | Verified |
| Issuer URL consistent (internal = external) | Verified |
| Authorization request parameters validated (incl. PKCE) | Verified |
| End-to-end browser login with SSO | Verified |
| Identity provider running in production mode | Verified |

---

## 9. Performance Hardening

Performance tuning is applied with security constraints maintained:

- **PHP OPcache/JIT:** Tracing JIT enabled, `validate_timestamps=0` (immutable container images — no runtime code modification possible)
- **MariaDB InnoDB:** Tuned buffer pool, `innodb_flush_log_at_trx_commit=2` (acceptable trade-off: 1-second data loss window vs. significant write performance gain)
- **Redis:** `maxmemory-policy allkeys-lru` with capped memory, no persistence (cache-only role)
- **notify_push:** WebSocket-based push replaces client polling, reducing server load and attack surface from repeated HTTP requests

---

## 10. Monitoring & Observability

### 10.1 Architecture

| Component | Purpose | Access |
|---|---|---|
| Prometheus | Metrics collection (CrowdSec, host metrics) | Internal only (container network) |
| Grafana | Dashboards and alerting | Localhost only (SSH tunnel) |
| Netdata | Real-time system and container monitoring | Localhost only (SSH tunnel) |
| auditd | Docker socket and daemon audit trail | Host-level logs |

### 10.2 Security Controls

- No monitoring endpoint is exposed to the internet
- Grafana and Netdata are accessible only via SSH tunnel (bound to `127.0.0.1`)
- Prometheus scrapes only internal targets (no external metrics ingestion)
- CrowdSec metrics provide visibility into blocked attacks, geoblocking activity, and community threat intelligence

---

## 11. Overall Assessment

| Layer | Control | Status |
|---|---|---|
| **Host** | Firewall deny-by-default | Verified |
| **Host** | Docker `no-new-privileges` global | Verified |
| **Host** | auditd monitoring | Verified |
| **Host** | CrowdSec IPS + geoblocking | Verified |
| **Network** | 6 isolated Docker networks | Verified |
| **Network** | Database + WOPI + LaTeX-DB networks fully internal | Verified |
| **Network** | Reverse proxy bound to loopback only | Verified |
| **Network** | Monitoring bound to localhost (SSH tunnel) | Verified |
| **Container** | `cap_drop: ALL` + minimal `cap_add` | Verified (17/17) |
| **Container** | `no-new-privileges` per container | Verified (14/17, 3 documented exceptions) |
| **Container** | Memory/CPU limits | Verified (17/17) |
| **Container** | Read-only filesystem (where possible) | Verified (5/17, rest documented exceptions) |
| **Container** | Healthchecks | Verified (17/17) |
| **Container** | Seccomp profile (Collabora) | Verified |
| **Secrets** | File-based, restrictive permissions | Verified |
| **Secrets** | No plaintext credentials in compose | Verified |
| **Secrets** | Git protection (.gitignore) | Verified |
| **Secrets** | Infrastructure identity excluded from repo | Verified |
| **IAM** | OIDC with PKCE + Authorization Code Flow | Verified |
| **IAM** | Centralized identity management (Keycloak) | Verified |
| **IAM** | 2FA (TOTP + WebAuthn) for admin accounts | Verified |
| **TLS** | End-to-end encryption | Planned (Let's Encrypt at DNS go-live) |
| **Production** | Secret rotation | Planned |
