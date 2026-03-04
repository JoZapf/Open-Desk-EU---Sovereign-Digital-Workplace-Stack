# No-New-Privileges Paradigm Shift

## Document Version
| Date | Author | Description |
|------|--------|-------------|
| 2026-03-04 | — | Initial documentation after Collabora deployment |

## Summary

The Docker daemon configuration was changed from a global `no-new-privileges` setting to **per-container** control. The trigger was the deployment of Collabora Online (CODE), whose security model relies on Linux file capabilities — incompatible with `no-new-privileges`.

## Background: What Is no-new-privileges?

`no-new-privileges` is a Linux kernel feature (`PR_SET_NO_NEW_PRIVS`) that prevents a process or its children from gaining additional privileges via `execve()`. Specifically, it blocks:

- **SUID/SGID binaries:** Programs with set-UID/GID bits cannot acquire elevated rights
- **Linux file capabilities:** Capabilities set on binaries via `setcap` (e.g., `cap_sys_chroot+ep`) are ignored
- **Ambient capabilities:** Cannot be passed across `execve()` boundaries

In Docker environments, this is an important hardening measure because it makes container breakouts via privilege escalation significantly harder.

## Previous Configuration

```json
// /etc/docker/daemon.json (before change)
{
  "no-new-privileges": true,
  "ipv6": false,
  "fixed-cidr-v6": "fd00::/80"
}
```

This setting applied **globally to all containers** on the host and could **not be overridden** at container level — not even with `security_opt: [no-new-privileges:false]` or `privileged: true`.

## Why Collabora Requires This

Collabora Online isolates each open document in its own chroot jail. The binary `coolforkit-caps` uses Linux file capabilities for this:

```
/opt/cool/bin/coolforkit-caps = cap_fowner,cap_chown,cap_mknod,cap_sys_chroot+ep
```

With `no-new-privileges`, these capabilities are ignored on `exec()` → `coolforkit` cannot create jails → no document can be opened. The error manifests as `CLONE_NEWNS unshare failed (EPERM)`.

## New Configuration

```json
// /etc/docker/daemon.json (after change)
{
  "ipv6": false,
  "fixed-cidr-v6": "fd00::/80"
}
```

`no-new-privileges` is **no longer set globally** but **per container** via `security_opt`:

```yaml
# Default for all containers (except Collabora):
security_opt:
  - no-new-privileges:true
```

## Affected Containers

### Containers WITH no-new-privileges (Default)

All OpenDesk containers set `no-new-privileges: true` explicitly in their compose files:

- Nextcloud (+ cron, db, redis)
- Keycloak (+ db)
- Traefik

### Containers WITHOUT no-new-privileges (Exception)

| Container | Reason | Compensation |
|-----------|--------|-------------|
| Collabora | `coolforkit-caps` requires file capabilities for chroot jails | Custom seccomp profile, `cap_drop: ALL` + minimal `cap_add`, network isolation (WOPI network internal), memory limits |

### Pre-Existing Production Containers (Action Required)

Any containers that previously relied on the daemon-level `no-new-privileges` setting now need `security_opt: [no-new-privileges:true]` added to their respective compose files.

**Status:** Not yet implemented. Planned as a separate hardening task.

## Collabora-Specific Mitigations

Since Collabora must run without `no-new-privileges`, the following compensating controls are in place:

1. **Custom seccomp profile** (`cool-seccomp-profile.json`): Docker default + 6 additional syscalls (`unshare`, `mount`, `umount2`, `setns`, `clone`, `chroot`). All other syscalls remain blocked.

2. **Minimal capabilities:** `cap_drop: ALL` + only `SYS_CHROOT`, `FOWNER`, `CHOWN`, `MKNOD`

3. **Network isolation:** WOPI traffic runs on the internal WOPI network. No direct internet access to container ports.

4. **Resource limits:** 1536 MB RAM, 1.0 CPU — limits blast radius in case of compromise.

5. **AppArmor:** Currently `unconfined` (Collabora compatibility). TODO: Create a dedicated AppArmor profile.

## Decision Matrix: When Can no-new-privileges NOT Be Set?

| Condition | no-new-privileges possible? |
|-----------|---------------------------|
| Container uses only Docker capabilities (`cap_add`) | **Yes** — Docker capabilities and file capabilities are different mechanisms |
| Container image contains SUID binaries | **No** — SUID is blocked |
| Container uses `setcap` binaries (file capabilities) | **No** — File capabilities are ignored |
| Container requires ambient capabilities across `execve()` | **No** — Ambient capabilities are dropped |

## Lessons Learned

1. **Docker daemon settings cannot be overridden at container level.** Even `privileged: true` does not override daemon-level `no-new-privileges`.

2. **Docker capabilities ≠ Linux file capabilities.** `cap_add: [SYS_CHROOT]` in Docker Compose sets capabilities on the process. `setcap cap_sys_chroot+ep /binary` sets capabilities on the file. With `no-new-privileges`, only the former works.

3. **Always check the official documentation first.** Collabora explicitly documents the seccomp profile and file capability requirements. Trial-and-error could have been avoided.

## References

- [Collabora Online Docker Documentation](https://sdk.collaboraonline.com/docs/installation/CODE_Docker_image.html)
- [Docker Security: no-new-privileges](https://docs.docker.com/engine/security/#no-new-privileges)
- [Linux man page: prctl PR_SET_NO_NEW_PRIVS](https://man7.org/linux/man-pages/man2/prctl.2.html)
- Seccomp profile: `compose/collabora/cool-seccomp-profile.json`
