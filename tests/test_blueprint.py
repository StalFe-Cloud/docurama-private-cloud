#!/usr/bin/env python3
"""Offline regression tests. Only temporary files are written; Docker/curl are mocked."""
import base64
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]


def run(args, **kwargs):
    return subprocess.run(args, text=True, capture_output=True, **kwargs)


def executable(path, text):
    path.write_text(text)
    path.chmod(0o755)


class BlueprintTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='docurama-blueprint-')
        self.path = Path(self.temp.name)
        self.bin = self.path / 'bin'
        self.bin.mkdir()
        self.env = {**os.environ, 'PATH': str(self.bin) + ':' + os.environ['PATH']}
        self.environment = self.path / 'tenant.env'
        template = (ROOT / 'compose/.env.tenant.template').read_text()
        self.environment.write_text(template.replace('REPLACE_WITH_VERIFIED_DIGEST', 'a' * 64)
                                    .replace('REPLACE_FROM_TERRAFORM_OUTPUT', 'docurama-test', 1)
                                    .replace('REPLACE_FROM_TERRAFORM_OUTPUT', 'arn:aws:kms:eu-west-3:123456789012:key/12345678-1234-1234-1234-123456789012'))
        self.cert = self.path / 'cert.pem'
        self.key = self.path / 'key.pem'
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                        '-keyout', str(self.key), '-out', str(self.cert), '-days', '2',
                        '-subj', '/CN=sign.acme.example', '-addext', 'subjectAltName=DNS:sign.acme.example'],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def tearDown(self):
        self.temp.cleanup()

    def bootstrap(self, *extra):
        return run(['bash', str(ROOT / 'scripts/provision-tenant-vpc.sh'), 'acme', 'sign.acme.example',
                    str(self.environment), str(self.cert), str(self.key), *extra],
                   env=self.env, cwd=self.path)

    def test_environment_rejects_mutable_image_and_shell_interpolation(self):
        validate = ['python3', str(ROOT / 'scripts/validate-environment.py'), str(self.environment), 'acme', 'sign.acme.example']
        self.assertEqual(run(validate).returncode, 0)
        original = self.environment.read_text()
        for invalid in (original.replace('@sha256:' + 'a' * 64, ':latest'), original + 'SMTP_URL=$(id)\n',
                        original.replace('S3_CREDENTIALS_MODE=default', 'S3_CREDENTIALS_MODE=static')):
            self.environment.write_text(invalid)
            self.assertNotEqual(run(validate).returncode, 0)

    @unittest.skipUnless(os.geteuid() == 0, 'Bootstrap ownership test requires root; CI runs in sudo')
    def test_bootstrap_is_repeatable_and_prepare_only(self):
        log = self.path / 'docker.log'
        executable(self.bin / 'docker', '#!/bin/sh\nprintf "%s\\n" "$*" >> ' + str(log) + '\n')
        self.env['DOCURAMA_DEPLOY_ROOT'] = str(self.path / 'deploy')
        result = self.bootstrap()
        self.assertEqual(result.returncode, 0, result.stderr)
        target = self.path / 'deploy/acme'
        self.assertEqual((target / 'data/db').stat().st_uid, 10001)
        self.assertEqual((target / '.env').stat().st_mode & 0o777, 0o600)
        identity = target / 'data/certs/tenant_key.pem'
        identity.write_text('existing signing identity')
        existing = (target / '.env').read_bytes()
        (target / '.env').chmod(0o644)
        self.environment.write_text('INVALID=do-not-overwrite\n')
        result = self.bootstrap()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((target / '.env').read_bytes(), existing)
        self.assertEqual((target / '.env').stat().st_mode & 0o777, 0o600)
        self.assertEqual(identity.read_text(), 'existing signing identity')
        self.assertNotIn('up ', log.read_text())
        self.assertNotIn('pull', log.read_text())
        result = self.bootstrap('--start')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('up -d --wait', log.read_text())

    @unittest.skipUnless(os.geteuid() == 0, 'Bootstrap ownership test requires root')
    def test_bootstrap_fails_closed_on_missing_tls_and_bad_host(self):
        executable(self.bin / 'docker', '#!/bin/sh\nexit 0\n')
        self.env['DOCURAMA_DEPLOY_ROOT'] = str(self.path / 'deploy')
        self.cert.unlink()
        self.assertNotEqual(self.bootstrap().returncode, 0)
        invalid = run(['bash', str(ROOT / 'scripts/provision-tenant-vpc.sh'), '../escape', 'sign.acme.example',
                       str(self.environment), str(self.cert), str(self.key)], env=self.env)
        self.assertNotEqual(invalid.returncode, 0)
        self.assertFalse((self.path / 'escape').exists())

    @unittest.skipUnless(os.geteuid() == 0, 'Bootstrap ownership test requires root')
    def test_bootstrap_rejects_wrong_certificate_hostname_and_symlink(self):
        executable(self.bin / 'docker', '#!/bin/sh\nexit 0\n')
        self.env['DOCURAMA_DEPLOY_ROOT'] = str(self.path / 'deploy')
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                        '-keyout', str(self.key), '-out', str(self.cert), '-days', '2',
                        '-subj', '/CN=wrong.example.com'], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        mismatch = self.bootstrap()
        self.assertNotEqual(mismatch.returncode, 0)
        self.assertIn('does not cover', mismatch.stderr)
        target = self.path / 'deploy/acme/.env'
        target.symlink_to(self.environment)
        symlink = self.bootstrap()
        self.assertNotEqual(symlink.returncode, 0)
        self.assertIn('symlink', symlink.stderr)

    def fixture(self):
        fixture = self.path / 'responses'
        fixture.mkdir()
        (fixture / 'headers').write_text('HTTP/2 200\nStrict-Transport-Security: max-age=63072000\nX-Content-Type-Options: nosniff\nX-Frame-Options: SAMEORIGIN\n')
        (fixture / 'health.json').write_text(json.dumps({'status': 'ok', 'checks': {'database': {'ok': True}, 'storage': {'ok': True, 'backend': 's3'}}}))
        public = subprocess.check_output(['openssl', 'pkey', '-in', str(self.key), '-pubout'], stderr=subprocess.DEVNULL)
        der = subprocess.check_output(['openssl', 'pkey', '-pubin', '-outform', 'DER'], input=public, stderr=subprocess.DEVNULL)
        fingerprint = hashlib.sha256(der).hexdigest()
        body = {'format': 'docurama-transparency-checkpoint', 'keyId': 'portal', 'size': 0, 'head': '0' * 64,
                'at': datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')}
        signature = subprocess.check_output(['openssl', 'dgst', '-sha256', '-sign', str(self.key)],
                                            input=json.dumps(body, sort_keys=True, separators=(',', ':')).encode())
        cp = {**body, 'publicKeyPem': public.decode(), 'keyFingerprint': fingerprint,
              'signature': base64.b64encode(signature).decode()}
        payload = {'ok': True, 'endpoint': 'docurama-transparency-checkpoint', 'log': {'size': 0, 'head': '0' * 64}, 'checkpoint': cp}
        (fixture / 'checkpoint.json').write_text(json.dumps(payload))
        return fixture, fingerprint

    def test_verifier_requires_live_probes_and_valid_signed_checkpoint(self):
        fixture, fingerprint = self.fixture()
        executable(self.bin / 'curl', '#!/usr/bin/env python3\nimport pathlib, shutil, sys\nargs=sys.argv[1:]\nf=pathlib.Path(' + repr(str(fixture)) + ')\n'
                   "if '-D' in args: shutil.copyfile(f/'headers', args[args.index('-D')+1])\n"
                   "if args[-1].endswith('/api/health'): shutil.copyfile(f/'health.json', args[args.index('-o')+1])\n"
                   "if args[-1].endswith('/checkpoint'): shutil.copyfile(f/'checkpoint.json', args[args.index('-o')+1])\n")
        command = ['bash', str(ROOT / 'scripts/verify-compliance.sh'), 'sign.acme.example', fingerprint]
        good = run(command, env=self.env)
        self.assertEqual(good.returncode, 0, good.stderr)
        self.assertIn('PASS:', good.stdout)
        original = (fixture / 'checkpoint.json').read_text()
        for mutate in ('signature', 'keyFingerprint'):
            payload = json.loads(original)
            payload['checkpoint'][mutate] = 'b' * 64
            (fixture / 'checkpoint.json').write_text(json.dumps(payload))
            self.assertNotEqual(run(command, env=self.env).returncode, 0)
        (fixture / 'checkpoint.json').write_text(original)
        (fixture / 'health.json').write_text('{"status":"ok","checks":{"database":{"ok":true},"storage":{"ok":true,"backend":"local"}}}')
        self.assertNotEqual(run(command, env=self.env).returncode, 0)
        executable(self.bin / 'curl', '#!/bin/sh\nexit 7\n')
        fail = run(command, env=self.env)
        self.assertNotEqual(fail.returncode, 0)
        self.assertNotIn('PASS:', fail.stdout)

    def test_verifier_rejects_missing_headers_and_unhealthy_database(self):
        fixture, fingerprint = self.fixture()
        command = ['python3', str(ROOT / 'scripts/verify-responses.py'), str(fixture), fingerprint]
        original = (fixture / 'headers').read_text()
        (fixture / 'headers').write_text('HTTP/2 200\n')
        self.assertNotEqual(run(command, env={**self.env, 'PYTHONOPTIMIZE': '1'}).returncode, 0)
        (fixture / 'headers').write_text(original)
        health = json.loads((fixture / 'health.json').read_text())
        health['checks']['database']['ok'] = False
        (fixture / 'health.json').write_text(json.dumps(health))
        self.assertNotEqual(run(command).returncode, 0)


if __name__ == '__main__':
    unittest.main(verbosity=2)
