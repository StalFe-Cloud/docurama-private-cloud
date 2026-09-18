#!/usr/bin/env bash
set -euo pipefail

# Docurama Private Cloud — Compliance & Security Verification

DOMAIN="${1:-sign.acme-corp.eu}"

echo "=========================================================="
echo "  Auditing Dedicated Private Cloud Enclave: ${DOMAIN}"
echo "=========================================================="

echo "[1/5] Checking TLS Protocol and Cipher Suite..."
curl -sIv --tlsv1.2 "https://${DOMAIN}" 2>&1 | grep -E "SSL connection using|TLSv1\.[23]|subject:" || true

echo "[2/5] Checking Security Headers (HSTS, nosniff, frame-options)..."
curl -sI "https://${DOMAIN}" | grep -iE "strict-transport-security|x-content-type-options|x-frame-options" || true

echo "[3/5] Verifying System Health & Storage Posture (/api/health)..."
curl -s "https://${DOMAIN}/api/health" | head -c 300 || true
echo ""

echo "[4/5] Verifying Transparency Checkpoint (/api/transparency/checkpoint)..."
curl -s "https://${DOMAIN}/api/transparency/checkpoint" | head -c 300 || true
echo ""

echo "[5/5] Verifying RFC 3161 Timestamping Connectivity..."
curl -sI "http://timestamp.digicert.com" | head -n 5 || true

echo "=========================================================="
echo "  Audit Complete for ${DOMAIN}"
echo "=========================================================="
