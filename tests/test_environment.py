"""Portable sender configuration checks; temporary files only, no services."""
from pathlib import Path
import runpy
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = runpy.run_path(str(ROOT / 'scripts/validate-environment.py'))


class EnvironmentSenderTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='docurama-sender-config-')
        self.environment = Path(self.temp.name) / 'tenant.env'
        self.base = (ROOT / 'compose/.env.tenant.template').read_text(encoding='utf-8') \
            .replace('REPLACE_WITH_VERIFIED_DIGEST', 'a' * 64) \
            .replace('REPLACE_FROM_TERRAFORM_OUTPUT', 'docurama-test', 1) \
            .replace('REPLACE_FROM_TERRAFORM_OUTPUT',
                     'arn:aws:kms:eu-west-3:123456789012:key/12345678-1234-1234-1234-123456789012')

    def tearDown(self):
        self.temp.cleanup()

    def validate(self, sender=None):
        lines = [line for line in self.base.splitlines() if not line.startswith('SMTP_FROM=')]
        if sender is not None:
            lines.append('SMTP_FROM=' + sender)
        self.environment.write_text('\n'.join(lines) + '\n', encoding='utf-8')
        return CONTRACT['validate'](self.environment, 'acme', 'sign.acme.example')

    def test_absent_blank_and_whitespace_sender_preserve_inheritance(self):
        for sender in (None, '', '   ', '"   "'):
            with self.subTest(sender=sender):
                values = self.validate(sender)
                self.assertFalse(values.get('SMTP_FROM', '').strip())
                self.assertEqual(values['SMTP_URL'], '')

    def test_explicit_safe_mailbox_and_display_name_pass(self):
        for sender in ('notifications@verified.example',
                       'Docurama <notifications@verified.example>',
                       "'\"Docurama Team\" <notifications@VERIFIED.example>'"):
            with self.subTest(sender=sender):
                self.assertTrue(self.validate(sender)['SMTP_FROM'])

    def test_nonblank_invalid_identity_fails_closed(self):
        for sender in ('not-a-mailbox', 'notifications@localhost', 'a..b@verified.example',
                       'a@-bad.example', 'a@example.test,b@example.test',
                       'Sender <a@example.test> <b@example.test>',
                       'Sender\t<a@example.test>', 'a' * 65 + '@example.test',
                       'a@' + 'b' * 64 + '.example', 'n' * 501):
            with self.subTest(sender=sender), self.assertRaises(ValueError):
                self.validate(sender)

    def test_header_control_and_shell_interpolation_rejected(self):
        for sender in ('sender@example.test\r\nBcc: injected@example.test',
                       'sender@example.test\x7f', '$(id)@example.test'):
            with self.subTest(sender=sender), self.assertRaises(ValueError):
                self.validate(sender)

    def test_optional_sender_is_forwarded_without_an_invented_default(self):
        compose = (ROOT / 'compose/docker-compose.vpc.yml').read_text(encoding='utf-8')
        self.assertIn('SMTP_FROM: ${SMTP_FROM:-}', compose)
        self.assertEqual(sum(line.strip().startswith('SMTP_FROM:')
                             for line in compose.splitlines()), 1)
        self.assertIn('SMTP_FROM=\n', self.base)
        self.assertNotIn('notifications@docurama.eu', compose)


if __name__ == '__main__':
    unittest.main(verbosity=2)
