# Product Backlog — Open-Desk Containerized On-Prem Stack
**Project:** Open-Desk EU · On-Premises · Docker/Compose  
**Host:** CREA-think · Ubuntu · IP 192.168.10.20  
**Security Paradigms:** Zero Trust · Defense in Depth  
**Created:** 2026-02-28  
**Status:** DRAFT v1.4  

---

## 0. Konzeptionelle Schwachstellen (Review v1.0 → v1.2)

> Die folgende Analyse identifiziert strukturelle und logische Widersprüche im Backlog, die vor Sprint-Start aufgelöst werden müssen. Jede Schwachstelle referenziert die betroffenen User Stories und beschreibt die vorgenommene Korrektur. KS-01 bis KS-10 wurden in v1.1 identifiziert, KS-11 und KS-12 in v1.2.

---

### KS-01 · Traefik Netzwerk-Isolation vs. Routing-Anforderung

**Problem:** US-006 bindet Traefik ausschließlich an `opendesk_frontend`. Gleichzeitig liegt Keycloak (US-010) auf `opendesk_backend`. Traefik kann Keycloak nicht routen, wenn es keinen Zugang zum Backend-Netzwerk hat. Dasselbe gilt für `traefik-forward-auth` (US-012), Redis und Loki/Promtail — alles Backend-Services, die Traefik direkt oder indirekt erreichen muss.

**Korrektur:** Traefik wird an `opendesk_frontend` UND `opendesk_backend` angeschlossen. Die `opendesk_db`-Isolation bleibt unangetastet. US-006 Acceptance Criteria entsprechend erweitert.

---

### KS-02 · ForwardAuth pauschal auf alle Routes bricht Machine-to-Machine-Kommunikation

**Problem:** US-012 verlangt ForwardAuth-Middleware auf **alle** Open-Desk-Router-Regeln. Collabora Online (US-014) nutzt WOPI-Callbacks von Nextcloud — das sind Server-zu-Server-Aufrufe ohne Browser-Session. Jitsi (US-018) nutzt WebRTC/SRTP und interne Prosody-Kommunikation. Pauschal angewendetes ForwardAuth blockiert diese Flows und bricht beide Services.

**Korrektur:** US-012 differenziert jetzt zwischen Browser-facing Routes (ForwardAuth aktiv) und M2M/API-Routes (Allowlist-basiert, z. B. Source-IP-Restriction auf interne Docker-Netze). US-014 und US-018 erhalten explizite Ausnahme-Kriterien.

---

### KS-03 · Inkonsistentes Backup-Konzept — Volume-Backup statt konsistenter DB-Dumps

**Problem:** US-021 definiert als Backup-Target "all Docker volumes under `/opt/opendesk/data/`". Ein File-Level-Backup laufender Datenbanken (PostgreSQL, MariaDB, MongoDB) erzeugt inkonsistente Snapshots und kann bei Restore zu Korruption führen. Konsistente Backups erfordern `pg_dump`, `mysqldump` bzw. `mongodump` VOR dem Volume-Backup.

**Korrektur:** US-021 erhält ein explizites Acceptance Criterion für Pre-Backup-DB-Dumps (logische Exports) mit anschließendem Volume-Backup der Dump-Files + Application-Data.

---

### KS-04 · Undefinierte TLS-Terminierungsstrategie (Nginx ↔ Traefik)

