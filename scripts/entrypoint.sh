#!/bin/sh
set -e

STEPPATH="${STEPPATH:-/home/step}"
PASSWORD_FILE="${STEPPATH}/secrets/ca-password"
DSN="postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}?sslmode=disable"

wait_postgres() {
    echo "==> Waiting for PostgreSQL..."
    for i in $(seq 30); do
        if pg_isready -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" >/dev/null 2>&1; then
            echo "==> PostgreSQL ready."
            return 0
        fi
        sleep 1
    done
    echo "==> ERROR: PostgreSQL not available after 30s"
    exit 1
}

init_ca() {
    wait_postgres
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
        --ssh \
        --db-type="postgres" \
        --db-dsn="${DSN}"

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
