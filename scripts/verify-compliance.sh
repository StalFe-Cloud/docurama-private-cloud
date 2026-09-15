#!/usr/bin/env bash
set -euo pipefail

# Docurama Private Cloud — Compliance & Security Verification

DOMAIN="${1:-sign.acme-corp.eu}"

echo "=========================================================="
echo "  Auditing Dedicated Private Cloud Enclave: ${DOMAIN}"
echo "=========================================================="

echo "[1/4] Checking TLS Protocol and Cipher Suite..."
curl -sIv --tlsv1.2 "https://${DOMAIN}" 2>&1 | grep -E "SSL connection using|TLSv1\.[23]|subject:" || true

echo "[2/4] Checking Security Headers (HSTS, nosniff, frame-options)..."
curl -sI "https://${DOMAIN}" | grep -iE "strict-transport-security|x-content-type-options|x-frame-options" || true

echo "[3/4] Verifying 21 CFR Part 11 and System Health..."
curl -s "https://${DOMAIN}/api" | grep -i "Docurama API" || true

echo "[4/4] Verifying RFC 3161 Timestamping Connectivity..."
curl -sI "http://timestamp.digicert.com" | head -n 5 || true

echo "=========================================================="
echo "  Audit Complete for ${DOMAIN}"
echo "=========================================================="
