#!/bin/sh
set -e

STEPPATH="${STEPPATH:-/home/step}"
PASSWORD_FILE="${STEPPATH}/secrets/ca-password"

# Fix ownership so step user can write to the bind-mounted directory
chown -R step:step "${STEPPATH}" 2>/dev/null || true

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