**Problem:** Die Architektur zeigt `nginx (host) → Traefik (container)`. US-007 konfiguriert TLS in Traefik (ACME/Let's Encrypt), US-008 konfiguriert nginx als Upstream-Proxy. Es ist nicht definiert, WER TLS terminiert. Möglichkeiten: (a) Nginx terminiert TLS → Traefik empfängt Plaintext auf 127.0.0.1:8443, (b) Nginx macht TCP-Passthrough → Traefik terminiert TLS. Option (a) bedeutet: Traefik sieht kein TLS und ACME ist sinnlos. Option (b) erfordert nginx Stream-Modul statt HTTP-Proxy. Das Backlog lässt das offen.

**Korrektur:** Explizite Entscheidung für **Nginx TLS-Termination + Proxy Protocol** an Traefik. Traefik arbeitet im HTTP-Modus mit Proxy-Protocol-Header für Client-IP-Transparenz. Let's Encrypt-Zertifikate werden auf Nginx-Ebene verwaltet (oder via Traefik mit DNS-Challenge, wobei Nginx dann reinen TCP-Passthrough macht). US-007 und US-008 erhalten je ein Acceptance Criterion, das die gewählte Variante festlegt.

---

### KS-05 · Collabora Network ACL technisch nicht umsetzbar

**Problem:** US-014 fordert: "Only Nextcloud container can communicate with Collabora backend (network ACL)". Beide Container liegen auf `opendesk_frontend`. Docker Bridge Networks bieten keine Container-zu-Container-ACLs — alle Container im selben Netzwerk können sich gegenseitig erreichen. Das Acceptance Criterion ist mit der aktuellen Architektur nicht erfüllbar.

**Korrektur:** Neues dediziertes Netzwerk `opendesk_wopi` für die Nextcloud ↔ Collabora-Kommunikation. Collabora wird von `opendesk_frontend` entkoppelt und nur über Traefik (für den Browser-Zugang) und `opendesk_wopi` (für WOPI-Callbacks von Nextcloud) erreichbar. Netzwerk-Tabelle und US-003, US-014 entsprechend aktualisiert.

---

### KS-06 · MongoDB fehlt in der Architektur-Übersicht

**Problem:** Rocket.Chat (US-017) benötigt MongoDB als Backend. Die Architektur-Übersicht (Section 3) listet unter `opendesk_db` nur PostgreSQL und MariaDB. MongoDB ist weder in der Architektur noch in der Netzwerk-Planung noch im Backup-Konzept berücksichtigt. Auch der Security Risk Register erwähnt MongoDB nicht.

**Korrektur:** MongoDB in Architektur-Diagramm, Netzwerk-Tabelle, Backup-Story (US-021) und Risk Register aufgenommen.

---

### KS-07 · Fehlende User Story für Update- und Patch-Management

**Problem:** US-024 scannt Images auf CVEs, aber es existiert keine User Story, die den eigentlichen Update-Prozess definiert: Wie werden Container-Images aktualisiert? Gibt es Rolling Updates? Maintenance Windows? Rollback-Verfahren? Ohne diesen Prozess bleibt das Scanning ein Audit-Artefakt ohne operativen Wert.

**Korrektur:** Neue User Story **US-028 · Container Image Update & Rollback Procedure** unter E-08 ergänzt.

---

### KS-08 · Fehlende Dependency: US-010 (Keycloak) → US-003 (Netzwerke)

**Problem:** US-010 deployed Keycloak auf `opendesk_backend` mit PostgreSQL auf `opendesk_db`. Beide Netzwerke werden in US-003 erstellt. US-010 listet aber US-003 nicht als Dependency — nur US-006, US-007, US-004. Ohne Netzwerke kann Keycloak nicht deployed werden.

**Korrektur:** US-003 als Dependency zu US-010 hinzugefügt. Gleichzeitig systematischer Review aller Dependencies durchgeführt und fehlende Abhängigkeiten in US-017 (→ US-003) und US-019 (→ US-005) ergänzt.

---

### KS-09 · Jitsi TURN/STUN "LAN only" widerspricht Internet-fähiger Architektur

**Problem:** US-018 definiert TURN/STUN "for NAT traversal within LAN" und Port 10000/UDP nur für LAN. Gleichzeitig impliziert die Verwendung von Let's Encrypt (DNS-01 oder HTTP-01) und öffentlichen Subdomains, dass die Architektur auch für Remote-Zugriff über Internet vorgesehen ist. TURN/STUN nur LAN-scoped macht Jitsi für externe Teilnehmer unbrauchbar.

**Korrektur:** US-018 erhält eine Klarstellung: TURN/STUN-Konfiguration unterscheidet zwischen LAN-Deployment (interner STUN) und Internet-Deployment (TURN-Server mit öffentlicher IP oder externer TURN-Service). Acceptance Criterion für beide Modi definiert.

---

### KS-10 · Monitoring-Ports (Grafana, Uptime Kuma) fehlen in der Port-Allocation-Tabelle

**Problem:** US-019 bindet Grafana auf `127.0.0.1:3000`, US-020 bindet Uptime Kuma auf `127.0.0.1:3001`. Beide Ports fehlen in der zentralen Port-Allocation-Tabelle (Section 2), obwohl diese als Single Source of Truth für Port-Konflikte dient. Bei wachsendem Stack entstehen so blinde Flecken.

**Korrektur:** Grafana und Uptime Kuma in die Port-Allocation-Tabelle aufgenommen. Regel ergänzt: Jeder Service mit Host-Port-Binding MUSS in der Tabelle erfasst werden.

---

### KS-11 · Doppelte Nextcloud-Instanz — fehlende Migrationsstrategie

**Problem:** Auf dem Host läuft bereits eine produktive Nextcloud-Instanz (Port 8085, eigener Compose-Stack, MariaDB auf Port 3307). US-013 deployt eine *zweite*, separate Nextcloud-Instanz im openDesk-Stack. Das Backlog erwähnt diese Koexistenz zwar ("Distinct from existing `nextcloud` on port 8085"), definiert aber keine Strategie: Wird die bestehende Instanz langfristig migriert und durch die openDesk-Nextcloud ersetzt? Laufen beide dauerhaft parallel — und wenn ja, mit welcher Datenabgrenzung? Oder wird die bestehende Instanz in den openDesk-Stack integriert (gleiche Daten, neuer Ingress)? Ohne diese Entscheidung entsteht Daten-Fragmentierung (Dateien auf zwei Instanzen), doppelter Wartungsaufwand, potenzielle Verwirrung bei Endnutzern und unnötiger Ressourcenverbrauch auf einem Single-Server-Setup.

**Korrektur:** Neue User Story **US-029 · Bestehende Nextcloud: Migrationsentscheidung & Koexistenzstrategie** unter E-01 ergänzt (muss VOR US-013 entschieden werden). US-013 erhält eine Dependency auf US-029. Drei Optionen werden in US-029 evaluiert und eine verbindlich gewählt.

---

### KS-12 · Abweichende Komponentenwahl vs. offizielles openDesk — undokumentierte Architekturentscheidungen

**Problem:** Das offizielle openDesk-Projekt (ZenDiS/BMI) definiert einen festen Komponentenstack: Nextcloud, Collabora, **Element/Matrix** (Chat), **Univention Nubus** (IAM/Portal), **Open-Xchange** (Mail/Calendar/Contacts), **XWiki** (Knowledge Management), OpenProject, Jitsi, Nordeck-Widgets. Das vorliegende Backlog weicht in mehreren Kernbereichen ab:

| Bereich | offizielles openDesk | dieses Backlog | Auswirkung |
|---|---|---|---|
| Chat/Messaging | Element (Matrix) | Rocket.Chat | Kein Matrix-Protokoll, keine Federation, andere DB (MongoDB statt Synapse/PostgreSQL) |
| IAM/Portal | Univention Nubus | Keycloak | Kein zentrales Portal, anderes LDAP-Schema, andere Provisioning-Flows |
| Mail/Calendar | Open-Xchange AppSuite | *fehlt komplett* | Kein E-Mail, kein Kalender, kein Adressbuch im Stack |
| Wiki/Knowledge | XWiki | *fehlt komplett* | Kein Knowledge-Management-Tool |

Diese Abweichungen können bewusst und sinnvoll sein (leichterer Stack für Single-Admin-Betrieb, Vermeidung von Univention-Komplexität, kein Mail-Bedarf weil extern gelöst). Aber sie sind **nirgends dokumentiert** — weder als Architectural Decision Record (ADR) noch als bewusste Scope-Entscheidung im Backlog. Das führt zu: (a) Unklarheit ob Komponenten vergessen oder bewusst ausgelassen wurden, (b) fehlender Evaluationsgrundlage für spätere Erweiterungen, (c) Verwirrung wenn das Projekt sich "Open-Desk EU" nennt aber wesentliche openDesk-Komponenten fehlen.

**Korrektur:** Neuer Abschnitt **"1a. Architekturentscheidungen (ADR)"** eingefügt, der die bewussten Abweichungen vom offiziellen openDesk-Stack dokumentiert und begründet. Jede Abweichung wird als ADR mit Status (Accepted/Open) geführt. Offene Entscheidungen (z. B. Mail-Lösung) werden als potenzielle zukünftige Epics markiert.

---

## 1. Product Vision

> *Deliver a fully containerized, sovereign, privacy-compliant open-source office suite (Open-Desk EU) on an existing Ubuntu server — integrated via a Zero Trust security model, co-existing with existing services without port conflicts, and maintainable by a single administrator.*

---

## 1a. Architekturentscheidungen — Abweichungen vom offiziellen openDesk-Stack (KS-12)

> Das offizielle openDesk-Projekt (ZenDiS/BMI, Release 1.0 Oktober 2024) definiert einen Referenzstack für den öffentlichen Sektor. Dieses Projekt übernimmt die openDesk-Philosophie (souverän, Open Source, On-Premises), wählt aber bewusst einen **reduzierten und angepassten Komponentenstack**, optimiert für den Betrieb durch einen einzelnen Administrator auf einem einzelnen Server.

| ADR | Entscheidung | Begründung | Status |
|---|---|---|---|
| ADR-01 | **Keycloak statt Univention Nubus als IAM** | Nubus bringt ein vollständiges UCS-Ökosystem mit (LDAP, Portal, Provisioning), das für ein Single-Server-Setup überdimensioniert ist. Keycloak bietet OIDC/SAML SSO mit deutlich geringerem operativem Overhead. Trade-off: Kein zentrales Portal — Zugang erfolgt über individuelle Subdomains. | Accepted |
| ADR-02 | **Rocket.Chat statt Element/Matrix als Chat** | Element/Matrix (Synapse) erfordert einen separaten Homeserver mit erheblichem Ressourcenbedarf und komplexer Federation-Konfiguration. Rocket.Chat bietet vergleichbare Funktionalität mit einfacherem Betrieb. Trade-off: Kein Matrix-Protokoll, keine Cross-Organisation-Federation. | Accepted |
| ADR-03 | **Kein Open-Xchange (Mail/Calendar/Contacts)** | E-Mail wird extern bereitgestellt (bestehende Infrastruktur). Ein vollständiger Groupware-Stack (OX AppSuite + Dovecot + Postfix) würde den Scope und die Komplexität des Projekts erheblich erweitern. Trade-off: Kein integriertes Mail/Calendar — Nutzer verwenden bestehende Mail-Lösung. | Accepted — ggf. zukünftiges Epic E-10 |
| ADR-04 | **Kein XWiki (Knowledge Management)** | Für die initiale Zielgruppe ist ein dediziertes Wiki nicht prioritär. Nextcloud bietet rudimentäre Kollaboration (Text-App, Markdown). Trade-off: Kein strukturiertes Knowledge Management. | Accepted — ggf. zukünftiges Epic E-11 |
| ADR-05 | **Vaultwarden als Ergänzung (nicht im offiziellen openDesk)** | Vaultwarden adressiert den Bedarf an zentralem Passwort-Management, der im offiziellen openDesk-Stack nicht vorgesehen ist. | Accepted |
| ADR-06 | **Kein globales `userns-remap` im Docker Daemon** | Auf dem Host laufen produktive Container (Nextcloud, Home Assistant, MariaDB u. a.) mit bestehenden Volume-Permissions. Globales User-Namespace-Remapping würde alle UID-Mappings ändern und Volume-Permissions bestehender Container brechen. Kompensation: `no-new-privileges: true` global im Daemon + `cap_drop: ALL` und `security_opt: [no-new-privileges:true]` pro Container (US-005). Trade-off: Kein Kernel-Level UID-Remapping, dafür kein Risiko für Produktiv-Container. | Accepted |
| ADR-07 | **Nextcloud: Migration nach openDesk-Stabilisierung (Option A)** | Die bestehende produktive Nextcloud (Port 8085) wird nach stabilem openDesk-Betrieb in die neue openDesk-Nextcloud migriert und anschließend dekommissioniert. Temporärer Parallelbetrieb bis Migration abgeschlossen. Trade-off: Kurzfristiger Doppelbetrieb, dafür kein Risiko durch gleichzeitigen Umbau. | Accepted |

---

## 2. Technical Constraints (derived from Port & Firewall Report)

| Constraint | Detail |
|---|---|
| Host IP | 192.168.10.20 |
| Subnet | 192.168.10.0/24 |
| Firewall | UFW active — default deny ingress |
| Occupied TCP ports | 22, 53, 80, 443, 631, 1883, 3307, 3389, 3390, 8080–8082, 8085, 8095, 8100, 8123, 18554, 18555 |
| Occupied UDP ports | 53, 67, 137–138, 1900, 4002, 5353, 5683 |
| Docker networks present | 172.17–172.21, 172.23, 172.30.10.x (must not overlap) |
| Ingress (existing) | nginx on 0.0.0.0:80, UFW allows 443/tcp from Anywhere |
| ~~Security Finding~~ | ~~`nextcloud-db-dev` exposes 3307/tcp on 0.0.0.0~~ → Test-Stack entfernt, Port frei ✅ |

### Port Allocation for Open-Desk Stack

> **Regel:** Jeder Service mit Host-Port-Binding MUSS in dieser Tabelle erfasst werden (KS-10).

| Service | Host Binding | Note |
|---|---|---|
| Traefik (HTTPS ingress) | `127.0.0.1:8443` | nginx upstreams to this |
| Traefik (dashboard) | `127.0.0.1:8890` | LAN/admin only, never public |
| Grafana | `127.0.0.1:3000` | LAN only via SSH tunnel |
| Uptime Kuma | `127.0.0.1:3001` | LAN only via SSH tunnel |
| Jitsi Video Bridge (JVB) | `0.0.0.0:10000/udp` | UFW-scoped (see US-018) |
| All other containers | Docker internal networks only | no host-port binding |

### Proposed Docker Networks (isolated, non-overlapping)

| Network | Subnet | Purpose |
|---|---|---|
| `opendesk_frontend` | 172.31.1.0/24 | Traefik ↔ App containers (browser-facing) |
| `opendesk_backend` | 172.31.2.0/24 | Traefik ↔ Keycloak / ForwardAuth / Redis / Loki (KS-01) |
| `opendesk_db` | 172.31.3.0/24 | DB containers only — fully isolated |
| `opendesk_mail` | 172.31.4.0/24 | Mail stack isolation |
| `opendesk_wopi` | 172.31.5.0/24 | Nextcloud ↔ Collabora WOPI-Callbacks (KS-05) |

---

## 3. Architecture Overview

```
Internet / LAN (192.168.10.0/24)
        │
        ▼ :443
   [ UFW / Host ]
        │
        ▼ :80 → :443 redirect + TLS termination (KS-04)
   [ nginx (host) ]
        │
        ▼ :8443 (127.0.0.1 only, Proxy Protocol)
   [ Traefik (container) ]
   (HTTP mode, ForwardAuth, routing, security headers)
   (connected to: opendesk_frontend + opendesk_backend) ← KS-01
        │
        ├── opendesk_frontend network
        │       ├── Nextcloud (files.domain)
        │       ├── Rocket.Chat (chat.domain)
        │       ├── Jitsi Meet (video.domain)
        │       ├── OpenProject (projects.domain)
        │       ├── Vaultwarden (vault.domain)
        │       └── Keycloak (id.domain) ← also on backend
        │
        ├── opendesk_wopi network ← KS-05
        │       ├── Nextcloud (WOPI client)
        │       └── Collabora Online (WOPI host, office.domain via Traefik)
        │
        ├── opendesk_backend network
        │       ├── Keycloak ↔ apps (OIDC/SAML)
        │       ├── traefik-forward-auth (ForwardAuth sidecar)
        │       ├── Redis (session cache)
        │       └── Loki + Promtail (logging)
        │
        └── opendesk_db network (isolated, internal: true)
                ├── PostgreSQL (Keycloak, OpenProject)
                ├── MariaDB (Nextcloud)
                └── MongoDB (Rocket.Chat) ← KS-06
```

**Zero Trust Enforcement Points:**
- Identity: Keycloak SSO (OIDC) — every service authenticates via token
- Network: No inter-network routing between opendesk_db and frontend
- Access: Traefik ForwardAuth middleware — browser-facing requests validated; M2M routes secured via source-IP allowlists (KS-02)
- Secrets: Docker Secrets / `.env` files with restricted permissions (600)
- Audit: Loki/Promtail centralized logging of all access events

---

## 4. Definition of Done (DoD)

A backlog item is **Done** when:
- [ ] Service runs as non-root user inside container
- [ ] No unnecessary host-port bindings (only via Traefik)
- [ ] Host-port bindings (if any) registered in Port Allocation Table (KS-10)
- [ ] Container has `read_only: true` filesystem where applicable
- [ ] Resource limits (`mem_limit`, `cpus`) defined in compose file
- [ ] Service connected only to required Docker networks (least-privilege networking)
- [ ] Environment secrets stored via Docker Secrets or `.env` (not hardcoded)
- [ ] UFW rule added only if strictly required, scoped to minimum source IP
- [ ] Health check (`healthcheck`) defined in compose service
- [ ] Service accessible via Traefik subdomain with valid TLS
- [ ] Keycloak SSO integration verified (where applicable)
- [ ] Basic functional smoke test passed and documented

---

## 5. Epics

| ID | Epic | Priority |
|---|---|---|
| E-01 | Foundation & Security Baseline | Must Have |
| E-02 | Ingress & TLS Layer | Must Have |
| E-03 | Identity & Access Management | Must Have |
| E-04 | Core Office Services | Must Have |
| E-05 | Communication Services | Should Have |
| E-06 | Observability & Logging | Should Have |
| E-07 | Backup & Recovery | Should Have |
| E-08 | Hardening & Compliance | Could Have |
| E-09 | Documentation & Runbooks | Could Have |

---

## 6. Product Backlog Items

---

### EPIC E-01 — Foundation & Security Baseline

---

#### US-001 · Host Security Pre-Check
**As a** system administrator,  
**I want** all known host-level security issues resolved before the stack is deployed,  
**so that** the Open-Desk stack does not inherit existing vulnerabilities.

**Acceptance Criteria:**
- ~~`nextcloud-db-dev` port 3307~~ → Test-Stack komplett entfernt (`docker compose down`), Port 3307 frei ✅
- UFW default policy confirmed: deny incoming, allow outgoing ✅
- Docker daemon configured with `"no-new-privileges": true` in `/etc/docker/daemon.json`
- ~~`userns-remap`~~ → Bewusst nicht umgesetzt, siehe ADR-06. Kompensation über `no-new-privileges` + `cap_drop: ALL` auf Container-Ebene (US-005)
- `auditd` installed and enabled for Docker socket monitoring

**Story Points:** 5  
**Priority:** Must Have  
**Dependencies:** None  

---

#### US-002 · Project Directory Structure
**As a** developer,  
**I want** a clean, versioned project directory layout,  
**so that** all configuration, secrets, and compose files are organized and maintainable.

**Acceptance Criteria:**
- Zwei getrennte Verzeichnisbäume gemäß bestehendem Host-Layout:
  - **Compose & Config:** `~/docker/opendesk/` (Home-Verzeichnis, SSD)
  - **Persistente Daten:** `/mnt/docker-data/opendesk/` (4 TB NVMe)
- Unterverzeichnisse gemäß Struktur unten angelegt
- `secrets/` has permissions `700`, owned by `jo`
- `.gitignore` excludes all files in `secrets/`
- `README.md` in Compose-Root beschreibt beide Pfade und deren Zweck

```
~/docker/opendesk/                     ← Compose & Config (SSD)
├── compose/
│   ├── traefik/
│   ├── keycloak/
│   ├── nextcloud/
│   ├── collabora/
│   ├── rocketchat/
│   ├── jitsi/
│   ├── openproject/
│   ├── vaultwarden/
│   └── observability/
├── config/
├── secrets/          (chmod 700)
├── scripts/
├── docs/
└── docker-compose.yml  (root orchestrator)

/mnt/docker-data/opendesk/             ← Persistente Daten (4 TB NVMe)
├── nextcloud/
├── postgres/
├── mariadb/
├── mongodb/
├── keycloak/
├── rocketchat/
├── vaultwarden/
├── openproject/
├── logs/
└── db-dumps/
```

**Story Points:** 3  
**Priority:** Must Have  
**Dependencies:** US-001  

---

#### US-003 · Docker Network Segmentation
**As a** security engineer,  
**I want** isolated Docker bridge networks per security zone,  
**so that** a compromised container cannot reach database or internal services directly.

**Acceptance Criteria:**
- Networks `opendesk_frontend`, `opendesk_backend`, `opendesk_db`, `opendesk_mail`, `opendesk_wopi` created with fixed subnets (KS-05)
- No container is attached to more networks than required by its function
- Database containers (`opendesk_db`) have no connection to `opendesk_frontend`
- Network config defined in root `docker-compose.yml` with `driver: bridge` and `internal: true` for `opendesk_db` network
- `opendesk_backend`: `internal: false` (Keycloak benötigt ausgehende Konnektivität für OIDC Discovery und ggf. LDAP) — Zugriff über Traefik gesteuert (KS-01)
- `opendesk_wopi`: `internal: true` — reine Container-zu-Container-Kommunikation (KS-05)
- Verified: `docker network inspect opendesk_db` shows no route to internet

**Story Points:** 5  
**Priority:** Must Have  
**Dependencies:** US-002  

---

#### US-004 · Docker Secrets Management
**As a** security engineer,  
**I want** all credentials managed as Docker Secrets or restricted `.env` files,  
**so that** no password or API key is visible in plain text in compose files or image layers.

**Acceptance Criteria:**
- All DB passwords, API keys, and JWT secrets stored as Docker Secrets (file-based)
- Compose files reference secrets via `secrets:` block, not environment variables
- `.env` files (if used) have `chmod 600` and are excluded from version control
- No credentials appear in `docker inspect` container environment output
- Secret rotation procedure documented in `secrets/ROTATION.md`

**Story Points:** 5  
**Priority:** Must Have  
**Dependencies:** US-002  

---

#### US-005 · Container Hardening Baseline
**As a** security engineer,  
**I want** all containers to follow a security hardening baseline,  
**so that** container escape and privilege escalation risks are minimized.

**Acceptance Criteria:**
- All services define `user:` directive (non-root UID, e.g. `1000:1000`) where image supports it
- All services define `read_only: true` where applicable (with `tmpfs` for writable paths)
- All services define `security_opt: [no-new-privileges:true]`
- All services define `cap_drop: [ALL]` and add back only required capabilities
- Resource limits set: `mem_limit`, `cpus` per service
- `restart: unless-stopped` set on all production services

**Story Points:** 8  
**Priority:** Must Have  
**Dependencies:** US-003  

---

#### US-029 · Bestehende Nextcloud: Migrationsentscheidung & Koexistenzstrategie (KS-11)
**As a** system administrator,  
**I want** eine verbindliche Entscheidung über den Umgang mit der bestehenden Nextcloud-Instanz (Port 8085),  
**so that** keine Daten-Fragmentierung, Ressourcenverschwendung oder Nutzerverwirrung durch zwei parallele Nextcloud-Instanzen entsteht.

**Acceptance Criteria:**
- Bestandsaufnahme der bestehenden Nextcloud dokumentiert: Version, Nutzerzahl, Datenvolumen, aktive Apps/Integrationen, DB-Backend (MariaDB auf 3307)
- ~~Drei Optionen evaluiert~~ → **Entscheidung gefallen: Option A — Migration** (siehe ADR-07)
  - **✅ Option A — Migration (gewählt):** openDesk-Nextcloud wird als neue Instanz deployed (US-013). Nach stabilem Betrieb werden Daten und Nutzer von der bestehenden Instanz (Port 8085) migriert. Alte Instanz wird nach erfolgreicher Migration dekommissioniert. Migrationsskript und Rollback-Plan werden im Rahmen der Migration erstellt.
  - ~~Option B — Integration:~~ Verworfen — bestehende Instanz hat eigenen Compose-Stack und eigene DB, Integration in openDesk-Netzwerke wäre aufwändiger als Neumigration.
  - ~~Option C — Parallelbetrieb:~~ Verworfen — Doppelter Wartungsaufwand und Ressourcenverbrauch auf Single-Server nicht sinnvoll.
- Entscheidung dokumentiert als ADR-07 im Backlog (Abschnitt 1a)
- Auswirkungen auf US-013 Acceptance Criteria entsprechend angepasst
- Migrationsrisiken: Bestehende Nextcloud läuft unverändert weiter bis openDesk-Stack stabil. Kein Zeitdruck für Migration.

**Story Points:** 3  
**Priority:** Must Have  
**Dependencies:** US-001  

---

### EPIC E-02 — Ingress & TLS Layer

---

#### US-006 · Traefik Reverse Proxy Setup
**As a** system administrator,  
**I want** Traefik as the central ingress controller for all Open-Desk services,  
**so that** only one port (8443 → forwarded via nginx) is exposed, and all routing is centrally managed.

**Acceptance Criteria:**
- Traefik container deployed, bound to `127.0.0.1:8443` only
- Traefik dashboard bound to `127.0.0.1:8890`, accessible only from LAN via SSH tunnel
- Traefik attached to `opendesk_frontend` AND `opendesk_backend` networks (KS-01)
- Traefik operates in HTTP mode (TLS terminated at nginx) with Proxy Protocol enabled for client-IP transparency (KS-04)
- Access logs and error logs written to `/mnt/docker-data/opendesk/logs/traefik/`
- `docker logs traefik` shows no startup errors

**Story Points:** 5  
**Priority:** Must Have  
**Dependencies:** US-003, US-005  

---

#### US-007 · TLS Certificate Management via Let's Encrypt / Local CA
**As a** system administrator,  
**I want** all Open-Desk subdomains served with valid TLS certificates,  
**so that** all communication is encrypted and browser warnings are eliminated.

**Acceptance Criteria:**
- **TLS-Terminierung erfolgt auf nginx-Ebene** (KS-04): nginx terminiert TLS für alle Open-Desk-Subdomains und leitet via Proxy Protocol an Traefik weiter
- Zertifikate via ACME (Let's Encrypt, DNS-01 Challenge) oder interner CA — Entscheidung dokumentiert in `config/tls/TLS_STRATEGY.md`
- TLS minimum version set to `TLSv1.2`, preferred `TLSv1.3`
- HSTS header enabled (`max-age=31536000; includeSubDomains`)
- Cipher suite restricted to strong ciphers (no RC4, no 3DES)
- Certificate auto-renewal verified and tested

**Story Points:** 8  
**Priority:** Must Have  
**Dependencies:** US-006  

---

#### US-008 · Nginx Host Integration
**As a** system administrator,  
**I want** the existing host nginx to upstream to Traefik for Open-Desk traffic,  
**so that** the existing nginx configuration for other services is not disrupted.

**Acceptance Criteria:**
- Nginx `upstream` block created pointing to `127.0.0.1:8443`
- **Nginx terminiert TLS und aktiviert Proxy Protocol** zum Upstream Traefik (KS-04)
- Server block with `proxy_pass` for Open-Desk domains configured
- `proxy_set_header` includes `X-Real-IP`, `X-Forwarded-For`, `X-Forwarded-Proto`
- Existing nginx vhosts (jozapf.com, Nextcloud on 8085) remain functional
- `nginx -t` passes without errors after change
- UFW rule for `:443` remains as-is (no new rules needed)
- TLS-Terminierungsstrategie dokumentiert in `config/tls/TLS_STRATEGY.md` (KS-04)

**Story Points:** 5  
**Priority:** Must Have  
**Dependencies:** US-006, US-007  

---

#### US-009 · Traefik Middleware Stack (Security Headers + Rate Limiting)
**As a** security engineer,  
**I want** Traefik middleware enforcing security headers and rate limiting on all routes,  
**so that** common web attacks (clickjacking, MIME sniffing, brute force) are mitigated at the proxy layer.

**Acceptance Criteria:**
- Middleware `security-headers` defined with: `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, `Content-Security-Policy` (per service)
- Rate limiting middleware: max 100 req/s per IP, burst 200
- Middleware applied globally as default middleware in Traefik static config
- Headers verified via `curl -I https://files.domain.de`

**Story Points:** 5  
**Priority:** Must Have  
**Dependencies:** US-006  

---

### EPIC E-03 — Identity & Access Management (Zero Trust Core)

---

#### US-010 · Keycloak Identity Provider Deployment
**As a** system administrator,  
**I want** Keycloak deployed as the central identity provider (IdP),  
**so that** all Open-Desk services authenticate users through a single, auditable SSO system (Zero Trust identity layer).

**Acceptance Criteria:**
- Keycloak container deployed on `opendesk_backend` AND `opendesk_frontend` networks (erreichbar via Traefik für Browser-Login, verbunden mit Backend für interne OIDC-Flows)
- Keycloak backed by dedicated PostgreSQL instance on `opendesk_db` network
- Keycloak accessible at `https://id.domain.de` via Traefik
- Admin console accessible only from LAN (Traefik IP whitelist middleware)
- Initial realm `opendesk` created with master realm admin account
- Keycloak runs as non-root user

**Story Points:** 8  
**Priority:** Must Have  
**Dependencies:** US-003, US-006, US-007, US-004 ← KS-08 (US-003 ergänzt)  

---

#### US-011 · Keycloak Realm & Client Configuration
**As a** system administrator,  
**I want** a dedicated Keycloak realm configured with OIDC clients for each Open-Desk service,  
**so that** each application authenticates via standard OIDC/OAuth2 flows.

**Acceptance Criteria:**
- Realm `opendesk` configured with password policy: min 12 chars, complexity, no reuse of last 5
- OIDC clients created for: Nextcloud, Rocket.Chat, Jitsi, OpenProject, Vaultwarden, Traefik ForwardAuth
- Client secrets stored as Docker Secrets
- MFA (TOTP) enabled and enforced for admin roles
- User group `opendesk-users` and `opendesk-admins` created
- Brute force protection enabled (max 5 failed attempts, 30 min lockout)

**Story Points:** 8  
**Priority:** Must Have  
**Dependencies:** US-010  

---

#### US-012 · Traefik ForwardAuth with Keycloak (Zero Trust Enforcement)
**As a** security engineer,  
**I want** Traefik to validate every browser-facing request against Keycloak before forwarding to upstream services,  
**so that** unauthenticated requests never reach application containers (Zero Trust "never trust, always verify").

**Acceptance Criteria:**
- `traefik-forward-auth` (or oauth2-proxy) deployed as sidecar on `opendesk_backend`
- ForwardAuth middleware applied to all **browser-facing** Open-Desk router rules in Traefik (KS-02)
- **M2M/API-Routes ausgenommen:** Collabora WOPI-Callbacks (Source-IP-Allowlist auf `opendesk_wopi` Subnet), Jitsi interne Prosody/JVB-Kommunikation — gesichert via Source-IP-Restriction statt ForwardAuth (KS-02)
- Unauthenticated browser requests redirect to Keycloak login page
- Token expiry and refresh handled transparently
- Verified: direct container URL (bypassing Traefik) is unreachable from host network
- ForwardAuth-Ausnahmen dokumentiert in `config/traefik/FORWARDAUTH_EXCEPTIONS.md` mit Begründung pro Route (KS-02)

**Story Points:** 8  
**Priority:** Must Have  
**Dependencies:** US-009, US-011  

---

### EPIC E-04 — Core Office Services

---

#### US-013 · Nextcloud Deployment (File Storage & Collaboration)
**As a** user,  
**I want** Nextcloud available as the file management and collaboration hub,  
**so that** I can store, share, and co-edit documents within the organization.

**Acceptance Criteria:**
- Nextcloud container deployed on `opendesk_frontend` AND `opendesk_wopi` networks (KS-05)
- MariaDB backend on `opendesk_db` network (no host-port exposure)
- Redis session cache on `opendesk_backend` network
- Nextcloud accessible at `https://files.domain.de`
- Nextcloud SSO configured via Keycloak OIDC (Social Login app)
- `trusted_domains` and `trusted_proxies` configured for Traefik
- Data volume mounted at `/mnt/docker-data/opendesk/nextcloud/`
- Background jobs set to `cron` (separate cron container)
- **Koexistenzstrategie gemäß US-029 umgesetzt** (KS-11): Je nach gewählter Option Migration, Integration oder Parallelbetrieb der bestehenden Nextcloud-Instanz (Port 8085)

**Story Points:** 13  
**Priority:** Must Have  
**Dependencies:** US-029, US-012, US-004 ← KS-11 (US-029 ergänzt)  

---

#### US-014 · Collabora Online (Document Editing Engine)
**As a** user,  
**I want** Collabora Online integrated with Nextcloud,  
**so that** I can open and edit ODF documents (Writer, Calc, Impress) directly in the browser.

**Acceptance Criteria:**
- Collabora Online (CODE) container deployed on `opendesk_wopi` network (für WOPI-Kommunikation mit Nextcloud) UND erreichbar via Traefik auf `opendesk_frontend` (für Browser-Zugang) (KS-05)
- Accessible at `https://office.domain.de`
- Nextcloud `Nextcloud Office` app configured to use `https://office.domain.de`
- WOPI-Traffic isoliert auf `opendesk_wopi` — nur Nextcloud kann Collabora-WOPI-Endpoints erreichen (KS-05)
- Collabora WOPI-Route von ForwardAuth ausgenommen; gesichert via Source-IP-Allowlist auf `opendesk_wopi` Subnet (KS-02)
- Document editing verified for .odt, .ods, .odp formats
- No external calls to Collabora cloud (air-gap compatible)

**Story Points:** 8  
**Priority:** Must Have  
**Dependencies:** US-013  

---

#### US-015 · Vaultwarden (Password & Secrets Management)
**As a** user,  
**I want** Vaultwarden as an on-premises password manager,  
**so that** credentials and secrets are stored securely within the organization's infrastructure.

**Acceptance Criteria:**
- Vaultwarden container deployed on `opendesk_frontend` network
- SQLite or PostgreSQL backend (PostgreSQL preferred for multi-user)
- Accessible at `https://vault.domain.de`
- Admin panel restricted to LAN IPs via Traefik IP allowlist
- SSO via Keycloak configured (Bitwarden SSO compatible)
- Signups disabled (`SIGNUPS_ALLOWED=false`); users invited by admin only
- Emergency access feature evaluated and documented

**Story Points:** 5  
**Priority:** Must Have  
**Dependencies:** US-012  

---

#### US-016 · OpenProject (Project Management)
**As a** project manager,  
**I want** OpenProject available as an on-premises project and task management tool,  
**so that** teams can plan, track, and report on work without using external SaaS tools.

**Acceptance Criteria:**
- OpenProject container (all-in-one or split) deployed
- PostgreSQL backend on `opendesk_db` network
- Accessible at `https://projects.domain.de`
- OIDC SSO via Keycloak configured
- Email notifications configured via SMTP (or local Postfix relay)
- Data volume mounted at `/mnt/docker-data/opendesk/openproject/`

**Story Points:** 8  
**Priority:** Must Have  
**Dependencies:** US-012  

---

### EPIC E-05 — Communication Services

---

#### US-017 · Rocket.Chat (Team Messaging)
**As a** user,  
**I want** Rocket.Chat as an on-premises team chat platform,  
**so that** internal communication does not depend on external services like Slack or Teams.

**Acceptance Criteria:**
- Rocket.Chat container deployed on `opendesk_frontend` network
- MongoDB backend on `opendesk_db` network (no host-port binding) (KS-06)
- Accessible at `https://chat.domain.de`
- OIDC SSO via Keycloak configured
- File uploads stored locally (no S3 external dependency)
- Guest access disabled; registration restricted to SSO only
- Admin account protected by MFA

**Story Points:** 8  
**Priority:** Should Have  
**Dependencies:** US-003, US-012 ← KS-08 (US-003 ergänzt)  

---

#### US-018 · Jitsi Meet (Video Conferencing)
**As a** user,  
**I want** Jitsi Meet available for video calls,  
**so that** video conferencing stays within the organization's infrastructure.

**Acceptance Criteria:**
- Jitsi Meet stack deployed (web, jicofo, prosody, jvb)
- Accessible at `https://video.domain.de`
- JWT authentication enforced (integrated with Keycloak via token)
- Jitsi interne M2M-Routen (Prosody ↔ JVB ↔ Jicofo) von ForwardAuth ausgenommen; gesichert via internes Docker-Netzwerk (KS-02)
- **TURN/STUN-Konfiguration nach Deployment-Modus (KS-09):**
  - **LAN-only:** Interner STUN-Server, Port 10000/UDP in UFW scoped auf LAN (192.168.10.0/24)
  - **Internet-fähig:** Externer TURN-Server (coturn) mit öffentlicher IP oder gehosteter TURN-Service; Port 10000/UDP + TURN-Ports (3478/TCP+UDP, 5349/TCP) in UFW für Anywhere geöffnet
  - Gewählter Modus dokumentiert in `config/jitsi/OFFENTLICHKEIT.md`
- Guest join links require authentication

**Story Points:** 13  
**Priority:** Should Have  
**Dependencies:** US-011  

---

### EPIC E-06 — Observability & Logging

---

#### US-019 · Centralized Logging with Loki + Promtail
**As a** system administrator,  
**I want** all container logs centrally collected and queryable,  
**so that** security incidents and operational issues can be investigated efficiently.

**Acceptance Criteria:**
- Loki container deployed on `opendesk_backend` network (no external exposure)
- Promtail deployed as log collector, configured to scrape all Open-Desk containers
- Grafana deployed at `127.0.0.1:3000` (LAN only via SSH tunnel) — Port in Allocation Table registriert (KS-10)
- Traefik access logs piped into Loki
- Log retention policy set to 30 days
- Failed authentication events from Keycloak visible in Grafana dashboard

**Story Points:** 8  
**Priority:** Should Have  
**Dependencies:** US-003, US-005 ← KS-08 (US-005 ergänzt)  

---

#### US-020 · Health Monitoring with Uptime Kuma
**As a** system administrator,  
**I want** a lightweight status dashboard for all Open-Desk services,  
**so that** service availability is visible at a glance without external monitoring tools.

**Acceptance Criteria:**
- Uptime Kuma deployed at `127.0.0.1:3001` (LAN only) — Port in Allocation Table registriert (KS-10)
- Monitors defined for all Open-Desk services (HTTP/HTTPS checks)
- Alerting configured (email or Rocket.Chat webhook)
- Status page accessible internally at `https://status.domain.de`

**Story Points:** 3  
**Priority:** Should Have  
**Dependencies:** US-013–US-018  

---

### EPIC E-07 — Backup & Recovery

---

#### US-021 · Automated Volume Backup Strategy
**As a** system administrator,  
**I want** automated backups of all persistent data volumes,  
**so that** data can be recovered in case of hardware failure or accidental deletion.

**Acceptance Criteria:**
- Backup script created at `~/docker/opendesk/scripts/backup.sh`
- Backups use `restic` or `borgbackup` with encryption
- **Pre-Backup: Logische Datenbank-Dumps (KS-03):**
  - `pg_dump` für PostgreSQL (Keycloak, OpenProject)
  - `mysqldump` für MariaDB (Nextcloud)
  - `mongodump` für MongoDB (Rocket.Chat) (KS-06)
  - Dumps gespeichert unter `/mnt/docker-data/opendesk/db-dumps/` vor Volume-Backup
- Backup targets: DB-Dump-Verzeichnis + alle Application-Data-Volumes unter `/mnt/docker-data/opendesk/`
- Backup includes Keycloak realm export (JSON)
- Daily full backup, 7-day retention on local target
- Backup job scheduled via `systemd timer` (not cron)
- Restore procedure tested and documented in `RESTORE.md` — inklusive DB-Restore aus Dumps (KS-03)
- Backup success/failure notifications sent via Rocket.Chat or email

**Story Points:** 8  
**Priority:** Should Have  
**Dependencies:** US-013–US-018  

---

#### US-022 · Compose Stack Versioning & Recovery
**As a** developer,  
**I want** all compose files version-controlled and the stack recoverable from scratch,  
**so that** the entire deployment can be rebuilt on a new host within a defined RTO.

**Acceptance Criteria:**
- All compose files committed to a private Git repository
- Sensitive values excluded (Docker Secrets approach ensures this)
- `scripts/deploy.sh` automates initial stack deployment
- RTO (Recovery Time Objective) documented: target < 2 hours from bare Ubuntu
- Runbook for "deploy from zero" tested and validated

**Story Points:** 5  
**Priority:** Should Have  
**Dependencies:** US-002, US-004  

---

### EPIC E-08 — Hardening & Compliance

---

#### US-023 · Fail2ban for SSH and Traefik
**As a** security engineer,  
**I want** Fail2ban monitoring SSH and Traefik access logs,  
**so that** brute force attacks on exposed services are automatically blocked at the host level.

**Acceptance Criteria:**
- Fail2ban installed and active on host
- Jail configured for `sshd` (max 3 attempts, ban 1 hour)
- Jail configured for Traefik access logs (detect 401/403 patterns, ban after 10 fails)
- Banned IPs written to UFW (Fail2ban UFW action)
- Fail2ban status checked via `fail2ban-client status`

**Story Points:** 5  
**Priority:** Could Have  
**Dependencies:** US-001, US-008  

---

#### US-024 · Docker Image Vulnerability Scanning
**As a** security engineer,  
**I want** all Docker images scanned for known CVEs before deployment,  
**so that** vulnerable base images are not run in production.

**Acceptance Criteria:**
- `trivy` installed on host
- Scan script `scripts/scan-images.sh` created
- All Open-Desk images scanned; HIGH/CRITICAL findings documented
- Scans re-run on every image update before deployment
- Findings documented in `SECURITY.md`; accepted risks signed off

**Story Points:** 5  
**Priority:** Could Have  
**Dependencies:** US-002  

---

#### US-025 · Security Headers Audit & CSP Fine-Tuning
**As a** security engineer,  
**I want** all Open-Desk services to achieve an A+ rating on Mozilla Observatory,  
**so that** the stack meets current web security best practices for headers and content policy.

**Acceptance Criteria:**
- All services tested at `observatory.mozilla.org` or equivalent
- A or A+ rating achieved for each service
- Content Security Policy fine-tuned per application (not wildcard `*`)
- Results documented in `SECURITY.md`

**Story Points:** 5  
**Priority:** Could Have  
**Dependencies:** US-009, US-013–US-018  

---

#### US-028 · Container Image Update & Rollback Procedure (KS-07)
**As a** system administrator,  
**I want** a definiertes Verfahren für Container-Image-Updates und Rollbacks,  
**so that** Sicherheitsupdates zeitnah eingespielt werden können, ohne den Stack zu destabilisieren.

**Acceptance Criteria:**
- Update-Verfahren dokumentiert in `~/docker/opendesk/docs/UPDATE_PROCEDURE.md`
- Prozess umfasst: Image-Pull → Trivy-Scan (US-024) → Staging-Test auf gleichem Host (separater Compose-Project-Name) → Production-Swap
- Rollback-Strategie: vorheriges Image-Tag bleibt lokal getagged; `docker-compose up -d --force-recreate` mit vorherigem Tag bei Fehler
- Maintenance-Window-Policy definiert (z. B. Sonntag 02:00–06:00 UTC)
- Update-Log geführt in `logs/updates.log` (Datum, Image, alter Tag, neuer Tag, Ergebnis)
- Automatischer Image-Pull-Check via `scripts/check-updates.sh` (weekly cron/systemd timer) mit Benachrichtigung bei verfügbaren Updates

**Story Points:** 5  
**Priority:** Could Have  
**Dependencies:** US-024, US-022  

---

### EPIC E-09 — Documentation & Runbooks

---

#### US-026 · Architecture Documentation
**As a** developer / future maintainer,  
**I want** complete architecture documentation,  
**so that** the system can be understood and maintained without tribal knowledge.

**Acceptance Criteria:**
- Architecture diagram (network, services, data flows) created (draw.io or Mermaid)
- Port allocation table documented and kept up-to-date
- Each service documented: purpose, image, networks, volumes, env vars, health check
- Document stored in `~/docker/opendesk/docs/ARCHITECTURE.md`

**Story Points:** 5  
**Priority:** Could Have  
**Dependencies:** All E-01 to E-07 items  

---

#### US-027 · User Onboarding Guide
**As an** end user,  
**I want** a simple guide to access and use Open-Desk services,  
**so that** I can get started without requiring administrator support.

**Acceptance Criteria:**
- Guide covers: SSO login, Nextcloud file access, Collabora document editing, Rocket.Chat, Jitsi, OpenProject
- Guide available as PDF and as Nextcloud page
- Guide includes screenshots of key steps
- Available in German and English

**Story Points:** 3  
**Priority:** Could Have  
**Dependencies:** US-013–US-018  

---

## 7. Backlog Summary

| ID | Title | Epic | Points | Priority |
|---|---|---|---|---|
| US-001 | Host Security Pre-Check | E-01 | 5 | Must Have |
| US-002 | Project Directory Structure | E-01 | 3 | Must Have |
| US-003 | Docker Network Segmentation | E-01 | 5 | Must Have |
| US-004 | Docker Secrets Management | E-01 | 5 | Must Have |
| US-005 | Container Hardening Baseline | E-01 | 8 | Must Have |
| US-029 | Nextcloud Migrationsentscheidung (KS-11) | E-01 | 3 | Must Have |
| US-006 | Traefik Reverse Proxy Setup | E-02 | 5 | Must Have |
| US-007 | TLS Certificate Management | E-02 | 8 | Must Have |
| US-008 | Nginx Host Integration | E-02 | 5 | Must Have |
| US-009 | Traefik Middleware Stack | E-02 | 5 | Must Have |
| US-010 | Keycloak Identity Provider | E-03 | 8 | Must Have |
| US-011 | Keycloak Realm & Client Config | E-03 | 8 | Must Have |
| US-012 | Traefik ForwardAuth (Zero Trust) | E-03 | 8 | Must Have |
| US-013 | Nextcloud Deployment | E-04 | 13 | Must Have |
| US-014 | Collabora Online | E-04 | 8 | Must Have |
| US-015 | Vaultwarden | E-04 | 5 | Must Have |
| US-016 | OpenProject | E-04 | 8 | Must Have |
| US-017 | Rocket.Chat | E-05 | 8 | Should Have |
| US-018 | Jitsi Meet | E-05 | 13 | Should Have |
| US-019 | Loki + Promtail + Grafana | E-06 | 8 | Should Have |
| US-020 | Uptime Kuma | E-06 | 3 | Should Have |
| US-021 | Automated Volume Backup | E-07 | 8 | Should Have |
| US-022 | Stack Versioning & Recovery | E-07 | 5 | Should Have |
| US-023 | Fail2ban | E-08 | 5 | Could Have |
| US-024 | Image Vulnerability Scanning | E-08 | 5 | Could Have |
| US-025 | Security Headers Audit | E-08 | 5 | Could Have |
| US-028 | Container Update & Rollback (KS-07) | E-08 | 5 | Could Have |
| US-026 | Architecture Documentation | E-09 | 5 | Could Have |
| US-027 | User Onboarding Guide | E-09 | 3 | Could Have |
| | **Total** | | **193 SP** | |

---

## 8. Suggested Sprint Plan (2-Week Sprints)

| Sprint | Items | Focus | SP |
|---|---|---|---|
| Sprint 1 | US-001–005, US-029 | Foundation & Security Baseline + Nextcloud-Entscheidung (KS-11) | 29 |
| Sprint 2 | US-006–009 | Ingress & TLS | 23 |
| Sprint 3 | US-010–012 | Identity & Zero Trust | 24 |
| Sprint 4 | US-013–014 | Nextcloud + Collabora | 21 |
| Sprint 5 | US-015–016 + US-019 | Vault + OpenProject + Logging | 21 |
| Sprint 6 | US-017–018 | Communication Services | 21 |
| Sprint 7 | US-020–022 | Monitoring + Backup | 16 |
| Sprint 8 | US-023–028 | Hardening + Docs (inkl. US-028 Update/Rollback) | 28 |

---

## 9. Security Risk Register (Zero Trust & Defense in Depth)

| Risk | Threat | Control | Layer |
|---|---|---|---|
| DB exposed on 0.0.0.0 | Lateral movement | Rebind to 127.0.0.1; opendesk_db isolated network | Network |
| Weak passwords | Credential stuffing | Keycloak password policy + MFA + brute-force lockout | Identity |
| Container escape | Privilege escalation | no-new-privileges, non-root user, cap_drop: ALL | Compute |
| Secrets in env vars | Secret exfiltration | Docker Secrets, .env chmod 600 | Secrets |
| Unpatched images | CVE exploitation | trivy scanning, update procedure (US-028), rollback | Supply Chain |
| Traefik misconfiguration | Service exposure | Middleware applied globally, dashboard LAN-only, ForwardAuth exceptions documented (KS-02) | Ingress |
| Log blindness | Undetected breach | Loki/Promtail + Grafana + Fail2ban | Detection |
| No backups | Data loss | Encrypted restic backups + DB-Dumps (KS-03) + restore testing | Resilience |
| Inconsistent DB backup | Data corruption on restore | Pre-backup logical dumps (pg_dump, mysqldump, mongodump) before volume backup (KS-03) | Resilience |
| Uncontrolled updates | Service disruption | Documented update procedure with staging test and rollback (US-028, KS-07) | Operations |

---

## 10. Changelog

| Version | Datum | Änderung |
|---|---|---|
| v1.0 | 2026-02-28 | Initiales Backlog erstellt |
| v1.1 | 2026-02-28 | Review: 10 konzeptionelle Schwachstellen identifiziert und korrigiert (KS-01 bis KS-10). Neues Netzwerk `opendesk_wopi` hinzugefügt, TLS-Terminierungsstrategie definiert, ForwardAuth-Ausnahmen für M2M-Routes, konsistente DB-Dumps im Backup, MongoDB in Architektur aufgenommen, neue US-028 für Update/Rollback, fehlende Dependencies ergänzt, Port-Allocation-Tabelle vervollständigt. Gesamtpunktzahl: 185 → 190 SP. |
| v1.2 | 2026-02-28 | KS-11: Doppelte Nextcloud-Instanz identifiziert — neue US-029 für Migrationsentscheidung, US-013 abhängig von US-029. KS-12: Abweichende Komponentenwahl vs. offizielles openDesk dokumentiert — neuer Abschnitt 1a (ADR-01 bis ADR-05) mit Begründungen für Keycloak statt Nubus, Rocket.Chat statt Element, kein OX/XWiki. Gesamtpunktzahl: 190 → 193 SP. |
| v1.3 | 2026-03-01 | Sprint 1 Fortschritt: US-001 Security Finding erledigt (nextcloud-db-dev entfernt), UFW verifiziert. ADR-06: `userns-remap` bewusst nicht umgesetzt (bestehende Produktiv-Container), Kompensation via Container-Level-Hardening. ADR-07: Nextcloud-Migrationsentscheidung gefallen — Option A (Migration nach openDesk-Stabilisierung), US-029 entsprechend aktualisiert. |
| v1.4 | 2026-03-01 | US-002 angepasst: Verzeichnisstruktur geändert von `/opt/opendesk/` auf zwei getrennte Pfade gemäß bestehendem Host-Layout — Compose & Config unter `~/docker/opendesk/`, persistente Daten unter `/mnt/docker-data/opendesk/` (4 TB NVMe). Alle Pfad-Referenzen in US-006, US-013, US-016, US-021, US-026, US-028 entsprechend aktualisiert. |

---

*Document maintained by: Project Owner / System Administrator CREA-think*  
*Next review: Sprint 1 Kickoff*
