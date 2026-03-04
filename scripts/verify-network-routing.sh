#!/usr/bin/env bash
# =============================================================================
# verify-network-routing.sh — Open-Desk EU
# Verifiziert alle Ports, Routen, DNS, Container-Netzwerke und WOPI-Pfade
# gemäß docs/NETWORK_ROUTING_OVERVIEW.md
#
# Ausführung: bash scripts/verify-network-routing.sh
# Voraussetzung: Auf CREA-think (192.168.10.20) als User jo ausführen
# =============================================================================

set -uo pipefail

# --- Farben ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0
REPORT=""

timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

log_section() {
    local title="$1"
    echo ""
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}  $title${NC}"
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════${NC}"
    REPORT+="\n## $title\n"
}

check_pass() {
    echo -e "  ${GREEN}✅ PASS${NC}  $1"
    REPORT+="- ✅ PASS: $1\n"
    ((PASS++))
}

check_fail() {
    echo -e "  ${RED}❌ FAIL${NC}  $1"
    REPORT+="- ❌ FAIL: $1\n"
    ((FAIL++))
}

check_warn() {
    echo -e "  ${YELLOW}⚠️  WARN${NC}  $1"
    REPORT+="- ⚠️  WARN: $1\n"
    ((WARN++))
}

# =============================================================================
# 1. HOST-PORTS (Abschnitt 2)
# =============================================================================
log_section "1. Host-Ports"

# nginx HTTPS :443
if ss -tlnp 2>/dev/null | grep -q ':443 '; then
    check_pass "Port 443 (nginx TLS) — lauscht"
else
    check_fail "Port 443 (nginx TLS) — nicht erreichbar"
fi

# nginx HTTP :80
if ss -tlnp 2>/dev/null | grep -q ':80 '; then
    check_pass "Port 80 (nginx HTTP→HTTPS) — lauscht"
else
    check_warn "Port 80 (nginx HTTP) — nicht aktiv"
fi

# Traefik :8443
TRAEFIK_BIND=$(ss -tlnp 2>/dev/null | grep ':8443 ' | awk '{print $4}')
if [ -n "$TRAEFIK_BIND" ]; then
    check_pass "Port 8443 (Traefik) — lauscht auf $TRAEFIK_BIND"
    if echo "$TRAEFIK_BIND" | grep -q '127.0.0.1'; then
        check_pass "Port 8443 — nur lokal gebunden (Production-ready)"
    elif echo "$TRAEFIK_BIND" | grep -q '192.168.10.20'; then
        check_warn "Port 8443 — auf LAN-IP gebunden (temporär OK, vor Production ändern!)"
    else
        check_warn "Port 8443 — gebunden auf $TRAEFIK_BIND (unerwartet)"
    fi
else
    check_fail "Port 8443 (Traefik) — lauscht NICHT"
fi

# Traefik Dashboard :8890
DASHBOARD_BIND=$(ss -tlnp 2>/dev/null | grep ':8890 ' | awk '{print $4}')
if [ -n "$DASHBOARD_BIND" ]; then
    if echo "$DASHBOARD_BIND" | grep -q '127.0.0.1'; then
        check_pass "Port 8890 (Dashboard) — nur lokal gebunden"
    else
        check_fail "Port 8890 (Dashboard) — NICHT nur lokal: $DASHBOARD_BIND"
    fi
else
    check_warn "Port 8890 (Dashboard) — nicht aktiv"
fi

# Port 3307 (soll NICHT lauschen)
if ss -tlnp 2>/dev/null | grep -q ':3307 '; then
    check_fail "Port 3307 (nextcloud-db-dev) — LAUSCHT NOCH! Sicherheitsrisiko!"
else
    check_pass "Port 3307 (nextcloud-db-dev) — korrekt geschlossen"
fi

# =============================================================================
# 2. DOCKER-NETZWERKE (Abschnitt 3)
# =============================================================================
log_section "2. Docker-Netzwerke"

