"""Portable, offline release gate checks; no subprocesses or services."""
import hashlib
import json
from pathlib import Path
import runpy
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
GATE = runpy.run_path(str(ROOT / 'scripts/validate-release.py'))


def fixture(directory, environment):
    values = runpy.run_path(str(ROOT / 'scripts/validate-environment.py'))['validate'](environment, 'acme', 'sign.acme.example')
    report = directory / 'acceptance.txt'
    report.write_text('NON-PRODUCTION UNIT TEST FIXTURE: no actual acceptance evidence')
    evidence = {
        'format': 'docurama-private-cloud-release-v1', 'tenant_id': 'acme',
        'domain': 'sign.acme.example', 'app_image': values['APP_IMAGE'],
        'edge_image': values['EDGE_IMAGE'], 'database_provider': 'sqlite',
        'application_source_commit': 'a' * 40, 'decision': 'approved',
        'approved_by': 'UNIT TEST FIXTURE', 'approved_at': '2026-01-01T00:00:00Z',
        'checks': {name: {'status': 'passed', 'report': report.name,
                         'sha256': hashlib.sha256(report.read_bytes()).hexdigest()}
                   for name in GATE['CHECKS']},
    }
    path = directory / 'release.json'
    path.write_text(json.dumps(evidence))
    return path, evidence


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='docurama-release-')
        self.directory = Path(self.temp.name)
        self.environment = self.directory / 'tenant.env'
        self.environment.write_text((ROOT / 'compose/.env.tenant.template').read_text()
                                    .replace('REPLACE_WITH_VERIFIED_DIGEST', 'a' * 64)
                                    .replace('REPLACE_FROM_TERRAFORM_OUTPUT', 'docurama-test', 1)
                                    .replace('REPLACE_FROM_TERRAFORM_OUTPUT', 'arn:aws:kms:eu-west-3:123456789012:key/12345678-1234-1234-1234-123456789012'))
        self.path, self.evidence = fixture(self.directory, self.environment)

    def tearDown(self):
        self.temp.cleanup()

    def check(self):
        self.path.write_text(json.dumps(self.evidence))
        GATE['validate'](self.path, self.environment, 'acme', 'sign.acme.example')

    def test_complete_fixture_passes(self):
        self.check()

    def test_installed_environment_requires_approved_digest(self):
        installed = self.directory / 'installed.env'
        installed.write_text(self.environment.read_text().replace('@sha256:' + 'a' * 64,
                                                                  '@sha256:' + 'b' * 64))
        # A syntactically valid copied configuration can differ from the approved input.
        runpy.run_path(str(ROOT / 'scripts/validate-environment.py'))['validate'](
            installed, 'acme', 'sign.acme.example')
        with self.assertRaisesRegex(ValueError, 'image digest mismatch'):
            GATE['validate'](self.path, installed, 'acme', 'sign.acme.example')

    def test_wrong_installation_image_provider_or_decision_rejected(self):
        for key, value in (('tenant_id', 'another'), ('domain', 'another.example'),
                           ('app_image', 'other@sha256:' + 'b' * 64),
                           ('edge_image', 'other@sha256:' + 'b' * 64),
                           ('database_provider', 'postgresql'), ('decision', 'pending'),
                           ('approved_by', ''), ('approved_at', '2999-01-01T00:00:00Z'),
                           ('approved_at', '2026-01-01T00:00:00'), ('application_source_commit', 'd106c71')):
            original = self.evidence[key]
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                self.evidence[key] = value
                self.check()
            self.evidence[key] = original

    def test_missing_or_failed_acceptance_rejected(self):
        for name in GATE['CHECKS']:
            check = self.evidence['checks'].pop(name)
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.check()
            self.evidence['checks'][name] = check
            check['status'] = 'pending'
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.check()
            check['status'] = 'passed'

    def test_changed_missing_or_escaped_report_rejected(self):
        check = self.evidence['checks']['runtime_contract']
        for report in ('missing.txt', '../outside.txt', str((self.directory / 'acceptance.txt').resolve())):
            check['report'] = report
            with self.subTest(report=report), self.assertRaises(ValueError):
                self.check()
        check['report'] = 'acceptance.txt'
        (self.directory / 'acceptance.txt').write_text('tampered')
        with self.assertRaises(ValueError):
            self.check()


if __name__ == '__main__':
    unittest.main()
