# No-New-Privileges Paradigmenwechsel

## Dokumentversion
| Datum | Autor | Beschreibung |
|-------|-------|-------------|
| 2026-03-04 | Jo | Initiale Dokumentation nach Collabora-Deployment |

## Zusammenfassung

Die Docker-Daemon-Konfiguration wurde von einer globalen `no-new-privileges`-Einstellung auf eine **container-individuelle** Steuerung umgestellt. Auslöser war das Deployment von Collabora Online (CODE), dessen Sicherheitsmodell auf Linux File Capabilities basiert — inkompatibel mit `no-new-privileges`.

## Hintergrund: Was ist no-new-privileges?

`no-new-privileges` ist ein Linux-Kernel-Feature (`PR_SET_NO_NEW_PRIVS`), das verhindert, dass ein Prozess oder dessen Kindprozesse über `execve()` zusätzliche Privilegien erlangen. Konkret blockiert es:

- **SUID/SGID-Binaries:** Programme mit gesetztem Set-UID/GID-Bit können keine erhöhten Rechte erlangen
- **Linux File Capabilities:** Über `setcap` auf Binaries gesetzte Capabilities (z.B. `cap_sys_chroot+ep`) werden ignoriert
- **Ambient Capabilities:** Können nicht über `execve()` hinweg weitergegeben werden

In Docker-Umgebungen ist dies eine wichtige Härtungsmaßnahme, weil es Container-Ausbrüche über privilege escalation erschwert.

## Vorherige Konfiguration

```json
// /etc/docker/daemon.json (bis 2026-03-04)
{
  "no-new-privileges": true,
  "ipv6": false,
  "fixed-cidr-v6": "fd00::/80"
}
```

Diese Einstellung galt **global für alle Container** auf dem Host und konnte auf Container-Ebene **nicht überschrieben** werden — auch nicht mit `security_opt: [no-new-privileges:false]` oder `privileged: true`.

## Warum Collabora das braucht

Collabora Online isoliert jedes geöffnete Dokument in einem eigenen Chroot-Jail. Die Binary `coolforkit-caps` verwendet dazu Linux File Capabilities:

```
/opt/cool/bin/coolforkit-caps = cap_fowner,cap_chown,cap_mknod,cap_sys_chroot+ep
```

Mit `no-new-privileges` werden diese Capabilities beim `exec()` ignoriert → `coolforkit` kann keine Jails erstellen → kein Dokument kann geöffnet werden. Der Fehler manifestiert sich als `CLONE_NEWNS unshare failed (EPERM)`.

## Neue Konfiguration

```json
// /etc/docker/daemon.json (ab 2026-03-04)
{
  "ipv6": false,
  "fixed-cidr-v6": "fd00::/80"
}
```

`no-new-privileges` wird **nicht mehr global** gesetzt, sondern **pro Container** via `security_opt`:

```yaml
# Standard für alle Container (außer Collabora):
security_opt:
  - no-new-privileges:true
```

## Betroffene Container

### Container MIT no-new-privileges (Standard)

Alle OpenDesk-Container setzen `no-new-privileges: true` explizit in ihren Compose-Dateien:

- `opendesk_nextcloud` (+ cron, db, redis)
- `opendesk_keycloak` (+ db)
- `opendesk_traefik`

### Container OHNE no-new-privileges (Ausnahme)

| Container | Begründung | Kompensation |
|-----------|-----------|-------------|
| `opendesk_collabora` | `coolforkit-caps` benötigt File Capabilities für Chroot-Jails | Custom Seccomp-Profil, `cap_drop: ALL` + minimale `cap_add`, Netzwerkisolation (`opendesk_wopi` intern), Memory-Limits |

### Produktionscontainer (Handlungsbedarf)

Die folgenden bestehenden Container auf CREA-think hatten bisher den Schutz über den Daemon. Sie benötigen `security_opt: [no-new-privileges:true]` in ihren jeweiligen Compose-Dateien:

- nextcloud-app, nextcloud-db, nextcloud-redis, nextcloud-cron, nextcloud-nginx (Produktiv-Nextcloud)
- homeassistant
- empc4 Stack (12 Container)
- jozapf.com Stack (3 Container)
- mosquitto, nvme2mqtt

**Status:** Noch nicht umgesetzt. Geplant als separater Hardening-Task.

## Collabora-spezifische Mitigations

Da Collabora ohne `no-new-privileges` laufen muss, werden folgende kompensierende Maßnahmen eingesetzt:

1. **Custom Seccomp-Profil** (`cool-seccomp-profile.json`): Docker-Default + 6 zusätzliche Syscalls (`unshare`, `mount`, `umount2`, `setns`, `clone`, `chroot`). Alle anderen Syscalls bleiben blockiert.

2. **Minimale Capabilities:** `cap_drop: ALL` + nur `SYS_CHROOT`, `FOWNER`, `CHOWN`, `MKNOD`

3. **Netzwerkisolation:** WOPI-Traffic läuft über das interne `opendesk_wopi`-Netzwerk. Kein direkter Zugriff aus dem Internet auf Container-Ports.

4. **Ressourcenlimits:** 1536 MB RAM, 1.0 CPU — begrenzt Auswirkungen bei Kompromittierung

5. **AppArmor:** Aktuell `unconfined` (Collabora-Kompatibilität). TODO: Eigenes AppArmor-Profil erstellen.

## Entscheidungsmatrix: Wann kann no-new-privileges NICHT gesetzt werden?

| Bedingung | no-new-privileges möglich? |
|-----------|---------------------------|
| Container verwendet nur Docker Capabilities (`cap_add`) | **Ja** — Docker Capabilities und File Capabilities sind verschiedene Mechanismen |
| Container hat SUID-Binaries im Image | **Nein** — SUID wird blockiert |
| Container verwendet `setcap`-Binaries (File Capabilities) | **Nein** — File Capabilities werden ignoriert |
| Container braucht Ambient Capabilities über `execve()` | **Nein** — Ambient Capabilities werden gedroppt |

## Lessons Learned

1. **Docker-Daemon-Einstellungen können auf Container-Ebene nicht überschrieben werden.** Auch `privileged: true` hebelt `no-new-privileges` auf Daemon-Ebene nicht aus.

2. **Docker Capabilities ≠ Linux File Capabilities.** `cap_add: [SYS_CHROOT]` in Docker Compose setzt Capabilities auf den Prozess. `setcap cap_sys_chroot+ep /binary` setzt Capabilities auf die Datei. Mit `no-new-privileges` funktioniert nur ersteres.

3. **Immer zuerst die offizielle Dokumentation prüfen.** Collabora dokumentiert das Seccomp-Profil und die File-Capability-Anforderung explizit. Trial-and-Error hätte vermieden werden können.

## Referenzen

- [Collabora Online Docker Documentation](https://sdk.collaboraonline.com/docs/installation/CODE_Docker_image.html)
- [Docker Security: no-new-privileges](https://docs.docker.com/engine/security/#no-new-privileges)
- [Linux man page: prctl PR_SET_NO_NEW_PRIVS](https://man7.org/linux/man-pages/man2/prctl.2.html)
- Seccomp-Profil: `compose/collabora/cool-seccomp-profile.json`
