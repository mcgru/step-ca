#!/bin/sh
set -e

STEPPATH="${STEPPATH:-/home/step}"
PASSWORD_FILE="${STEPPATH}/secrets/ca-password"

init_ca() {
    echo "==> Initializing CA..."

    mkdir -p "${STEPPATH}/secrets"
    echo "${STEP_CA_PASSWORD}" > "${PASSWORD_FILE}"
    echo "${STEP_PROVISIONER_PASSWORD}" > "${STEPPATH}/secrets/provisioner-password"

    step ca init \
        --name="${STEP_CA_NAME}" \
        --dns="${STEP_CA_DNS}" \
        --address=":8443" \
        --provisioner="${STEP_PROVISIONER_NAME}" \
        --password-file="${PASSWORD_FILE}" \
        --provisioner-password-file="${STEPPATH}/secrets/provisioner-password" \
        --ssh

    echo "==> CA initialized."
}

# ── Init mode ────────────────────────────────────────
if [ "${1}" = "init" ]; then
    init_ca
    exit 0
fi

# ── Passthrough for step CLI ─────────────────────────
if [ $# -gt 0 ]; then
    exec "$@"
fi

# ── Default: auto-init + start CA ────────────────────
if [ ! -f "${STEPPATH}/config/ca.json" ]; then
    init_ca
fi

exec step-ca "${STEPPATH}/config/ca.json" --password-file="${PASSWORD_FILE}"
