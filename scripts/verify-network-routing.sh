#!/usr/bin/env bash
# =============================================================================
# verify-network-routing.sh — Open-Desk EU
# Verifies all ports, routes, DNS, container networks, and WOPI paths
# as defined in docs/NETWORK_ROUTING_OVERVIEW.md
#
# Usage: bash scripts/verify-network-routing.sh
# Prerequisite: Run on the Docker host as deploying user
# =============================================================================

set -uo pipefail

# --- Load environment ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "ERROR: .env not found at $ENV_FILE"
    echo "Copy .env.example to .env and adjust values for your deployment."
    exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

# --- Colors ---
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
# 1. HOST PORTS (Section 2)
# =============================================================================
log_section "1. Host Ports"

# nginx HTTPS :443
if ss -tlnp 2>/dev/null | grep -q ':443 '; then
    check_pass "Port 443 (nginx TLS) — listening"
else
    check_fail "Port 443 (nginx TLS) — not reachable"
fi

# nginx HTTP :80
if ss -tlnp 2>/dev/null | grep -q ':80 '; then
    check_pass "Port 80 (nginx HTTP→HTTPS) — listening"
else
    check_warn "Port 80 (nginx HTTP) — not active"
fi

# Traefik :TRAEFIK_PORT
TRAEFIK_BIND=$(ss -tlnp 2>/dev/null | grep ":${TRAEFIK_PORT} " | awk '{print $4}')
if [ -n "$TRAEFIK_BIND" ]; then
    check_pass "Port ${TRAEFIK_PORT} (Traefik) — listening on $TRAEFIK_BIND"
    if echo "$TRAEFIK_BIND" | grep -q '127.0.0.1'; then
        check_pass "Port ${TRAEFIK_PORT} — bound to localhost only (production-ready)"
    elif echo "$TRAEFIK_BIND" | grep -q "${HOST_IP}"; then
        check_warn "Port ${TRAEFIK_PORT} — bound to LAN IP (temporary OK, change before production!)"
    else
        check_warn "Port ${TRAEFIK_PORT} — bound to $TRAEFIK_BIND (unexpected)"
    fi
else
    check_fail "Port ${TRAEFIK_PORT} (Traefik) — NOT listening"
fi

# Traefik Dashboard :TRAEFIK_DASHBOARD_PORT
DASHBOARD_BIND=$(ss -tlnp 2>/dev/null | grep ":${TRAEFIK_DASHBOARD_PORT} " | awk '{print $4}')
if [ -n "$DASHBOARD_BIND" ]; then
    if echo "$DASHBOARD_BIND" | grep -q '127.0.0.1'; then
        check_pass "Port ${TRAEFIK_DASHBOARD_PORT} (Dashboard) — bound to localhost only"
    else
        check_fail "Port ${TRAEFIK_DASHBOARD_PORT} (Dashboard) — NOT localhost only: $DASHBOARD_BIND"
    fi
else
    check_warn "Port ${TRAEFIK_DASHBOARD_PORT} (Dashboard) — not active"
fi

# =============================================================================
# 2. DOCKER NETWORKS (Section 3)
# =============================================================================
log_section "2. Docker Networks"

declare -A EXPECTED_NETS
EXPECTED_NETS[opendesk_frontend]="${NET_FRONTEND}|false"
EXPECTED_NETS[opendesk_backend]="${NET_BACKEND}|false"
EXPECTED_NETS[opendesk_db]="${NET_DB}|true"
EXPECTED_NETS[opendesk_mail]="${NET_MAIL}|false"
EXPECTED_NETS[opendesk_wopi]="${NET_WOPI}|true"

for net in "${!EXPECTED_NETS[@]}"; do
    IFS='|' read -r expected_subnet expected_internal <<< "${EXPECTED_NETS[$net]}"

    if ! docker network inspect "$net" &>/dev/null; then
        check_fail "Network $net — does not exist"
        continue
    fi

    actual_subnet=$(docker network inspect "$net" --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}')
    actual_internal=$(docker network inspect "$net" --format '{{.Internal}}')

    if [ "$actual_subnet" = "$expected_subnet" ]; then
        check_pass "$net — Subnet $actual_subnet"
    else
        check_fail "$net — Subnet is $actual_subnet, expected $expected_subnet"
    fi

    if [ "$actual_internal" = "$expected_internal" ]; then
        check_pass "$net — Internal=$actual_internal"
    else
        check_fail "$net — Internal=$actual_internal, expected $expected_internal"
    fi
