#!/usr/bin/env bash
set -euo pipefail

# Docurama Private Cloud — Tenant Bootstrap Script
# Automates single-tenant enclave setup with dedicated TLS, PKI, and Docker Compose

TENANT_ID="${1:-acme}"
DOMAIN="${2:-sign.acme-corp.eu}"
DEPLOY_DIR="/opt/docurama-tenants/${TENANT_ID}"

echo "=========================================================="
echo "  Provisioning Dedicated Docurama Enclave: ${TENANT_ID}"
echo "  Target Domain: ${DOMAIN}"
echo "  Path: ${DEPLOY_DIR}"
echo "=========================================================="

mkdir -p "${DEPLOY_DIR}/data/db" "${DEPLOY_DIR}/data/storage" "${DEPLOY_DIR}/data/certs" "${DEPLOY_DIR}/ssl"

# Generate tenant-specific signing key & self-signed root if BYOK not supplied
if [ ! -f "${DEPLOY_DIR}/data/certs/tenant_signing_cert.p12" ]; then
    echo "[*] Generating tenant X.509 private key & certificate..."
    openssl req -x509 -newkey rsa:4096 -keyout "${DEPLOY_DIR}/data/certs/tenant_key.pem" \
        -out "${DEPLOY_DIR}/data/certs/tenant_cert.pem" -days 730 -nodes \
        -subj "/C=FR/ST=Paris/O=${TENANT_ID} Dedicated Signing/CN=${DOMAIN}"
fi

echo "[*] Copying compose definition and configuring environment..."
cp compose/docker-compose.vpc.yml "${DEPLOY_DIR}/docker-compose.yml"
cp compose/nginx.tenant.conf "${DEPLOY_DIR}/nginx.tenant.conf"
sed -e "s/TENANT_ID=\"acme\"/TENANT_ID=\"${TENANT_ID}\"/g" \
    -e "s/DOMAIN=\"sign.acme-corp.eu\"/DOMAIN=\"${DOMAIN}\"/g" \
    compose/.env.tenant.template > "${DEPLOY_DIR}/.env"

echo "[*] Starting tenant container cluster..."
cd "${DEPLOY_DIR}"
docker compose up -d

echo "=========================================================="
echo "  Dedicated Enclave for ${TENANT_ID} is LIVE!"
echo "  URL: https://${DOMAIN}"
echo "=========================================================="
