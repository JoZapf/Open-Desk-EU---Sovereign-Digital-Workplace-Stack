# Container Hardening Baseline — Open-Desk EU

Jeder Container im openDesk-Stack MUSS die folgenden Security-Direktiven implementieren.
Abweichungen nur mit dokumentierter Begründung im jeweiligen Compose-File.

## Pflicht-Direktiven (Compose Service Level)
```yaml
services:
  example-service:
    # 1. Non-root User (wo Image es unterstützt)
    user: "1000:1000"

    # 2. Read-only Filesystem + tmpfs für Schreibpfade
    read_only: true
    tmpfs:
      - /tmp
      - /run

    # 3. Privilege Escalation verhindern
    security_opt:
      - no-new-privileges:true

    # 4. Alle Capabilities entfernen, nur benötigte zurückgeben
    cap_drop:
      - ALL
    # cap_add:
    #   - NET_BIND_SERVICE   # nur wenn Port < 1024 nötig

    # 5. Ressourcen-Limits
    deploy:
      resources:
        limits:
          memory: 512M       # pro Service anpassen
          cpus: '1.0'        # pro Service anpassen
        reservations:
          memory: 128M

    # 6. Restart Policy
    restart: unless-stopped

    # 7. Healthcheck
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

    # 8. Netzwerk — nur benötigte Netze
    networks:
      - opendesk_frontend
    # NICHT: opendesk_db (es sei denn DB-Client)

    # 9. Secrets — file-basiert, nie als ENV
    secrets:
      - db_password
    environment:
      DB_PASSWORD_FILE: /run/secrets/db_password
```

## Bekannte Ausnahmen

| Image | Abweichung | Begründung |
|---|---|---|
| Keycloak | `user:` nicht 1000:1000 | Offizielles Image nutzt UID 1000 (keycloak), aber eigener Entrypoint |
| MariaDB / PostgreSQL / MongoDB | `read_only: false` | DB-Engines benötigen Schreibzugriff auf Datenverzeichnis |
| Jitsi JVB | `cap_add: NET_ADMIN` | WebRTC benötigt Netzwerk-Capabilities für SRTP/TURN |
| Home Assistant | Nicht im openDesk-Scope | Bestehender Container, wird nicht gehärtet |

## Prüfung bei Deployment

Für jeden neuen Service vor Inbetriebnahme prüfen:
```bash
# Läuft als non-root?
docker exec <container> id

# Keine unnötigen Capabilities?
docker inspect <container> --format '{{.HostConfig.CapDrop}}'
docker inspect <container> --format '{{.HostConfig.CapAdd}}'

# no-new-privileges aktiv?
docker inspect <container> --format '{{.HostConfig.SecurityOpt}}'

# Keine Secrets in Environment?
docker inspect <container> --format '{{.Config.Env}}' | grep -i -E 'pass|secret|key|token'

# Resource Limits gesetzt?
docker inspect <container> --format 'Memory={{.HostConfig.Memory}} CPUs={{.HostConfig.NanoCpus}}'
```

## Referenz

- ADR-06: Kein globales `userns-remap`, Kompensation auf Container-Ebene
- US-001: `no-new-privileges: true` global im Docker Daemon
- DoD (Backlog Section 4): Vollständige Checkliste
