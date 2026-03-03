# CLAUDE.md — Projektregeln für Open-Desk EU

## Projekt

Open-Desk EU ist ein On-Premises-Deployment einer souveränen Office-Suite auf Docker/Compose. Einzelbetrieb (ein Administrator = PO, Dev, Admin). Übungsprojekt mit echtem Homelab-Nutzen, orientiert an IHK-Prüfungsstandards für Fachinformatiker Systemintegration.

## Dateispeicherorte

### Windows (lokaler Entwicklungsrechner)
- **Projektverzeichnis:** `E:\Projects\Open-Desk-EU\`
- Alle Dateien, die Claude via Filesystem-Tool auf Windows ablegt (Compose-Files, Configs, Skripte zum Transfer auf den Server), gehören ausschließlich in dieses Verzeichnis
- Dient als Staging-Bereich für Dateien, die per SCP/WinSCP auf den Server kopiert werden

### Ubuntu-Server (CREA-think, 192.168.10.20)
- **Compose & Config:** `~/docker/opendesk/` (Home-Verzeichnis, SSD)
- **Persistente Daten:** `/mnt/docker-data/opendesk/` (4 TB NVMe)

### Claude-Workspace
- **Backlog, Runbook, CLAUDE.md:** `/workspace/` (Claude-seitig, wird ins Projekt synchronisiert)

## Source of Truth

- **Product Backlog:** `OPEN-DESK_Product_Backlog_v*.md` — immer die höchste Versionsnummer verwenden
- **Port & Firewall Report:** `20260228_CREA-think_port_fw_report.html`
- Bei Widersprüchen zwischen Dokumenten gilt das Backlog

## Regeln bei Dokumentenänderungen

- **Versionspflicht:** Jede inhaltliche Änderung am Backlog bumpt die Version (v1.2 → v1.3 usw.) und wird im Changelog (Section 10) erfasst
- **Keine stille Änderung:** Änderungen an Acceptance Criteria, Dependencies oder Architektur werden dem Nutzer zusammengefasst, bevor sie geschrieben werden
- **Dateiname enthält Version:** `OPEN-DESK_Product_Backlog_v1.3.md` — alte Versionen bleiben als Archiv erhalten

## Architekturentscheidungen (ADR)

Wenn eine Toolwahl, Protokollentscheidung oder Abweichung von der openDesk-Referenzarchitektur getroffen wird: als ADR im Backlog (Abschnitt 1a) dokumentieren. Kurz halten — Entscheidung, Begründung, Trade-off, Status. Kein eigenes Dokument nötig, solange der Backlog-Abschnitt ausreicht.

## Scrum-Konventionen

- **User Stories:** Format "Als [Rolle] will ich [Ziel], damit [Nutzen]" — auch wenn Rolle und Autor dieselbe Person sind
- **Acceptance Criteria:** Prüfbar formuliert. Technische Details sind erlaubt und gewünscht (Einmann-Projekt, kein separates Dev-Team für Refinement)
- **Definition of Done:** Gilt wie im Backlog Section 4 definiert
- **Epics, Stories, Prioritäten (MoSCoW):** Wie im Backlog. Keine Sub-Tasks oder Spikes als eigene Artefakte — zu viel Overhead für Einzelbetrieb
- **Sprint-Länge:** 2 Wochen laut Backlog Section 8

## IHK-Relevanz

Dieses Projekt kann als Grundlage für eine IHK-Projektdokumentation (Fachinformatiker Systemintegration) dienen. Deshalb:

- **Fachbegriffe korrekt verwenden:** Kein Bullshit-Bingo, aber die richtigen Begriffe an den richtigen Stellen (Zero Trust, Defense in Depth, OIDC, TLS-Terminierung, Netzwerksegmentierung usw.)
- **Entscheidungen begründen:** Nicht nur *was*, sondern *warum*. IHK-Prüfer fragen im Fachgespräch nach Alternativen und Trade-offs — genau das liefern die ADRs
- **Wirtschaftlichkeit nicht vergessen:** Wo relevant, Ressourcenverbrauch, Lizenzkosten (= 0 bei Open Source, aber trotzdem benennen) und Betriebsaufwand erwähnen
- **Projektphasen nachvollziehbar:** Planung (Backlog) → Durchführung (Sprints) → Test (Smoke Tests, DoD) → Dokumentation (Architektur, Runbooks)
- **Zeitrahmen IHK:** Projektarbeit max. 40 Stunden. Der Backlog deckt mehr ab — bei Bedarf Scope auf ausgewählte Epics eingrenzen und begründen

## Runbook

Es wird ein Runbook gepflegt (`RUNBOOK.md` im Projektordner), das alle durchgeführten Schritte nachvollziehbar dokumentiert. Jeder Schritt enthält:

- **Was** wurde gemacht (Befehl, Konfigurationsänderung, Entscheidung)
- **Beweis:** Terminal-Ausgabe vom Ubuntu-Host, Screenshot oder relevanter Config-Auszug — copy/paste, nicht umschreiben
- **Ergebnis:** Erfolgreich / Fehlgeschlagen / Anpassung nötig
- **Zeitstempel:** Wann wurde der Schritt durchgeführt
- **Zuordnung:** Welche User Story / welches Acceptance Criterion wird damit erfüllt

Das Runbook dient als Durchführungsnachweis für die IHK-Dokumentation und als Wiederherstellungsanleitung. Wenn Claude Befehle vorschlägt und der Nutzer die Ausgabe liefert, wird das direkt ins Runbook übernommen.

## Sprache

- Dokumentation: Deutsch, technische Begriffe auf Englisch wo üblich (Docker, Compose, TLS, OIDC usw.)
- Code, Konfiguration, Dateinamen: Englisch
- Commit Messages: Englisch

## Docker Compose Namenskonvention

- **Jede Compose-Datei MUSS** ein explizites `name: opendesk-<service>` am Dateianfang haben
- Grund: CREA-think hat bestehende produktive Container. Ohne expliziten Projektnamen leitet Docker Compose den Namen vom Verzeichnis ab, was zu Kollisionen führen kann (Incident: opendesk-nextcloud hat produktive nextcloud-Container überschrieben)
- Alle `container_name:` Werte MÜSSEN mit `opendesk_` prefixed sein

## Was dieses Dokument NICHT regelt

- Keine Code-Style-Guides (kein Anwendungscode in diesem Projekt)
- Keine CI/CD-Pipeline-Regeln (noch nicht im Scope)
- Keine Team-Kommunikationsregeln (Einzelbetrieb)
