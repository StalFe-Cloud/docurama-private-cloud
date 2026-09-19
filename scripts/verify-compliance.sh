#!/usr/bin/env bash
# Operational and checkpoint checks, not a legal compliance certification.
set -euo pipefail
[[ $# == 2 ]] || { echo 'Usage: verify-compliance.sh DOMAIN TRUSTED_PORTAL_KEY_SHA256' >&2; exit 1; }
DOMAIN="$1"; FINGERPRINT="$2"
[[ "$DOMAIN" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}$ ]] || { echo 'Invalid domain' >&2; exit 1; }
[[ "$FINGERPRINT" =~ ^[0-9a-f]{64}$ ]] || { echo 'Supply the portal SPKI fingerprint established over a trusted channel' >&2; exit 1; }
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
for tool in curl python3 openssl; do command -v "$tool" >/dev/null || { echo "Missing prerequisite: $tool" >&2; exit 1; }; done
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEMP_DIR"' EXIT
# curl validates hostname and CA trust. No insecure mode, HTTP downgrade, or ignored failures.
CURL=(curl --silent --show-error --fail --proto '=https' --tlsv1.2 --connect-timeout 10 --max-time 30 --max-filesize 1048576)
"${CURL[@]}" -D "$TEMP_DIR/headers" -o /dev/null "https://$DOMAIN/"
"${CURL[@]}" -o "$TEMP_DIR/health.json" "https://$DOMAIN/api/health"
"${CURL[@]}" -o "$TEMP_DIR/checkpoint.json" "https://$DOMAIN/api/transparency/checkpoint"
python3 "$ROOT_DIR/scripts/verify-responses.py" "$TEMP_DIR" "$FINGERPRINT"
printf 'PASS: TLS trust, security headers, database/S3 health and pinned checkpoint signature.\n'
printf 'Signing ceremony, timestamp authority, log consistency, backups and tenant isolation require separate acceptance evidence.\n'
