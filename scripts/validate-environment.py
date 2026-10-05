#!/usr/bin/env python3
"""Validate the deployment contract without evaluating shell expressions."""
import re
import sys
from pathlib import Path


def validate_mail_sender(value):
    """Blank inherits platform identity; nonblank must be one safe mailbox."""
    if not value.strip():
        return
    if len(value) > 500 or re.search(r'[\x00-\x1f\x7f]', value):
        raise ValueError('SMTP_FROM must contain one valid configured sender')
    value = value.strip()
    named = re.fullmatch(r'([^<>]+)\s*<([^<>]+)>', value)
    address = (named[2] if named else value).strip()
    local, separator, domain = address.rpartition('@')
    if (not separator or len(address) > 254 or not 1 <= len(local) <= 64
            or not re.fullmatch(r"[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+)*", local)
            or not re.fullmatch(r'(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?', domain)):
        raise ValueError('SMTP_FROM must contain exactly one valid mailbox')


def validate(path, tenant, domain):
    values = {}
    for line in Path(path).read_text(encoding='utf-8').splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        match = re.fullmatch(r'([A-Z][A-Z0-9_]*)=(.*)', line)
        if not match or match[1] in values:
            raise ValueError('Use unique KEY=value lines; shell syntax is unsupported')
        name, value = match.groups()
        if value.startswith(('"', "'")):
            if len(value) < 2 or value[-1] != value[0]:
                raise ValueError('Unbalanced environment quoting')
            value = value[1:-1]
        if '$' in value or '\\' in value or '\x00' in value:
            raise ValueError('Environment interpolation and escape sequences are unsupported')
        values[name] = value
    expected = {'TENANT_ID': tenant, 'DOMAIN': domain,
                'DOCURAMA_DEPLOYMENT_MODE': 'private_cloud',
                'DOCURAMA_PUBLIC_REGISTRATION': 'false',
                'S3_CREDENTIALS_MODE': 'default',
                'S3_AUTO_CREATE_BUCKET': '0', 'REKOR_WITNESS': 'off'}
    for name, value in expected.items():
        if values.get(name) != value:
            raise ValueError(f'{name} is missing or inconsistent with private-cloud policy')
    for name in ('APP_IMAGE', 'EDGE_IMAGE'):
        if not re.fullmatch(r'[a-z0-9][a-z0-9./:_-]*@sha256:[0-9a-f]{64}', values.get(name, '')):
            raise ValueError(f'{name} must be an explicit image reference pinned by SHA-256 digest')
    if not re.fullmatch(r'[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]', values.get('S3_BUCKET', '')):
        raise ValueError('S3_BUCKET is required')
    if not re.fullmatch(r'[a-z]{2}-[a-z]+-\d+', values.get('S3_REGION', '')):
        raise ValueError('S3_REGION is required')
    if not re.fullmatch(r'arn:aws:kms:[a-z0-9-]+:\d{12}:key/[a-f0-9-]+', values.get('S3_SSE_KMS_KEY_ID', '')):
        raise ValueError('S3_SSE_KMS_KEY_ID must be the Terraform KMS key ARN')
    for name in ('S3_ACCESS_KEY_ID', 'S3_SECRET_ACCESS_KEY', 'S3_ENDPOINT'):
        if values.get(name):
            raise ValueError(f'{name} is unsupported: use the EC2 instance role and regional AWS S3')
    validate_mail_sender(values.get('SMTP_FROM', ''))
    return values


if __name__ == '__main__':
    try:
        validate(*sys.argv[1:])
    except (ValueError, OSError, TypeError) as error:
        sys.exit(f'Invalid deployment environment: {error}')
