#!/usr/bin/env python3
"""Check operator release evidence without pulling images or contacting services.

This checks completeness/integrity of supplied evidence, not its truth or approval
authority. Evidence files must contain non-secret acceptance reports only.
"""
import hashlib
import json
import re
import sys
import runpy
from datetime import datetime, timezone
from pathlib import Path

CHECKS = ('runtime_contract', 'migration_failure', 'admin_bootstrap',
          'invitation_and_tenant_isolation', 's3_kms_and_access_denials',
          'signing_and_evidence', 'backup_restore', 'monitoring_and_tls')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def validate(evidence_path, environment_path, tenant, domain):
    environment_validator = runpy.run_path(str(Path(__file__).with_name('validate-environment.py')))['validate']
    env = environment_validator(environment_path, tenant, domain)
    path = Path(evidence_path).resolve()
    evidence = json.loads(path.read_text())
    require(evidence.get('format') == 'docurama-private-cloud-release-v1', 'Unknown release evidence format')
    require(evidence.get('tenant_id') == tenant and evidence.get('domain') == domain, 'Evidence installation mismatch')
    require(evidence.get('app_image') == env['APP_IMAGE'] and evidence.get('edge_image') == env['EDGE_IMAGE'], 'Evidence image digest mismatch')
    require(evidence.get('database_provider') == 'sqlite', 'This blueprint requires a SQLite application image')
    require(re.fullmatch(r'[0-9a-f]{40}', evidence.get('application_source_commit', '')), 'Record full application source commit')
    require(evidence.get('decision') == 'approved', 'Release decision is not approved')
    require(isinstance(evidence.get('approved_by'), str) and evidence['approved_by'].strip(), 'Record release approver')
    approved_at = datetime.fromisoformat(evidence['approved_at'].replace('Z', '+00:00'))
    require(approved_at.tzinfo and approved_at <= datetime.now(timezone.utc), 'Invalid approval timestamp')
    checks = evidence.get('checks', {})
    require(set(checks) == set(CHECKS), 'Complete every required acceptance check')
    for name in CHECKS:
        check = checks[name]
        require(check.get('status') == 'passed', f'Acceptance check is not passed: {name}')
        reference = check.get('report', '')
        require(isinstance(reference, str) and reference, f'Missing report: {name}')
        report = (path.parent / reference).resolve()
        require(not Path(reference).is_absolute() and report.is_relative_to(path.parent), f'Report must remain inside evidence directory: {name}')
        expected = check.get('sha256', '')
        require(re.fullmatch(r'[0-9a-f]{64}', expected), f'Missing report SHA-256: {name}')
        require(report.is_file() and hashlib.sha256(report.read_bytes()).hexdigest() == expected, f'Missing or changed acceptance report: {name}')


if __name__ == '__main__':
    try:
        validate(*sys.argv[1:])
    except (ValueError, KeyError, TypeError, AttributeError, OSError) as error:
        # Never print environment, report contents or JSON decoder excerpts.
        if isinstance(error, json.JSONDecodeError):
            sys.exit('Invalid release evidence: malformed JSON')
        sys.exit(f'Invalid release evidence: {error}')
