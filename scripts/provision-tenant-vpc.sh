#!/usr/bin/env bash
# Prepare an existing Linux host. Starting containers requires explicit --start.
set -euo pipefail
umask 077
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[[ $# == 5 || $# == 7 ]] || die 'Usage: provision-tenant-vpc.sh TENANT_ID DOMAIN ENV_FILE TLS_CHAIN TLS_KEY [--start RELEASE_EVIDENCE_JSON]'
TENANT_ID="$1"; DOMAIN="$2"; ENV_FILE="$3"; TLS_CHAIN="$4"; TLS_KEY="$5"
[[ "${6:-}" == '' || "${6:-}" == '--start' ]] || die 'Unknown option'
[[ "$TENANT_ID" =~ ^[a-z][a-z0-9-]{1,30}$ ]] || die 'Invalid tenant identifier'
[[ "$DOMAIN" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}$ ]] || die 'Invalid domain'
[[ $EUID == 0 ]] || die 'Run on the target Linux host as root to set UID/GID 10001 ownership'
for tool in python3 openssl docker install flock; do command -v "$tool" >/dev/null || die "Missing prerequisite: $tool"; done
DEPLOY_ROOT="${DOCURAMA_DEPLOY_ROOT:-/opt/docurama-tenants}"
[[ "$DEPLOY_ROOT" == /* && "$DEPLOY_ROOT" != / && ! -L "$DEPLOY_ROOT" ]] || die 'Deployment root must be an absolute non-symlink directory'
DEPLOY_DIR="$DEPLOY_ROOT/$TENANT_ID"
[[ ! -L "$DEPLOY_DIR" ]] || die 'Deployment directory must not be a symlink'
install -d -m 700 "$DEPLOY_DIR"
for path in .bootstrap.lock .env data data/db data/storage data/certs ssl ssl/fullchain.pem ssl/privkey.pem docker-compose.yml nginx.tenant.conf; do
  [[ ! -L "$DEPLOY_DIR/$path" ]] || die "Refusing symlink: $path"
done
exec 9>"$DEPLOY_DIR/.bootstrap.lock"
flock -n 9 || die 'Another bootstrap is running for this tenant'
# Never execute an environment file. Validate existing configuration on every rerun.
if [[ -f "$DEPLOY_DIR/.env" ]]; then
  CONFIG="$DEPLOY_DIR/.env"
else
  [[ -f "$ENV_FILE" ]] || die 'Supply an environment file for first bootstrap'
  CONFIG="$ENV_FILE"
fi
python3 "$ROOT_DIR/scripts/validate-environment.py" "$CONFIG" "$TENANT_ID" "$DOMAIN"
if [[ "${6:-}" == '--start' ]]; then
  python3 "$ROOT_DIR/scripts/validate-release.py" "$7" "$CONFIG" "$TENANT_ID" "$DOMAIN"
fi
[[ -f "$TLS_CHAIN" && -f "$TLS_KEY" ]] || die 'Supply a trusted TLS certificate chain and private key'
openssl x509 -in "$TLS_CHAIN" -noout -checkend 86400 >/dev/null || die 'TLS certificate expires within 24 hours'
# OpenSSL x509 returns zero even for a hostname mismatch; assert its result.
[[ "$(openssl x509 -in "$TLS_CHAIN" -noout -checkhost "$DOMAIN")" == "Hostname $DOMAIN does match certificate" ]] || die 'TLS certificate does not cover the domain'
cert_key="$(openssl x509 -in "$TLS_CHAIN" -pubkey -noout | openssl pkey -pubin -outform DER | openssl dgst -sha256)"
private_key="$(openssl pkey -in "$TLS_KEY" -passin pass: -pubout -outform DER | openssl dgst -sha256)"
[[ "$cert_key" == "$private_key" ]] || die 'TLS certificate and private key do not match'
install -d -m 750 -o 10001 -g 10001 "$DEPLOY_DIR/data" "$DEPLOY_DIR/data/db" "$DEPLOY_DIR/data/storage" "$DEPLOY_DIR/data/certs"
install -d -m 700 "$DEPLOY_DIR/ssl"
# Signing material is application-managed. Preserve existing certificates/keys.
[[ -f "$DEPLOY_DIR/.env" ]] || install -m 600 "$ENV_FILE" "$DEPLOY_DIR/.env"
chmod 600 "$DEPLOY_DIR/.env"
install -m 600 "$ROOT_DIR/compose/docker-compose.vpc.yml" "$DEPLOY_DIR/docker-compose.yml"
install -m 600 "$ROOT_DIR/compose/nginx.tenant.conf" "$DEPLOY_DIR/nginx.tenant.conf"
# A rerun never silently replaces an installed identity.
if [[ -e "$DEPLOY_DIR/ssl/fullchain.pem" || -e "$DEPLOY_DIR/ssl/privkey.pem" ]]; then
  [[ -f "$DEPLOY_DIR/ssl/fullchain.pem" && -f "$DEPLOY_DIR/ssl/privkey.pem" ]] || die 'Incomplete installed TLS identity; repair explicitly'
  cmp -s "$TLS_CHAIN" "$DEPLOY_DIR/ssl/fullchain.pem" && cmp -s "$TLS_KEY" "$DEPLOY_DIR/ssl/privkey.pem" || die 'TLS identity differs; renew explicitly following the runbook'
else
  install -m 600 "$TLS_CHAIN" "$DEPLOY_DIR/ssl/fullchain.pem"
  install -m 600 "$TLS_KEY" "$DEPLOY_DIR/ssl/privkey.pem"
fi
chmod 600 "$DEPLOY_DIR/ssl/fullchain.pem" "$DEPLOY_DIR/ssl/privkey.pem"
cd "$DEPLOY_DIR"
# The installed file is authoritative: the supplied file may change before copy.
python3 "$ROOT_DIR/scripts/validate-environment.py" "$DEPLOY_DIR/.env" "$TENANT_ID" "$DOMAIN"
if [[ "${6:-}" == '--start' ]]; then
  python3 "$ROOT_DIR/scripts/validate-release.py" "$7" "$DEPLOY_DIR/.env" "$TENANT_ID" "$DOMAIN"
fi
# Prevent caller variables from overriding the validated dotenv contract.
compose() { env -i PATH="$PATH" HOME=/root docker compose --env-file .env -f docker-compose.yml "$@"; }
compose config --quiet
if [[ "${6:-}" == '--start' ]]; then
  compose pull
  compose up -d --wait --wait-timeout 180
  printf 'Containers started. Run verification and acceptance checks before routing users.\n'
else
  printf 'Prepared %s. No containers started. Rerun with --start only after deployment approval.\n' "$DEPLOY_DIR"
fi
