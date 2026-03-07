FROM quay.io/keycloak/keycloak:26.5.4 AS builder

# Build-time options — baked into the optimized image
ENV KC_DB=postgres
ENV KC_HEALTH_ENABLED=true
ENV KC_HTTP_ENABLED=true
ENV KC_PROXY_HEADERS=xforwarded

RUN /opt/keycloak/bin/kc.sh build

FROM quay.io/keycloak/keycloak:26.5.4

COPY --from=builder /opt/keycloak/ /opt/keycloak/

# Runtime defaults for optimized mode
ENV KC_HTTP_ENABLED=true
ENV KC_PROXY_HEADERS=xforwarded
ENV KC_HEALTH_ENABLED=true
