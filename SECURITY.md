# Sicherheitsstruktur Open-Desk EU

**Stand:** 2026-03-03  
**Host:** CREA-think (192.168.10.20), Ubuntu Server  
**Projekt:** Open-Desk EU — Containerized Office Suite  
**Verantwortlich:** Jo Zapf

---

## 1. Sicherheitsphilosophie

Das Projekt folgt dem Zero-Trust-Ansatz mit Defense-in-Depth-Strategie. Jede Schicht — Host, Netzwerk, Container, Applikation — implementiert eigene Sicherheitsmaßnahmen, sodass der Ausfall einer Schicht nicht zum Gesamtversagen führt.

Leitprinzipien:

- **Least Privilege:** Container erhalten nur die minimal notwendigen Linux-Capabilities
- **Network Segmentation:** Isolierte Docker-Netzwerke mit definierten Kommunikationspfaden
- **Secrets as Files:** Keine Credentials in Compose-Dateien oder Umgebungsvariablen im Klartext
- **Immutable Infrastructure:** Read-Only-Dateisysteme wo möglich, explizite tmpfs für Laufzeitdaten
- **Audit Trail:** auditd überwacht Docker Socket und Daemon-Konfiguration

---

## 2. Host-Sicherheit (CREA-think)

### 2.1 Firewall (UFW)

Default Policy: **deny (eingehend), allow (abgehend), deny (geroutet)**

Geöffnete Ports sind auf `192.168.10.0/24` beschränkt (LAN-only), mit Ausnahme von Port 443 (HTTPS, weltweit) und Samba (Anywhere — wird bei Hardening geprüft).

### 2.2 Docker Daemon

Globale Sicherheitskonfiguration in `/etc/docker/daemon.json`:

```json
{
  "ipv6": false,
  "fixed-cidr-v6": "fd00::/80",
  "no-new-privileges": true
}
```

`no-new-privileges: true` gilt global für alle Container — verhindert Privilege Escalation via `setuid`/`setgid`-Binaries. Zusätzlich setzt jeder Container `security_opt: [no-new-privileges:true]` explizit als Defense in Depth.

**Architekturentscheidung (ADR-06):** `userns-remap` wurde bewusst nicht implementiert. Begründung: Inkompatibilität mit bestehenden Bind-Mounts und Volume-Permissions, erhöhte Komplexität bei Secret-File-Zugriff, und marginaler Sicherheitsgewinn bei bereits implementiertem `cap_drop: ALL` + `no-new-privileges`.

### 2.3 Audit-Monitoring

auditd überwacht sicherheitskritische Docker-Dateien:

```
-w /var/run/docker.sock -p rwxa -k docker-socket
-w /etc/docker/daemon.json -p rwxa -k docker-config
```

---

## 3. Netzwerkarchitektur

### 3.1 Docker-Netzwerke

Fünf isolierte Bridge-Netzwerke mit festen Subnetzen:

| Netzwerk | Subnet | Internal | Zweck |
|---|---|---|---|
| `opendesk_frontend` | 172.31.1.0/24 | Nein | Traefik ↔ Services (HTTP-Routing) |
| `opendesk_backend` | 172.31.2.0/24 | Nein | Service-zu-Service (OIDC Backchannel) |
| `opendesk_db` | 172.31.3.0/24 | **Ja** | Datenbank-Zugriff (kein Internet) |
| `opendesk_mail` | 172.31.4.0/24 | Nein | E-Mail-Versand (zukünftig) |
| `opendesk_wopi` | 172.31.5.0/24 | **Ja** | Collabora ↔ Nextcloud (kein Internet) |

`internal: true` bedeutet: Container in diesem Netzwerk haben keinen Zugang zum Internet und sind von außen nicht erreichbar. Nur Container, die explizit an das gleiche Netzwerk angeschlossen sind, können kommunizieren.

### 3.2 Container-Netzwerkzuordnung

| Container | frontend | backend | db | Begründung |
|---|---|---|---|---|
| Traefik | ✅ | ✅ | — | Reverse Proxy, muss alle Services erreichen |
| Keycloak | ✅ | ✅ | ✅ | Braucht Frontend (Traefik), Backend (OIDC) und DB |
| Keycloak DB | — | — | ✅ | Nur Datenbank-Zugriff |
| Nextcloud | ✅ | — | ✅ | Frontend (Traefik) und DB, Backend-Zugriff über extra_hosts |
| Nextcloud DB | — | — | ✅ | Nur Datenbank-Zugriff |
| Nextcloud Redis | — | — | ✅ | Nur Cache-Zugriff aus DB-Netzwerk |
| Nextcloud Cron | — | — | ✅ | Hintergrund-Jobs, DB-Zugriff |

