#!/bin/sh
set -e

STEPPATH="${STEPPATH:-/home/step}"
PASSWORD_FILE="${STEPPATH}/secrets/ca-password"
NGINX_DIR="/nginx-config"

# Fix ownership so step user can write to bind-mounted directories
chown -R step:step "${STEPPATH}" 2>/dev/null || true

if [ -d "${NGINX_DIR}" ]; then
    chown -R step:step "${NGINX_DIR}" 2>/dev/null || true
fi

init_ca() {
    echo "==> Initializing CA..."

    mkdir -p "${STEPPATH}/secrets"
    echo "${STEP_CA_PASSWORD}" > "${PASSWORD_FILE}"
    echo "${STEP_PROVISIONER_PASSWORD}" > "${STEPPATH}/secrets/provisioner-password"

    su-exec step step ca init \
        --name="${STEP_CA_NAME}" \
        --dns="${STEP_CA_DNS}" \
        --address=":8443" \
        --provisioner="${STEP_PROVISIONER_NAME}" \
        --password-file="${PASSWORD_FILE}" \
        --provisioner-password-file="${STEPPATH}/secrets/provisioner-password" \
        --ssh

    chown -R step:step "${STEPPATH}" 2>/dev/null || true
    echo "==> CA initialized."

    # ── Generate nginx config ──────────────────────────────
    echo "==> Generating nginx config..."

    mkdir -p "${NGINX_DIR}"
    chown -R step:step "${NGINX_DIR}" 2>/dev/null || true

    # Root CA fingerprint
    su-exec step step certificate fingerprint "${STEPPATH}/certs/root_ca.crt" \
        > "${NGINX_DIR}/fingerprint"
    echo "  Fingerprint: $(cat ${NGINX_DIR}/fingerprint)"

    # Client certificate for nginx <-> step-ca mutual TLS
    su-exec step step certificate create "NGINX Client" \
        "${NGINX_DIR}/client.crt" \
        "${NGINX_DIR}/client.key" \
        --ca "${STEPPATH}/certs/intermediate_ca.crt" \
        --ca-key "${STEPPATH}/secrets/intermediate_ca_key" \
        --password-file "${PASSWORD_FILE}" \
        --not-after=87600h

    # Nginx location config
    cat > "${NGINX_DIR}/step-ca.conf" << 'NGINX_EOF'
# Step CA reverse proxy location
# Подключите в ваш server block:  include /path/to/step-ca.conf;

upstream step-ca-backend {
    server 127.0.0.1:8443;
}

# Пример server block (раскомментируйте и настройте под свой домен):
#server {
#    listen 443 ssl http2;
#    server_name DOMAIN_PLACEHOLDER;
#
#    ssl_certificate     /etc/ssl/certs/DOMAIN_PLACEHOLDER.crt;
#    ssl_certificate_key /etc/ssl/private/DOMAIN_PLACEHOLDER.key;
#
#    location / {
#        proxy_pass https://step-ca-backend;
#
#        # Клиентский сертификат для mTLS с step-ca
#        proxy_ssl_certificate     /etc/nginx/ssl/client.crt;
#        proxy_ssl_certificate_key /etc/nginx/ssl/client.key;
#        proxy_ssl_verify          off;
#
#        proxy_set_header Host              $host;
#        proxy_set_header X-Real-IP         $remote_addr;
#        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
#        proxy_set_header X-Forwarded-Proto $scheme;
#
#        proxy_http_version 1.1;
#    }
#}
NGINX_EOF

    # Replace placeholder with actual domain
    sed -i "s/DOMAIN_PLACEHOLDER/${DOMAIN}/g" "${NGINX_DIR}/step-ca.conf"

    chown -R step:step "${NGINX_DIR}" 2>/dev/null || true
    echo "==> Nginx config generated in ${NGINX_DIR}/"
    echo "  - fingerprint"
    echo "  - client.crt / client.key"
    echo "  - step-ca.conf"
}

# ── Init mode ────────────────────────────────────────
if [ "${1}" = "init" ]; then
    init_ca
    exit 0
fi

# ── Passthrough for step CLI ─────────────────────────
if [ $# -gt 0 ]; then
    exec su-exec step "$@"
fi

# ── Default: auto-init + start CA ────────────────────
if [ ! -f "${STEPPATH}/config/ca.json" ]; then
    init_ca
fi

exec su-exec step step-ca "${STEPPATH}/config/ca.json" --password-file="${PASSWORD_FILE}"
