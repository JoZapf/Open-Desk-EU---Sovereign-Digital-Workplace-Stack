# Container Hardening Baseline — Open-Desk EU

Every container in the OpenDesk stack MUST implement the following security directives.
Deviations are only permitted with a documented justification in the respective compose file.

## Mandatory Directives (Compose Service Level)
```yaml
services:
  example-service:
    # 1. Non-root user (where the image supports it)
    user: "1000:1000"

    # 2. Read-only filesystem + tmpfs for writable paths
    read_only: true
    tmpfs:
      - /tmp
      - /run

    # 3. Prevent privilege escalation
    security_opt:
      - no-new-privileges:true

    # 4. Drop all capabilities, selectively restore only required ones
    cap_drop:
      - ALL
    # cap_add:
    #   - NET_BIND_SERVICE   # only if port < 1024 is needed

    # 5. Resource limits
    deploy:
      resources:
        limits:
          memory: 512M       # adjust per service
          cpus: '1.0'        # adjust per service
        reservations:
          memory: 128M

    # 6. Restart policy
    restart: unless-stopped

    # 7. Healthcheck
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

    # 8. Networks — only required networks
    networks:
      - opendesk_frontend
    # NOT: opendesk_db (unless service is a DB client)

    # 9. Secrets — file-based, never as ENV
    secrets:
      - db_password
    environment:
      DB_PASSWORD_FILE: /run/secrets/db_password
```

## Known Exceptions

| Image | Deviation | Justification |
|---|---|---|
| Keycloak | `user:` not 1000:1000 | Official image uses UID 1000 (keycloak), custom entrypoint |
| MariaDB / PostgreSQL | `read_only: false` | DB engines require write access to data directory |
| Collabora | `no-new-privileges` not set | `coolforkit-caps` requires Linux file capabilities for chroot jails. See [`NO_NEW_PRIVILEGES_PARADIGM.md`](NO_NEW_PRIVILEGES_PARADIGM.md) |
| Jitsi JVB (planned) | `cap_add: NET_ADMIN` | WebRTC requires network capabilities for SRTP/TURN |

## Deployment Verification

For each new service, verify before going live:
```bash
# Running as non-root?
docker exec <container> id

# No unnecessary capabilities?
docker inspect <container> --format '{{.HostConfig.CapDrop}}'
docker inspect <container> --format '{{.HostConfig.CapAdd}}'

# no-new-privileges active?
docker inspect <container> --format '{{.HostConfig.SecurityOpt}}'

# No secrets in environment?
docker inspect <container> --format '{{.Config.Env}}' | grep -i -E 'pass|secret|key|token'

# Resource limits set?
docker inspect <container> --format 'Memory={{.HostConfig.Memory}} CPUs={{.HostConfig.NanoCpus}}'
```

## References

- ADR-06: No global `userns-remap`, compensated at container level
- US-001: `no-new-privileges: true` global in Docker daemon
- DoD (Backlog Section 4): Complete checklist
