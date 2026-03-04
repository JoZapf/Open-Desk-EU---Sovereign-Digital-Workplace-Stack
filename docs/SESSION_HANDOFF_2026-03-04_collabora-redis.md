# Session-Handoff: 2026-03-04 (Collabora + Redis-Fix)

## Erledigtes

### Collabora Online (US-014) — Container deployed & healthy

- **Image:** `collabora/code:25.04.9.2.1`
- **Netzwerke:** `opendesk_frontend` (Traefik) + `opendesk_wopi` (WOPI intern)
- **Seccomp:** Custom-Profil `cool-seccomp-profile.json` (Docker-Default + 6 Syscalls)
- **Subdomain:** `office.sine-math.com` via Traefik
- **Healthcheck:** `curl localhost:9980/hosting/capabilities` → OK
- **Konnektivität:** Nextcloud → Collabora über `opendesk_wopi` bestätigt
- **Secret:** `collabora_admin_password` generiert, als Docker Secret eingebunden

### Docker Daemon no-new-privileges Umbau

- **Vorher:** `no-new-privileges: true` global in `/etc/docker/daemon.json`
- **Nachher:** Entfernt. Jeder Container setzt es individuell via `security_opt`
- **Grund:** Collabora braucht Linux File Capabilities (`setcap`) für Chroot-Jails
- **Doku:** `docs/NO_NEW_PRIVILEGES_PARADIGM.md` erstellt

### Redis-Fix (Blocker behoben)

- **Problem:** Docker Compose hat `$REDIS_PASS` als Compose-Variable interpoliert → Redis startete ohne Passwort → Nextcloud hing, weil PHP Session Handler Redis ohne Auth nicht erreichen konnte
- **Fix 1:** `$$REDIS_PASS` Escaping in Redis-Command (server-seitig angewandt)
- **Fix 2:** `REDIS_HOST_PASSWORD_FILE` Environment-Variable für Nextcloud-Container hinzugefügt (fehlte komplett)

### Nextcloud richdocuments Konfiguration

```bash
# Intern (Container-zu-Container)
occ config:app:set richdocuments wopi_url --value="http://opendesk_collabora:9980"
# Extern (Browser-Iframe)
occ config:app:set richdocuments public_wopi_url --value="https://office.sine-math.com"
```

### nginx aktualisiert

- `office.sine-math.com` zum bestehenden `server_name` in `/etc/nginx/sites-available/opendesk` hinzugefügt

### app_api deaktiviert

- `docker exec -u www-data opendesk_nextcloud php occ app:disable app_api`
- Grund: app_api versuchte eigene Redis-Verbindung aufzubauen und flutete Logs mit Fehlern
- Nicht benötigt für OpenDesk-Scope

---

## Aktueller Status nach Redis-Fix

| Prüfpunkt | Status |
|-----------|--------|
| Collabora Container healthy | ✅ |
| Redis mit Passwort | ✅ |
| Nextcloud hat `REDIS_HOST_PASSWORD_FILE` | ✅ |
| Nextcloud → Collabora (WOPI intern) | ✅ |
| Browser → office.sine-math.com | ✅ (Zertifikat akzeptiert) |
| **Dokument im Browser öffnen** | ⏳ Noch nicht bestätigt — Nextcloud war nach Redis-Fix noch nicht getestet |

---

## Nächste Schritte (priorisiert)

### 1. Nextcloud + Collabora End-to-End testen

```bash
docker compose up -d --force-recreate nextcloud
sleep 15
curl -sf -m 5 -o /dev/null -w "%{http_code}" -H "Host: cloud.sine-math.com" http://192.168.10.20:8443/status.php
```

Danach im Browser: Dokument in Nextcloud Files öffnen → Collabora-Editor sollte im Iframe laden.

### 2. Produktionscontainer nachhärten

23 Container auf CREA-think haben `no-new-privileges` verloren. Jeder braucht `security_opt: [no-new-privileges:true]` in seiner Compose-Datei. Betroffene Stacks:

- Produktiv-Nextcloud (5 Container)
- HomeAssistant (1)
- empc4 (12)
- jozapf.com (3)
- mosquitto, nvme2mqtt (2)

### 3. overwriteprotocol prüfen

Nextcloud config.php hat `'overwriteprotocol' => 'http'` — sollte `'https'` sein für korrekte WOPI-URLs.

### 4. Compose-Dateien auf Server synchronisieren

Die Repo-Dateien (`/workspace/compose/`) sind aktualisiert. Per Git pull auf Windows, dann SCP auf Server.

**Achtung:** Die `$$REDIS_PASS` Escaping-Notation kann vom Git-/Editor-Tooling nicht korrekt geschrieben werden. Server-Datei hat es korrekt — Repo-Datei hat einen Kommentar als Hinweis.

---

## Geänderte Dateien im Repo

| Datei | Änderung |
|-------|---------|
| `compose/nextcloud/docker-compose.yml` | + `REDIS_HOST_PASSWORD_FILE`, + `opendesk_wopi` Netzwerk, Kommentar zu `$$REDIS_PASS` |
| `compose/collabora/docker-compose.yml` | Seccomp-Profil, `apparmor:unconfined`, kein `no-new-privileges`, kein `SYS_ADMIN`, + `CHOWN`/`MKNOD` Caps, höhere Memory-Limits |
| `docs/NO_NEW_PRIVILEGES_PARADIGM.md` | Neue Datei: Komplette Dokumentation des Paradigmenwechsels |

---

## Dateipfade (Server)

| Was | Pfad |
|-----|------|
| Collabora Compose | `~/docker/opendesk/compose/collabora/docker-compose.yml` |
| Seccomp-Profil | `~/docker/opendesk/compose/collabora/cool-seccomp-profile.json` |
| Nextcloud Compose | `~/docker/opendesk/compose/nextcloud/docker-compose.yml` |
| Docker Daemon Config | `/etc/docker/daemon.json` |
| nginx Config | `/etc/nginx/sites-available/opendesk` |
| Collabora Admin PW | `~/docker/opendesk/secrets/collabora_admin_password` |

---

## Key Learnings dieser Session

1. **Docker Compose interpoliert `$VAR` in Command-Blöcken** — Escape mit `$$VAR` nötig
2. **`REDIS_HOST_PASSWORD_FILE`** muss explizit als Nextcloud-Environment gesetzt werden — ohne diese Variable konfiguriert der Entrypoint PHP Sessions ohne Redis-Passwort
3. **Docker Daemon `no-new-privileges` ist nicht per Container überschreibbar** — weder mit `security_opt: [no-new-privileges:false]` noch mit `privileged: true`
4. **Collabora erfordert File Capabilities** — das ist fundamental für sein Sicherheitsmodell und nicht verhandelbar
