#!/usr/bin/env python3
"""Assert health and verify the portal checkpoint against an operator-pinned key."""
import base64
import hashlib
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


def require(condition, message):
    if not condition:
        raise ValueError(message)


def check(directory, trusted_fingerprint):
    directory = Path(directory)
    headers = {}
    for line in (directory / 'headers').read_text().splitlines():
        if ':' in line:
            name, value = line.split(':', 1)
            headers[name.lower()] = value.strip().lower()
    hsts = re.search(r'(?:^|;)\s*max-age=(\d+)', headers.get('strict-transport-security', ''))
    require(hsts and int(hsts[1]) >= 31536000, 'Missing or insufficient HSTS')
    require(headers.get('x-content-type-options') == 'nosniff', 'Missing nosniff header')
    require(headers.get('x-frame-options') in ('sameorigin', 'deny'), 'Missing frame protection')
    health = json.loads((directory / 'health.json').read_text())
    require(health.get('status') == 'ok', 'Application is not ready')
    checks = health['checks']
    require(checks['database'].get('ok') is True, 'Database is unhealthy')
    require(checks['storage'].get('ok') is True, 'Storage is unhealthy')
    require(checks['storage'].get('backend') == 's3', 'Expected S3; refusing silent local fallback')
    payload = json.loads((directory / 'checkpoint.json').read_text())
    require(payload.get('ok') is True, 'Checkpoint endpoint failed')
    require(payload.get('endpoint') == 'docurama-transparency-checkpoint', 'Unexpected endpoint')
    cp = payload['checkpoint']
    require(cp['keyId'] == 'portal', 'Unexpected checkpoint key ID')
    require(isinstance(cp['size'], int) and not isinstance(cp['size'], bool) and cp['size'] >= 0, 'Invalid log size')
    require(re.fullmatch('[0-9a-f]{64}', cp['head']), 'Invalid log head')
    require(payload['log']['size'] == cp['size'] and payload['log']['head'] == cp['head'], 'Checkpoint/log mismatch; retry if writes occurred during probe')
    require(cp['format'] == 'docurama-transparency-checkpoint', 'Unknown checkpoint format')
    at = datetime.fromisoformat(cp['at'].replace('Z', '+00:00'))
    require(at.tzinfo and abs((datetime.now(timezone.utc) - at).total_seconds()) <= 600, 'Stale or future checkpoint')
    public_key = directory / 'portal-public.pem'
    public_key.write_text(cp['publicKeyPem'])
    der = subprocess.check_output(['openssl', 'pkey', '-pubin', '-in', str(public_key), '-outform', 'DER'], stderr=subprocess.DEVNULL)
    fingerprint = hashlib.sha256(der).hexdigest()
    require(fingerprint == trusted_fingerprint == cp['keyFingerprint'], 'Portal key does not match the trusted fingerprint')
    body = {key: cp[key] for key in ('format', 'keyId', 'size', 'head', 'at')}
    # Fields have ASCII keys and integer sizes: this matches the application's canonical JSON.
    (directory / 'body.json').write_bytes(json.dumps(body, sort_keys=True, ensure_ascii=False, separators=(',', ':')).encode())
    (directory / 'signature.bin').write_bytes(base64.b64decode(cp['signature'], validate=True))
    subprocess.run(['openssl', 'dgst', '-sha256', '-verify', str(public_key),
                    '-signature', str(directory / 'signature.bin'), str(directory / 'body.json')],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == '__main__':
    try:
        check(*sys.argv[1:])
    except (ValueError, KeyError, TypeError, AttributeError, OSError, subprocess.SubprocessError) as error:
        sys.exit(f'FAIL: {error}')
