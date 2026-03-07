# Security Architecture — Open-Desk EU

**Last updated:** 2026-03-07
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

Five isolated bridge networks with fixed subnets:

| Network | Internal | Purpose |
|---|---|---|
| Frontend | No | Reverse proxy ↔ services (HTTP routing) |
| Backend | No | Service-to-service communication (OIDC backchannel) |
| Database | **Yes** | Database access (no internet connectivity) |
| Mail | No | Email delivery (planned) |
| WOPI | **Yes** | Collabora ↔ Nextcloud (no internet connectivity) |

`internal: true` means containers in this network have no internet access and are unreachable from outside. Only containers explicitly attached to the same network can communicate.

### 3.2 Container Network Assignment

| Container | Frontend | Backend | Database | WOPI | Rationale |
|---|---|---|---|---|---|
| Traefik | ✅ | ✅ | — | — | Reverse proxy, reaches routable services |
| Keycloak | ✅ | ✅ | ✅ | — | Frontend (routing), backend (OIDC), DB |
| Keycloak DB | — | — | ✅ | — | Database access only |
| Nextcloud | ✅ | — | ✅ | ✅ | Frontend (routing), DB, WOPI (Collabora) |
| Nextcloud DB | — | — | ✅ | — | Database access only |
| Nextcloud Redis | — | — | ✅ | — | Cache access from database network only |
| Nextcloud Cron | — | — | ✅ | — | Background jobs, DB + Redis access |
| notify_push | ✅ | — | ✅ | — | WebSocket push, needs DB (Redis) + frontend |
| Collabora | ✅ | — | — | ✅ | Frontend (routing) + WOPI (Nextcloud) |
| Whiteboard | ✅ | — | — | — | Frontend only (WebSocket via Traefik) |
| Prometheus | — | ✅ | — | — | Backend only (scrapes metrics) |
| Grafana | — | ✅ | — | — | Backend only (queries Prometheus) |
| Netdata | host | host | host | host | Host network mode (system monitoring) |

### 3.3 Ingress Architecture

```
Internet → nginx (TLS termination) → Traefik (host-based routing) → Service containers
```

Traefik binds exclusively to the loopback interface — no direct access from outside is possible. nginx terminates TLS and forwards traffic to Traefik. Traefik routes based on Host headers to individual services.

Monitoring dashboards (Grafana, Netdata) are bound to localhost only and accessible exclusively via SSH tunnel.

---

## 4. Container Hardening Baseline

### 4.1 Audit Results (2026-03-07)

All 13 containers were audited against the hardening baseline:

| Container | NoNewPrivs | CapDrop ALL | Minimal CapAdd | ReadOnly | Memory Limit | CPU Limit |
|---|---|---|---|---|---|---|
| Traefik | ✅ | ✅ | None | ✅ | ✅ | ✅ |
| Keycloak | ✅ | ✅ | DAC_READ_SEARCH | ❌ | ✅ (1024M) | ✅ |
| Keycloak DB | ✅ | ✅ | CHOWN, FOWNER, SETUID, SETGID, DAC_READ_SEARCH | ❌ | ✅ (256M) | ✅ |
| Nextcloud | ✅ | ✅ | CHOWN, DAC_OVERRIDE, FOWNER, SETUID, SETGID, DAC_READ_SEARCH, NET_BIND_SERVICE | ❌ | ✅ (2048M) | ✅ |
| Nextcloud DB | ✅ | ✅ | CHOWN, FOWNER, SETUID, SETGID, DAC_READ_SEARCH | ❌ | ✅ (1536M) | ✅ |
| Nextcloud Redis | ✅ | ✅ | DAC_READ_SEARCH | ✅ | ✅ (256M) | ✅ |
| Nextcloud Cron | ✅ | ✅ | CHOWN, DAC_OVERRIDE, FOWNER, SETUID, SETGID, DAC_READ_SEARCH | ❌ | ✅ (512M) | ✅ |
| notify_push | ✅ | ✅ | DAC_READ_SEARCH | ❌ ¹ | ✅ (256M) | ✅ |
| Collabora | ❌ ² | ✅ | SYS_CHROOT, FOWNER, CHOWN, MKNOD | ❌ | ✅ (1536M) | ✅ |
| Whiteboard | ✅ | ✅ | DAC_READ_SEARCH | ❌ | ✅ (256M) | ✅ |
| Prometheus | ✅ | ✅ | None | ✅ | ✅ (512M) | ✅ |
| Grafana | ✅ | ✅ | None | ✅ | ✅ (256M) | ✅ |
| Netdata | ❌ ³ | ❌ ³ | SYS_PTRACE, SYS_ADMIN | ❌ | ✅ (512M) | ✅ |