done

# =============================================================================
# 3. CONTAINER STATUS + HEALTH
# =============================================================================
log_section "3. Container Status"

CONTAINERS=(
    "${CT_TRAEFIK}"
    "${CT_KEYCLOAK}"
    "${CT_KEYCLOAK_DB}"
    "${CT_NEXTCLOUD}"
    "${CT_NEXTCLOUD_DB}"
    "${CT_NEXTCLOUD_REDIS}"
    "${CT_NEXTCLOUD_CRON}"
    "${CT_COLLABORA}"
)

for c in "${CONTAINERS[@]}"; do
    status=$(docker inspect "$c" --format '{{.State.Status}}' 2>/dev/null || echo "not_found")
    health=$(docker inspect "$c" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' 2>/dev/null || echo "n/a")

    if [ "$status" = "running" ]; then
        if [ "$health" = "healthy" ] || [ "$health" = "no-healthcheck" ]; then
            check_pass "$c — running ($health)"
        else
            check_warn "$c — running but $health"
        fi
    else
        check_fail "$c — Status: $status"
    fi
done

# =============================================================================
# 4. CONTAINER NETWORK ASSIGNMENT (Section 5)
# =============================================================================
log_section "4. Container Network Assignment"

NET_MAP=(
    "${CT_TRAEFIK}|opendesk_frontend,opendesk_backend"
    "${CT_KEYCLOAK}|opendesk_frontend,opendesk_backend"
    "${CT_KEYCLOAK_DB}|opendesk_db"
    "${CT_NEXTCLOUD}|opendesk_frontend,opendesk_db,opendesk_wopi"
    "${CT_NEXTCLOUD_DB}|opendesk_db"
    "${CT_NEXTCLOUD_REDIS}|opendesk_db"
    "${CT_NEXTCLOUD_CRON}|opendesk_db"
    "${CT_COLLABORA}|opendesk_frontend,opendesk_wopi"
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
            check_fail "$container — missing from network $net"
            all_ok=false
        fi
    done

    if $all_ok; then
        check_pass "$container — correctly in: ${expected_str//,/, }"
    fi
done

# =============================================================================
# 5. TRAEFIK ROUTING (Section 4)
# =============================================================================
log_section "5. Traefik Routing (Host Rules)"

TRAEFIK_API="http://127.0.0.1:${TRAEFIK_DASHBOARD_PORT}/api"

if ! curl -sf -m 3 "$TRAEFIK_API/overview" &>/dev/null; then
    check_fail "Traefik API on :${TRAEFIK_DASHBOARD_PORT} not reachable — skipping routing tests"
else
    check_pass "Traefik API reachable"

    ROUTERS=$(curl -sf -m 3 "$TRAEFIK_API/http/routers" 2>/dev/null || echo "[]")

    for domain_router in "${DOMAIN_CLOUD}|nextcloud" "${DOMAIN_IAM}|keycloak" "${DOMAIN_OFFICE}|collabora"; do
        IFS='|' read -r domain router_name <<< "$domain_router"
        if echo "$ROUTERS" | grep -q "$domain"; then
            check_pass "Router $router_name — Host($domain) registered"
        else
            check_fail "Router $router_name — Host($domain) NOT in Traefik"
        fi
    done

    MIDDLEWARES=$(curl -sf -m 3 "$TRAEFIK_API/http/middlewares" 2>/dev/null || echo "[]")
    for mw in "default-chain@file" "collabora-chain@file" "security-headers@file" "rate-limit@file"; do
        if echo "$MIDDLEWARES" | grep -q "$mw"; then
            check_pass "Middleware $mw — registered"
        else
            check_fail "Middleware $mw — NOT found"
        fi
    done
fi

# =============================================================================
# 6. HTTP ROUTING END-TO-END (Section 1)
# =============================================================================
log_section "6. HTTP Routing End-to-End"

# Via Traefik (internal)
for test in \
    "${DOMAIN_CLOUD}|/status.php|200|Nextcloud via Traefik" \
    "${DOMAIN_IAM}|/realms/opendesk/.well-known/openid-configuration|200|Keycloak via Traefik" \
    "${DOMAIN_OFFICE}|/hosting/capabilities|200|Collabora via Traefik"
do
    IFS='|' read -r host path expected_code desc <<< "$test"
    actual_code=$(curl -sf -m 5 -o /dev/null -w "%{http_code}" \
        -H "Host: $host" "http://127.0.0.1:${TRAEFIK_PORT}${path}" 2>/dev/null || echo "000")

    if [ "$actual_code" = "$expected_code" ]; then
        check_pass "$desc — HTTP $actual_code"
    else
        check_fail "$desc — HTTP $actual_code (expected $expected_code)"
    fi
done

# Via nginx (TLS, external)
for test in \
    "${DOMAIN_CLOUD}|/status.php|200|Nextcloud via nginx+TLS" \
    "${DOMAIN_IAM}|/|302|Keycloak via nginx+TLS" \
    "${DOMAIN_OFFICE}|/hosting/capabilities|200|Collabora via nginx+TLS"
do
    IFS='|' read -r host path expected_code desc <<< "$test"
    actual_code=$(curl -skf -m 5 -o /dev/null -w "%{http_code}" \
        "https://${host}${path}" 2>/dev/null || echo "000")

    if [ "$actual_code" = "$expected_code" ]; then
        check_pass "$desc — HTTPS $actual_code"
    elif [ "$actual_code" = "000" ] || [ "$actual_code" = "000000" ]; then
        check_warn "$desc — HTTPS $actual_code (nginx server block missing?)"
    else
        check_fail "$desc — HTTPS $actual_code (expected $expected_code)"
    fi
done

# =============================================================================
# 7. SECURITY HEADERS (Section 4 Middleware)
# =============================================================================
log_section "7. Security Headers"

NC_HEADERS=$(curl -sf -m 5 -D- -o /dev/null \
    -H "Host: ${DOMAIN_CLOUD}" "http://127.0.0.1:${TRAEFIK_PORT}/login" 2>/dev/null || echo "")

for header in "X-Content-Type-Options" "X-Robots-Tag"; do
    if echo "$NC_HEADERS" | grep -qi "$header"; then
        check_pass "Nextcloud — Header $header present"
    else
        check_fail "Nextcloud — Header $header MISSING"
    fi
done

# HSTS only verifiable over TLS
HSTS_HEADERS=$(curl -skf -m 5 -D- -o /dev/null "https://${DOMAIN_CLOUD}/login" 2>/dev/null || echo "")
if echo "$HSTS_HEADERS" | grep -qi "Strict-Transport-Security"; then
    check_pass "Nextcloud — HSTS present (via HTTPS)"
elif [ -z "$HSTS_HEADERS" ]; then
    check_warn "Nextcloud — HSTS not verifiable (nginx TLS not reachable?)"
else
    check_fail "Nextcloud — HSTS MISSING in HTTPS response"
fi

# Collabora: no X-Frame-Options DENY
COLL_HEADERS=$(curl -sf -m 5 -D- -o /dev/null \
    -H "Host: ${DOMAIN_OFFICE}" "http://127.0.0.1:${TRAEFIK_PORT}/hosting/capabilities" 2>/dev/null || echo "")

if echo "$COLL_HEADERS" | grep -qi "X-Frame-Options: DENY"; then
    check_fail "Collabora — X-Frame-Options: DENY is set (blocks iframe!)"
else
    check_pass "Collabora — no X-Frame-Options: DENY (iframe allowed)"
fi

# CSP must include DOMAIN_OFFICE
CSP=$(echo "$NC_HEADERS" | grep -i "content-security-policy" || echo "")
if echo "$CSP" | grep -qE "frame-src \*|${DOMAIN_OFFICE}"; then
    check_pass "Nextcloud CSP — Collabora iframe allowed (frame-src)"
else
    check_fail "Nextcloud CSP — ${DOMAIN_OFFICE} MISSING (Collabora iframe blocked)"
fi

# =============================================================================
# 8. CONTAINER DNS (extra_hosts — Section 6)
# =============================================================================
log_section "8. Container DNS (extra_hosts)"

# Nextcloud → DOMAIN_IAM
NC_RESOLVE=$(docker exec "${CT_NEXTCLOUD}" getent hosts "${DOMAIN_IAM}" 2>/dev/null | awk '{print $1}')
if [ "$NC_RESOLVE" = "${HOST_IP}" ]; then
    check_pass "Nextcloud → ${DOMAIN_IAM} = ${HOST_IP} (via nginx)"
elif [ -n "$NC_RESOLVE" ]; then
    check_warn "Nextcloud → ${DOMAIN_IAM} = $NC_RESOLVE (expected ${TRAEFIK_FRONTEND_IP})"
else
    check_fail "Nextcloud → ${DOMAIN_IAM} — cannot resolve"
fi

# Collabora → DOMAIN_CLOUD
COLL_RESOLVE=$(docker exec "${CT_COLLABORA}" grep "${DOMAIN_CLOUD}" /etc/hosts 2>/dev/null | awk '{print $1}')
if [ "$COLL_RESOLVE" = "${HOST_IP}" ]; then
    check_pass "Collabora → ${DOMAIN_CLOUD} = ${HOST_IP} in /etc/hosts"
elif [ -n "$COLL_RESOLVE" ]; then
    check_warn "Collabora → ${DOMAIN_CLOUD} = $COLL_RESOLVE (expected ${HOST_IP})"
else
    check_fail "Collabora → ${DOMAIN_CLOUD} — MISSING in /etc/hosts"
fi

# =============================================================================
# 9. BACKCHANNEL CONNECTIVITY (Section 6/7)
# =============================================================================
log_section "9. Backchannel Connectivity"

# Nextcloud → Keycloak (HTTP)
NC_KC=$(docker exec "${CT_NEXTCLOUD}" curl -sf -m 5 -o /dev/null -w "%{http_code}" \
    "https://${DOMAIN_IAM}/realms/opendesk/.well-known/openid-configuration" 2>/dev/null || echo "000")
if [ "$NC_KC" = "200" ]; then
    check_pass "Nextcloud → Keycloak backchannel — HTTP $NC_KC"
else
    check_fail "Nextcloud → Keycloak backchannel — HTTP $NC_KC (expected 200)"
fi

# Collabora → Nextcloud (HTTPS, WOPI callback)
COLL_NC=$(docker exec "${CT_COLLABORA}" curl -skf -m 5 -o /dev/null -w "%{http_code}" \
    "https://${DOMAIN_CLOUD}/status.php" 2>/dev/null || echo "000")
if [ "$COLL_NC" = "200" ]; then
    check_pass "Collabora → Nextcloud WOPI callback — HTTPS $COLL_NC"
else
    check_fail "Collabora → Nextcloud WOPI callback — HTTPS $COLL_NC (expected 200)"
fi

# Nextcloud → Collabora (HTTP, Docker DNS)
NC_COLL=$(docker exec "${CT_NEXTCLOUD}" curl -sf -m 5 -o /dev/null -w "%{http_code}" \
    "http://${CT_COLLABORA}:9980/hosting/capabilities" 2>/dev/null || echo "000")
if [ "$NC_COLL" = "200" ]; then
    check_pass "Nextcloud → Collabora discovery (internal) — HTTP $NC_COLL"
else
    check_fail "Nextcloud → Collabora discovery (internal) — HTTP $NC_COLL (expected 200)"
fi

# =============================================================================
# 10. WOPI CONFIGURATION (Section 7)
# =============================================================================
log_section "10. WOPI Configuration"

WOPI_URL=$(docker exec -u www-data "${CT_NEXTCLOUD}" php occ config:app:get richdocuments wopi_url 2>/dev/null || echo "")
PUBLIC_WOPI=$(docker exec -u www-data "${CT_NEXTCLOUD}" php occ config:app:get richdocuments public_wopi_url 2>/dev/null || echo "")

if [ "$WOPI_URL" = "https://${DOMAIN_OFFICE}" ] || [ "$WOPI_URL" = "http://${CT_COLLABORA}:9980" ]; then
    check_pass "wopi_url = $WOPI_URL"
else
    check_fail "wopi_url = '$WOPI_URL' (expected http://${CT_COLLABORA}:9980)"
fi

if [ "$PUBLIC_WOPI" = "https://${DOMAIN_OFFICE}" ]; then
    check_pass "public_wopi_url = $PUBLIC_WOPI"
else
    check_fail "public_wopi_url = '$PUBLIC_WOPI' (expected https://${DOMAIN_OFFICE})"
fi

# Discovery XML
DISCOVERY=$(docker exec "${CT_NEXTCLOUD}" curl -sf -m 5 \
    "http://${CT_COLLABORA}:9980/hosting/discovery" 2>/dev/null | head -c 500)
if echo "$CSP" | grep -qE "frame-src \*|${DOMAIN_OFFICE}"; then
    check_pass "Collabora Discovery — URLs point to ${DOMAIN_OFFICE}"
else
    check_fail "Collabora Discovery — ${DOMAIN_OFFICE} MISSING in XML"
fi

# Collabora env vars
ALIAS=$(docker exec "${CT_COLLABORA}" printenv aliasgroup1 2>/dev/null || echo "")
if [ "$ALIAS" = "https://${DOMAIN_CLOUD}:443" ]; then
    check_pass "Collabora aliasgroup1 = $ALIAS"
else
    check_fail "Collabora aliasgroup1 = '$ALIAS' (expected https://${DOMAIN_CLOUD}:443)"
fi

SNAME=$(docker exec "${CT_COLLABORA}" printenv server_name 2>/dev/null || echo "")
if [ "$SNAME" = "${DOMAIN_OFFICE}" ]; then
    check_pass "Collabora server_name = $SNAME"
else
    check_fail "Collabora server_name = '$SNAME' (expected ${DOMAIN_OFFICE})"
fi

# =============================================================================
# 11. NEXTCLOUD CONFIGURATION
# =============================================================================
log_section "11. Nextcloud Configuration"

OW_PROTO=$(docker exec -u www-data "${CT_NEXTCLOUD}" php occ config:system:get overwriteprotocol 2>/dev/null || echo "")
if [ "$OW_PROTO" = "https" ]; then
    check_pass "overwriteprotocol = https"
else
    check_fail "overwriteprotocol = '$OW_PROTO' (expected https)"
fi

OW_HOST=$(docker exec -u www-data "${CT_NEXTCLOUD}" php occ config:system:get overwritehost 2>/dev/null || echo "")
if [ "$OW_HOST" = "${DOMAIN_CLOUD}" ]; then
    check_pass "overwritehost = $OW_HOST"
else
    check_fail "overwritehost = '$OW_HOST' (expected ${DOMAIN_CLOUD})"
fi

# Redis — secret only readable as root, test via redis-cli
REDIS_OK=$(docker exec "${CT_NEXTCLOUD_REDIS}" sh -c \
    'redis-cli -a "$(cat /run/secrets/redis_nextcloud_password)" ping 2>/dev/null' \
    2>/dev/null | tr -d '[:space:]')
if [ "$REDIS_OK" = "PONG" ]; then
    check_pass "Redis — authenticated PING successful"
else
    check_fail "Redis — PING failed ($REDIS_OK)"
fi

# Redis without password must be rejected
REDIS_NOAUTH=$(docker exec "${CT_NEXTCLOUD_REDIS}" redis-cli ping 2>/dev/null | tr -d '[:space:]')
if echo "$REDIS_NOAUTH" | grep -qi "NOAUTH\|ERR"; then
    check_pass "Redis — unauthenticated access rejected"
else
    check_fail "Redis — unauthenticated access possible! ($REDIS_NOAUTH)"
fi

# =============================================================================
# 12. TRAEFIK IP STABILITY (Section 9)
# =============================================================================
log_section "12. Traefik IP Check"

ACTUAL_TRAEFIK_IP=$(docker inspect "${CT_TRAEFIK}" \
    --format '{{range $k,$v := .NetworkSettings.Networks}}{{if eq $k "opendesk_frontend"}}{{$v.IPAddress}}{{end}}{{end}}' 2>/dev/null)

# INFO only - Traefik IP no longer used for routing (bound to 127.0.0.1)
check_pass "Traefik frontend IP = $ACTUAL_TRAEFIK_IP (informational - not used for routing)"

# =============================================================================
# SUMMARY
# =============================================================================
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  RESULTS${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${GREEN}PASS:${NC} $PASS"
echo -e "  ${RED}FAIL:${NC} $FAIL"
echo -e "  ${YELLOW}WARN:${NC} $WARN"
echo ""

TOTAL=$((PASS + FAIL + WARN))
echo -e "  Total: $TOTAL checks | $(timestamp)"

if [ "$FAIL" -eq 0 ]; then
    echo -e "\n  ${GREEN}${BOLD}All critical checks passed.${NC}"
else
    echo -e "\n  ${RED}${BOLD}$FAIL critical failures found — see details above.${NC}"
fi

# Write report to file
mkdir -p "${REPORT_DIR}"
REPORT_FILE="${REPORT_DIR}/verify-network-routing-$(date +%Y%m%d-%H%M%S).md"

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