declare -A EXPECTED_NETS
EXPECTED_NETS[opendesk_frontend]="172.31.1.0/24|false"
EXPECTED_NETS[opendesk_backend]="172.31.2.0/24|false"
EXPECTED_NETS[opendesk_db]="172.31.3.0/24|true"
EXPECTED_NETS[opendesk_mail]="172.31.4.0/24|false"
EXPECTED_NETS[opendesk_wopi]="172.31.5.0/24|true"

for net in "${!EXPECTED_NETS[@]}"; do
    IFS='|' read -r expected_subnet expected_internal <<< "${EXPECTED_NETS[$net]}"

    if ! docker network inspect "$net" &>/dev/null; then
        check_fail "Netzwerk $net — existiert nicht"
        continue
    fi

    actual_subnet=$(docker network inspect "$net" --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}')
    actual_internal=$(docker network inspect "$net" --format '{{.Internal}}')

    if [ "$actual_subnet" = "$expected_subnet" ]; then
        check_pass "$net — Subnet $actual_subnet"
    else
        check_fail "$net — Subnet ist $actual_subnet, erwartet $expected_subnet"
    fi

    if [ "$actual_internal" = "$expected_internal" ]; then
        check_pass "$net — Internal=$actual_internal"
    else
        check_fail "$net — Internal=$actual_internal, erwartet $expected_internal"
    fi
done

# =============================================================================
# 3. CONTAINER-STATUS + HEALTH (Voraussetzung)
# =============================================================================
log_section "3. Container-Status"

CONTAINERS=(
    opendesk_traefik
    opendesk_keycloak
    opendesk_keycloak_db
    opendesk_nextcloud
    opendesk_nextcloud_db
    opendesk_nextcloud_redis
    opendesk_nextcloud_cron
    opendesk_collabora
)

