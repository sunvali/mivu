"""Missing signing credentials must fail before any Apple operations."""
import os
import subprocess
import unittest
from pathlib import Path

class SigningGate(unittest.TestCase):
    def test_missing_owner_credentials_fail_for_export_and_upload(self):
        script = Path(__file__).with_name('signed.sh')
        for upload in ('false', 'true'):
            env = {k: v for k, v in os.environ.items() if not k.startswith(('APPLE_', 'ASC_'))}
            env['UPLOAD_TESTFLIGHT'] = upload
            with self.subTest(upload=upload):
                result = subprocess.run(['bash', str(script)], env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 1)
                self.assertIn('Signed delivery blocked: missing owner secret APPLE_DISTRIBUTION_P12_BASE64', result.stderr)
                self.assertEqual('ASC_KEY_ID' in result.stderr, upload == 'true')

if __name__ == '__main__':
    unittest.main()