### 3.3 Ingress-Architektur

```
Internet → nginx (Host, Port 80/443) → 127.0.0.1:8443 → Traefik → Container
```

Traefik ist ausschließlich auf `127.0.0.1` gebunden — kein direkter Zugriff von außen möglich. nginx auf dem Host terminiert TLS (zukünftig via Let's Encrypt) und leitet an Traefik weiter. Traefik routet anhand von Host-Headern zu den einzelnen Services.

---

## 4. Container-Hardening-Baseline

### 4.1 Prüfergebnis (2026-03-03)

Alle 7 Container wurden per `docker inspect` gegen die Hardening-Baseline geprüft:

| Container | NoNewPrivs | CapDrop ALL | CapAdd (Minimum) | ReadOnly | Memory | CPUs | Restart |
|---|---|---|---|---|---|---|---|
| opendesk_traefik | ✅ | ✅ | — (keine) | ✅ | 256 MB | 0.5 | unless-stopped |
| opendesk_keycloak | ✅ | ✅ | DAC_READ_SEARCH | ❌ | 1024 MB | 1.0 | unless-stopped |
| opendesk_keycloak_db | ✅ | ✅ | CHOWN, FOWNER, SETUID, SETGID, DAC_READ_SEARCH | ❌ | 256 MB | 0.5 | unless-stopped |
| opendesk_nextcloud | ✅ | ✅ | CHOWN, DAC_OVERRIDE, FOWNER, SETUID, SETGID, DAC_READ_SEARCH, NET_BIND_SERVICE | ❌ | 1024 MB | 1.0 | unless-stopped |
| opendesk_nextcloud_db | ✅ | ✅ | CHOWN, FOWNER, SETUID, SETGID, DAC_READ_SEARCH | ❌ | 512 MB | 0.5 | unless-stopped |
| opendesk_nextcloud_redis | ✅ | ✅ | DAC_READ_SEARCH | ✅ | 128 MB | 0.25 | unless-stopped |
| opendesk_nextcloud_cron | ✅ | ✅ | CHOWN, DAC_OVERRIDE, FOWNER, SETUID, SETGID, DAC_READ_SEARCH | ❌ | 256 MB | 0.25 | unless-stopped |

### 4.2 Bewertung

**100% Compliance** auf den kritischen Maßnahmen: `no-new-privileges`, `cap_drop: ALL`, Memory/CPU-Limits, Restart-Policy.

**ReadOnly-Filesystem:** Traefik und Redis laufen mit `read_only: true` — Gold-Standard. Datenbanken, Keycloak (Java) und Nextcloud (Apache/PHP) benötigen Schreibzugriff auf das Dateisystem und sind daher dokumentierte Ausnahmen gemäß CONTAINER_HARDENING_BASELINE.md (US-005).

**Capabilities:** Jeder Container erhält nur die minimal notwendigen Capabilities. `cap_drop: ALL` entfernt zunächst alle Linux-Capabilities; `cap_add` gibt gezielt nur die zurück, die der jeweilige Prozess benötigt (z.B. `CHOWN`/`FOWNER` für Datenbank-Entrypoints, `NET_BIND_SERVICE` für Apache auf Port 80).

---

## 5. Secrets-Management

### 5.1 Architektur

Secrets werden als Dateien auf dem Host gespeichert und über Docker Compose `secrets:` Block in die Container gemountet unter `/run/secrets/`. Kein Secret steht als Umgebungsvariable im Klartext in Compose-Dateien.

```
~/docker/opendesk/secrets/          ← Host-Verzeichnis (chmod 700)
├── forwardauth_secret              ← chmod 600, Eigentümer jo:jo
├── keycloak_admin_password
├── mariadb_nextcloud_password
├── mariadb_root_password
├── mongodb_rocketchat_password
├── mongodb_root_password
├── nextcloud_admin_password        ← NEU (2026-03-03), getrennt von DB-Root
├── oidc_forwardauth_secret
├── oidc_nextcloud_secret
├── oidc_openproject_secret
├── oidc_rocketchat_secret
├── oidc_vaultwarden_secret
├── postgres_keycloak_password
├── postgres_openproject_password
├── redis_nextcloud_password        ← NEU (2026-03-03), ersetzt hardcoded
├── ROTATION.md
└── vaultwarden_admin_token
```

### 5.2 Secret-Zugriff im Container

Secrets im Container gehören `1000:1000` (Host-User jo) mit Permissions `600`. Nur root kann sie im Container lesen.

**Designentscheidung:** Das ist korrekt so. Der Container-Entrypoint läuft als root, liest die `_FILE`-Variablen und schreibt die Werte in die jeweilige Applikationskonfiguration (z.B. `config.php`, Datenbank). Der Applikations-User (z.B. www-data, UID 33) greift zur Laufzeit nur auf die Konfigurationsdatei zu, nie direkt auf Secret-Dateien.

Für Services die `_FILE`-Suffixe nicht nativ unterstützen (Keycloak, Redis), wird ein Shell-Wrapper als Entrypoint verwendet:

```yaml
entrypoint: ["/bin/sh", "-c"]
command:
  - |
    SECRET=$(cat /run/secrets/secret_file)
    exec service-binary --password "$SECRET"
```

### 5.3 Git-Sicherheit

Die `.gitignore` schließt alle sensiblen Pfade aus:

```
secrets/
*.env
.env.*
RUNBOOK*
```

Das Runbook enthält Terminal-Ausgaben mit sichtbaren Secret-Werten und wird bewusst nicht versioniert.

### 5.4 Nextcloud config.php — Risikobewertung

Nextcloud speichert `dbpassword`, `secret`, `passwordsalt` und `redis.password` im Klartext in `/var/www/html/config/config.php`. Diese Datei liegt auf dem Docker-Volume unter `/mnt/docker-data/opendesk/nextcloud/config/` und ist nur für root und www-data lesbar.

**Bewertung: Akzeptables Restrisiko.** Nextcloud bietet keinen Mechanismus, diese Werte zur Laufzeit aus Dateien zu lesen. Alle produktiven Nextcloud-Installationen leben mit diesem Zustand. Die Absicherung erfolgt über Volume-Permissions und die Tatsache, dass das Datenbank-Netzwerk (`opendesk_db`) als `internal: true` konfiguriert ist — selbst bei Kenntnis des DB-Passworts ist die Datenbank von außen nicht erreichbar.

---

## 6. Secrets — Rotation vor Production

Folgende Secrets waren während der Entwicklungsphase in Terminal-Sessions oder Chat-Protokollen sichtbar und **müssen vor Production-Go-Live rotiert werden**:

| Secret | Aktueller Speicherort | Expositionsgrund | Rotationsprozedur |
|---|---|---|---|
| OIDC Nextcloud Client Secret | `secrets/oidc_nextcloud_secret` | Im Chat + Terminal sichtbar (2026-03-03) | `openssl rand -base64 32` → Keycloak Admin Console → `occ user_oidc:provider` |
| Redis-Passwort | `secrets/redis_nextcloud_password` | Im Chat + Terminal sichtbar (2026-03-03) | `openssl rand -base64 32` → `occ config:system:set redis password` → Container recreate |
| Nextcloud Admin-Passwort | `secrets/nextcloud_admin_password` | Nicht im Chat sichtbar, aber Defense in Depth | `openssl rand -base64 32` → `occ user:resetpassword admin` |
| Keycloak User `jozapf` | Keycloak Realm (DB) | Temporäres Passwort `changeme` im Terminal (2026-03-01) | Ändert sich automatisch beim ersten Login (required action) |

Zusätzlich **bereits behobene** Schwachstellen:

| Problem | Status | Datum |
|---|---|---|
| Redis-Passwort `changeme-redis` hardcoded in Compose | ✅ In Secret-Datei ausgelagert | 2026-03-03 |
| Nextcloud Admin nutzte `mariadb_root_password` | ✅ Eigenes Secret erstellt | 2026-03-03 |
| Bruteforce-Schutz war temporär deaktiviert | ✅ Wieder aktiviert | 2026-03-03 |

---

## 7. Temporäre Konfigurationen (Pre-Production)

Die folgenden Einstellungen sind für die Entwicklungsphase ohne echtes DNS und TLS notwendig und **müssen vor Production-Go-Live überprüft und angepasst werden**:

| Einstellung | Ort | Risiko | Aktion |
|---|---|---|---|
| `allow_local_remote_servers = true` | Nextcloud `config.php` | **Mittel** — SSRF-Schutz deaktiviert | Prüfen ob nach DNS-Go-Live zurücknehmbar |
| `extra_hosts: id.sine-math.com:172.31.1.3` | Nextcloud Compose | Niedrig — statische IP-Bindung | Entfernen wenn DNS live |
| dnsmasq `address=/id.sine-math.com/172.31.1.3` | `/etc/dnsmasq.d/opendesk.conf` | Niedrig — DNS-Workaround | Entfernen/ändern wenn DNS live |
| `/etc/hosts` Eintrag `cloud.sine-math.com` | Host `/etc/hosts` | Niedrig — lokale DNS-Überschreibung | Entfernen vor DNS-Go-Live |
| `DOCKER_API_VERSION=1.44` | Traefik Compose | Keins — wirkungslos seit v3.6 | Entfernen (Cleanup) |
| Keycloak `start-dev` Modus | Keycloak Compose | **Hoch** — keine Optimierung, Dev-Features aktiv | `kc.sh build` + `start` (Production Build) |

---

## 8. OIDC-Sicherheitsarchitektur

### 8.1 Authentifizierungsfluss

```
Browser → Nextcloud → 303 Redirect → Keycloak Login → Authorization Code + PKCE
Keycloak → Callback → Nextcloud → Token Exchange (Backchannel) → Keycloak
Keycloak → ID Token + Access Token → Nextcloud → Session erstellt
```

### 8.2 Implementierte Sicherheitsmaßnahmen

- **PKCE (Proof Key for Code Exchange)** mit S256: Verhindert Authorization Code Interception
- **Authorization Code Flow** (nicht Implicit): Token werden nie im Browser exponiert
- **Backchannel Token Exchange**: Nextcloud tauscht Code direkt mit Keycloak, nicht über den Browser
- **Client Secret**: Zusätzliche Absicherung des Token-Endpoints (confidential client)
- **Scope Limitation**: Nur `openid email profile` — kein übermäßiger Zugriff auf Keycloak-Daten

### 8.3 Verifizierungsstatus

| Prüfpunkt | Status | Beweis |
|---|---|---|
| OIDC Discovery Endpoint erreichbar (Container-intern) | ✅ | HTTP 200 auf `.well-known/openid-configuration` |
| Issuer-URL konsistent (intern = extern) | ✅ | `http://id.sine-math.com:8443/realms/opendesk` |
| Authorization Request korrekt (303 Redirect) | ✅ | Alle Parameter validiert inkl. PKCE |
| End-to-End Browser Login | ⏳ | Blockiert durch fehlendes TLS, geplant bei DNS-Go-Live |

---

## 9. Gesamtbewertung

| Schicht | Maßnahme | Status |
|---|---|---|
| **Host** | UFW deny-by-default | ✅ |
| **Host** | Docker `no-new-privileges` global | ✅ |
| **Host** | auditd Docker Socket Monitoring | ✅ |
| **Netzwerk** | 5 isolierte Docker-Netzwerke | ✅ |
| **Netzwerk** | DB + WOPI `internal: true` | ✅ |
| **Netzwerk** | Traefik nur auf 127.0.0.1 | ✅ |
| **Container** | `cap_drop: ALL` + minimale `cap_add` | ✅ (7/7) |
| **Container** | `no-new-privileges` pro Container | ✅ (7/7) |
| **Container** | Memory/CPU Limits | ✅ (7/7) |
| **Container** | Read-Only Filesystem (wo möglich) | ✅ (2/7, Rest dokumentierte Ausnahmen) |
| **Container** | Healthchecks | ✅ (7/7) |
| **Secrets** | File-basiert, chmod 600, Verzeichnis 700 | ✅ |
| **Secrets** | Keine Klartext-Credentials in Compose | ✅ |
| **Secrets** | Git-Schutz (.gitignore) | ✅ |
| **IAM** | OIDC mit PKCE + Authorization Code Flow | ✅ |
| **IAM** | Zentrales Identity Management (Keycloak) | ✅ |
| **TLS** | End-to-End-Verschlüsselung | ⏳ (bei DNS-Go-Live mit Let's Encrypt) |
| **Production** | Keycloak Production Build | ⏳ |
| **Production** | Secret-Rotation | ⏳ |