for c in "${CONTAINERS[@]}"; do
    status=$(docker inspect "$c" --format '{{.State.Status}}' 2>/dev/null || echo "not_found")
    health=$(docker inspect "$c" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' 2>/dev/null || echo "n/a")

    if [ "$status" = "running" ]; then
        if [ "$health" = "healthy" ] || [ "$health" = "no-healthcheck" ]; then
            check_pass "$c — running ($health)"
        else
            check_warn "$c — running aber $health"
        fi
    else
        check_fail "$c — Status: $status"
    fi
done

# =============================================================================
# 4. CONTAINER-NETZWERK-ZUORDNUNG (Abschnitt 5)
# =============================================================================
log_section "4. Container-Netzwerk-Zuordnung"

# Format: container|expected_nets (kommagetrennt)
NET_MAP=(
    "opendesk_traefik|opendesk_frontend,opendesk_backend"
    "opendesk_keycloak|opendesk_frontend,opendesk_backend"
    "opendesk_keycloak_db|opendesk_db"
    "opendesk_nextcloud|opendesk_frontend,opendesk_db,opendesk_wopi"
    "opendesk_nextcloud_db|opendesk_db"
    "opendesk_nextcloud_redis|opendesk_db"
    "opendesk_nextcloud_cron|opendesk_db"
    "opendesk_collabora|opendesk_frontend,opendesk_wopi"
)

for entry in "${NET_MAP[@]}"; do
    IFS='|' read -r container expected_str <<< "$entry"
    IFS=',' read -ra expected_nets <<< "$expected_str"

    actual_nets=$(docker inspect "$container" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null || echo "")

    all_ok=true
    for net in "${expected_nets[@]}"; do
        if echo "$actual_nets" | grep -qw "$net"; then
            : # ok
        else
            check_fail "$container — fehlt in Netzwerk $net"
            all_ok=false
        fi
    done

    if $all_ok; then
        check_pass "$container — korrekt in: ${expected_str//,/, }"
    fi
done

# =============================================================================
# 5. TRAEFIK-ROUTING (Abschnitt 4)
# =============================================================================
log_section "5. Traefik-Routing (Host-Rules)"

TRAEFIK_API="http://127.0.0.1:8890/api"

if ! curl -sf -m 3 "$TRAEFIK_API/overview" &>/dev/null; then
    check_fail "Traefik API auf :8890 nicht erreichbar — Routing-Tests übersprungen"
else
    check_pass "Traefik API erreichbar"

    ROUTERS=$(curl -sf -m 3 "$TRAEFIK_API/http/routers" 2>/dev/null || echo "[]")

    for domain_router in "cloud.sine-math.com|nextcloud" "id.sine-math.com|keycloak" "office.sine-math.com|collabora"; do
        IFS='|' read -r domain router_name <<< "$domain_router"
        if echo "$ROUTERS" | grep -q "$domain"; then
            check_pass "Router $router_name — Host($domain) registriert"
        else
            check_fail "Router $router_name — Host($domain) NICHT in Traefik"
        fi
    done

    MIDDLEWARES=$(curl -sf -m 3 "$TRAEFIK_API/http/middlewares" 2>/dev/null || echo "[]")
    for mw in "default-chain@file" "collabora-chain@file" "security-headers@file" "rate-limit@file"; do
        if echo "$MIDDLEWARES" | grep -q "$mw"; then
            check_pass "Middleware $mw — registriert"
        else
            check_fail "Middleware $mw — NICHT gefunden"
        fi
    done
fi

# =============================================================================
# 6. HTTP-ROUTING END-TO-END (Abschnitt 1)
# =============================================================================
log_section "6. HTTP-Routing End-to-End"

# Via Traefik (intern)
for test in \
    "cloud.sine-math.com|/status.php|200|Nextcloud via Traefik" \
    "id.sine-math.com|/realms/opendesk/.well-known/openid-configuration|200|Keycloak via Traefik" \
    "office.sine-math.com|/hosting/capabilities|200|Collabora via Traefik"
do
    IFS='|' read -r host path expected_code desc <<< "$test"
    actual_code=$(curl -sf -m 5 -o /dev/null -w "%{http_code}" \
        -H "Host: $host" "http://192.168.10.20:8443${path}" 2>/dev/null || echo "000")

    if [ "$actual_code" = "$expected_code" ]; then
        check_pass "$desc — HTTP $actual_code"
    else
        check_fail "$desc — HTTP $actual_code (erwartet $expected_code)"
    fi
done

# Via nginx (TLS, extern)
# Hinweis: id/office.sine-math.com brauchen eigene nginx server-Blöcke
for test in \
    "cloud.sine-math.com|/status.php|200|Nextcloud via nginx+TLS" \
    "id.sine-math.com|/|302|Keycloak via nginx+TLS" \
    "office.sine-math.com|/hosting/capabilities|200|Collabora via nginx+TLS"
do
    IFS='|' read -r host path expected_code desc <<< "$test"
    actual_code=$(curl -skf -m 5 -o /dev/null -w "%{http_code}" \
        "https://${host}${path}" 2>/dev/null || echo "000")

    if [ "$actual_code" = "$expected_code" ]; then
        check_pass "$desc — HTTPS $actual_code"
    elif [ "$actual_code" = "000" ] || [ "$actual_code" = "000000" ]; then
        check_warn "$desc — HTTPS $actual_code (nginx server-Block fehlt?)"
    else
        check_fail "$desc — HTTPS $actual_code (erwartet $expected_code)"
    fi
done

# =============================================================================
# 7. SECURITY HEADERS (Abschnitt 4 Middleware)
# =============================================================================
log_section "7. Security Headers"

NC_HEADERS=$(curl -sf -m 5 -D- -o /dev/null \
    -H "Host: cloud.sine-math.com" "http://192.168.10.20:8443/login" 2>/dev/null || echo "")

for header in "X-Content-Type-Options" "X-Robots-Tag"; do
    if echo "$NC_HEADERS" | grep -qi "$header"; then
        check_pass "Nextcloud — Header $header vorhanden"
    else
        check_fail "Nextcloud — Header $header FEHLT"
    fi
done

# HSTS nur über TLS prüfbar (Traefik sendet HSTS korrekt nur über HTTPS)
HSTS_HEADERS=$(curl -skf -m 5 -D- -o /dev/null "https://cloud.sine-math.com/login" 2>/dev/null || echo "")
if echo "$HSTS_HEADERS" | grep -qi "Strict-Transport-Security"; then
    check_pass "Nextcloud — HSTS vorhanden (via HTTPS)"
elif [ -z "$HSTS_HEADERS" ]; then
    check_warn "Nextcloud — HSTS nicht prüfbar (nginx-TLS nicht erreichbar?)"
else
    check_fail "Nextcloud — HSTS FEHLT in HTTPS-Response"
fi

# Collabora: kein X-Frame-Options DENY
COLL_HEADERS=$(curl -sf -m 5 -D- -o /dev/null \
    -H "Host: office.sine-math.com" "http://192.168.10.20:8443/hosting/capabilities" 2>/dev/null || echo "")

if echo "$COLL_HEADERS" | grep -qi "X-Frame-Options: DENY"; then
    check_fail "Collabora — X-Frame-Options: DENY gesetzt (blockiert iframe!)"
else
    check_pass "Collabora — kein X-Frame-Options: DENY (iframe erlaubt)"
fi

# CSP muss office.sine-math.com enthalten
CSP=$(echo "$NC_HEADERS" | grep -i "content-security-policy" || echo "")
if echo "$CSP" | grep -q "office.sine-math.com"; then
    check_pass "Nextcloud CSP — office.sine-math.com in frame-src"
else
    check_fail "Nextcloud CSP — office.sine-math.com FEHLT (Collabora-iframe blockiert)"
fi

# =============================================================================
# 8. DNS-AUFLÖSUNG IN CONTAINERN (Abschnitt 6)
# =============================================================================
log_section "8. Container-DNS (extra_hosts)"

# Nextcloud → id.sine-math.com
NC_RESOLVE=$(docker exec opendesk_nextcloud getent hosts id.sine-math.com 2>/dev/null | awk '{print $1}')
if [ "$NC_RESOLVE" = "172.31.1.3" ]; then
    check_pass "Nextcloud → id.sine-math.com = 172.31.1.3 (Traefik)"
elif [ -n "$NC_RESOLVE" ]; then
    check_warn "Nextcloud → id.sine-math.com = $NC_RESOLVE (erwartet 172.31.1.3)"
else
    check_fail "Nextcloud → id.sine-math.com — nicht auflösbar"
fi

# Collabora → cloud.sine-math.com
# getent ignoriert /etc/hosts in manchen Containern — grep /etc/hosts direkt
COLL_RESOLVE=$(docker exec opendesk_collabora grep cloud.sine-math.com /etc/hosts 2>/dev/null | awk '{print $1}')
if [ "$COLL_RESOLVE" = "192.168.10.20" ]; then
    check_pass "Collabora → cloud.sine-math.com = 192.168.10.20 in /etc/hosts"
elif [ -n "$COLL_RESOLVE" ]; then
    check_warn "Collabora → cloud.sine-math.com = $COLL_RESOLVE (erwartet 192.168.10.20)"
else
    check_fail "Collabora → cloud.sine-math.com — FEHLT in /etc/hosts"
fi

# =============================================================================
# 9. BACKCHANNEL-KONNEKTIVITÄT (Abschnitt 6/7)
# =============================================================================
log_section "9. Backchannel-Konnektivität"

# Nextcloud → Keycloak (HTTP)
NC_KC=$(docker exec opendesk_nextcloud curl -sf -m 5 -o /dev/null -w "%{http_code}" \
    "http://id.sine-math.com:8443/realms/opendesk/.well-known/openid-configuration" 2>/dev/null || echo "000")
if [ "$NC_KC" = "200" ]; then
    check_pass "Nextcloud → Keycloak Backchannel — HTTP $NC_KC"
else
    check_fail "Nextcloud → Keycloak Backchannel — HTTP $NC_KC (erwartet 200)"
fi

# Collabora → Nextcloud (HTTPS, WOPI-Callback)
COLL_NC=$(docker exec opendesk_collabora curl -skf -m 5 -o /dev/null -w "%{http_code}" \
    "https://cloud.sine-math.com/status.php" 2>/dev/null || echo "000")
if [ "$COLL_NC" = "200" ]; then
    check_pass "Collabora → Nextcloud WOPI-Callback — HTTPS $COLL_NC"
else
    check_fail "Collabora → Nextcloud WOPI-Callback — HTTPS $COLL_NC (erwartet 200)"
fi

# Nextcloud → Collabora (HTTP, Docker-DNS)
NC_COLL=$(docker exec opendesk_nextcloud curl -sf -m 5 -o /dev/null -w "%{http_code}" \
    "http://opendesk_collabora:9980/hosting/capabilities" 2>/dev/null || echo "000")
if [ "$NC_COLL" = "200" ]; then
    check_pass "Nextcloud → Collabora Discovery (intern) — HTTP $NC_COLL"
else
    check_fail "Nextcloud → Collabora Discovery (intern) — HTTP $NC_COLL (erwartet 200)"
fi

# =============================================================================
# 10. WOPI-KONFIGURATION (Abschnitt 7)
# =============================================================================
log_section "10. WOPI-Konfiguration"

WOPI_URL=$(docker exec -u www-data opendesk_nextcloud php occ config:app:get richdocuments wopi_url 2>/dev/null || echo "")
PUBLIC_WOPI=$(docker exec -u www-data opendesk_nextcloud php occ config:app:get richdocuments public_wopi_url 2>/dev/null || echo "")

if [ "$WOPI_URL" = "http://opendesk_collabora:9980" ]; then
    check_pass "wopi_url = $WOPI_URL"
else
    check_fail "wopi_url = '$WOPI_URL' (erwartet http://opendesk_collabora:9980)"
fi

if [ "$PUBLIC_WOPI" = "https://office.sine-math.com" ]; then
    check_pass "public_wopi_url = $PUBLIC_WOPI"
else
    check_fail "public_wopi_url = '$PUBLIC_WOPI' (erwartet https://office.sine-math.com)"
fi

# Discovery-XML
DISCOVERY=$(docker exec opendesk_nextcloud curl -sf -m 5 \
    "http://opendesk_collabora:9980/hosting/discovery" 2>/dev/null | head -c 500)
if echo "$DISCOVERY" | grep -q "office.sine-math.com"; then
    check_pass "Collabora Discovery — URLs zeigen auf office.sine-math.com"
else
    check_fail "Collabora Discovery — office.sine-math.com FEHLT in XML"
fi

# Collabora env vars
ALIAS=$(docker exec opendesk_collabora printenv aliasgroup1 2>/dev/null || echo "")
if [ "$ALIAS" = "https://cloud.sine-math.com:443" ]; then
    check_pass "Collabora aliasgroup1 = $ALIAS"
else
    check_fail "Collabora aliasgroup1 = '$ALIAS' (erwartet https://cloud.sine-math.com:443)"
fi

SNAME=$(docker exec opendesk_collabora printenv server_name 2>/dev/null || echo "")
if [ "$SNAME" = "office.sine-math.com" ]; then
    check_pass "Collabora server_name = $SNAME"
else
    check_fail "Collabora server_name = '$SNAME' (erwartet office.sine-math.com)"
fi

# =============================================================================
# 11. NEXTCLOUD-KONFIGURATION
# =============================================================================
log_section "11. Nextcloud-Konfiguration"

OW_PROTO=$(docker exec -u www-data opendesk_nextcloud php occ config:system:get overwriteprotocol 2>/dev/null || echo "")
if [ "$OW_PROTO" = "https" ]; then
    check_pass "overwriteprotocol = https"
else
    check_fail "overwriteprotocol = '$OW_PROTO' (erwartet https)"
fi

OW_HOST=$(docker exec -u www-data opendesk_nextcloud php occ config:system:get overwritehost 2>/dev/null || echo "")
if [ "$OW_HOST" = "cloud.sine-math.com" ]; then
    check_pass "overwritehost = $OW_HOST"
else
    check_fail "overwritehost = '$OW_HOST' (erwartet cloud.sine-math.com)"
fi

# Redis — Secret nur als root lesbar, daher auth über redis-cli testen
REDIS_OK=$(docker exec opendesk_nextcloud_redis sh -c \
    'redis-cli -a "$(cat /run/secrets/redis_nextcloud_password)" ping 2>/dev/null' \
    2>/dev/null | tr -d '[:space:]')
if [ "$REDIS_OK" = "PONG" ]; then
    check_pass "Redis — authentifizierter PING erfolgreich"
else
    check_fail "Redis — PING fehlgeschlagen ($REDIS_OK)"
fi

# Redis ohne Passwort muss abgelehnt werden
REDIS_NOAUTH=$(docker exec opendesk_nextcloud_redis redis-cli ping 2>/dev/null | tr -d '[:space:]')
if echo "$REDIS_NOAUTH" | grep -qi "NOAUTH\|ERR"; then
    check_pass "Redis — unauthentifizierter Zugriff wird abgelehnt"
else
    check_fail "Redis — unauthentifizierter Zugriff möglich! ($REDIS_NOAUTH)"
fi

# =============================================================================
# 12. TRAEFIK IP-STABILITÄT (Abschnitt 9)
# =============================================================================
log_section "12. Traefik IP-Prüfung"

TRAEFIK_FRONTEND_IP=$(docker inspect opendesk_traefik \
    --format '{{range $k,$v := .NetworkSettings.Networks}}{{if eq $k "opendesk_frontend"}}{{$v.IPAddress}}{{end}}{{end}}' 2>/dev/null)

if [ "$TRAEFIK_FRONTEND_IP" = "172.31.1.3" ]; then
    check_pass "Traefik Frontend-IP = 172.31.1.3 (wie in extra_hosts referenziert)"
else
    check_warn "Traefik Frontend-IP = $TRAEFIK_FRONTEND_IP (extra_hosts erwarten 172.31.1.3!)"
fi

# =============================================================================
# ZUSAMMENFASSUNG
# =============================================================================
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  ERGEBNIS${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${GREEN}PASS:${NC} $PASS"
echo -e "  ${RED}FAIL:${NC} $FAIL"
echo -e "  ${YELLOW}WARN:${NC} $WARN"
echo ""

TOTAL=$((PASS + FAIL + WARN))
echo -e "  Gesamt: $TOTAL Checks | $(timestamp)"

if [ "$FAIL" -eq 0 ]; then
    echo -e "\n  ${GREEN}${BOLD}Alle kritischen Checks bestanden.${NC}"
else
    echo -e "\n  ${RED}${BOLD}$FAIL kritische Fehler gefunden — siehe Details oben.${NC}"
fi

# Report in Datei
REPORT_DIR="$HOME/docker/opendesk/docs"
REPORT_FILE="$REPORT_DIR/verify-network-routing-$(date +%Y%m%d-%H%M%S).md"
mkdir -p "$REPORT_DIR"

{
    echo "# Network & Routing Verification — $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo "PASS: $PASS | FAIL: $FAIL | WARN: $WARN"
    echo ""
    echo -e "$REPORT"
} > "$REPORT_FILE"

echo ""
echo -e "  Report: ${CYAN}$REPORT_FILE${NC}"
echo ""