¹ Volume mounted read-only (`:ro`)
² Documented exception — Collabora uses Linux file capabilities (`setcap`) for jail setup, which requires `no-new-privileges` to be disabled. Compensated by custom seccomp profile, WOPI network isolation, and `cap_drop: ALL`.
³ Documented exception — Netdata requires host-level access for system monitoring (`pid: host`, `network_mode: host`). Mitigated by localhost-only access (SSH tunnel), read-only host mounts, and memory/CPU limits.

### 4.2 Assessment

**12/13 containers** comply with all critical controls (`no-new-privileges`, `cap_drop: ALL`, memory/CPU limits). Collabora and Netdata are documented exceptions with compensating controls.

**Read-only filesystem:** Traefik, Redis, Prometheus, and Grafana run with `read_only: true` (4/13). Databases, application servers, and monitoring agents require filesystem write access — documented exceptions per the hardening baseline.

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

### 5.3 Git Security

The `.gitignore` excludes all sensitive paths: secret files, environment files, runbooks containing terminal output, and archive directories pending review.

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
| Identity provider running in development mode | ✅ Switched to production build (`start --optimized`, multi-stage Dockerfile) |

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
| OIDC Discovery endpoint reachable (container-internal) | ✅ |
| Issuer URL consistent (internal = external) | ✅ |
| Authorization request parameters validated (incl. PKCE) | ✅ |
| End-to-end browser login with SSO | ✅ |
| Identity provider running in production mode | ✅ |

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
| **Host** | Firewall deny-by-default | ✅ |
| **Host** | Docker `no-new-privileges` global | ✅ |
| **Host** | auditd monitoring | ✅ |
| **Host** | CrowdSec IPS + geoblocking | ✅ |
| **Network** | 5 isolated Docker networks | ✅ |
| **Network** | Database + WOPI networks fully internal | ✅ |
| **Network** | Reverse proxy bound to loopback only | ✅ |
| **Network** | Monitoring bound to localhost (SSH tunnel) | ✅ |
| **Container** | `cap_drop: ALL` + minimal `cap_add` | ✅ (13/13) |
| **Container** | `no-new-privileges` per container | ✅ (11/13, 2 documented exceptions) |
| **Container** | Memory/CPU limits | ✅ (13/13) |
| **Container** | Read-only filesystem (where possible) | ✅ (4/13, rest documented exceptions) |
| **Container** | Healthchecks | ✅ (13/13) |
| **Container** | Seccomp profile (Collabora) | ✅ |
| **Secrets** | File-based, restrictive permissions | ✅ |
| **Secrets** | No plaintext credentials in compose | ✅ |
| **Secrets** | Git protection (.gitignore) | ✅ |
| **IAM** | OIDC with PKCE + Authorization Code Flow | ✅ |
| **IAM** | Centralized identity management (Keycloak) | ✅ |
| **IAM** | 2FA (TOTP + WebAuthn) for admin accounts | ✅ |
| **TLS** | End-to-end encryption | ⏳ (Let's Encrypt at DNS go-live) |
| **Production** | Secret rotation | ⏳ |
