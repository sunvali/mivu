"""Protect the signed lane's trigger/source boundary without paid environments."""
import json
import subprocess
import unittest
from pathlib import Path


class SignedWorkflowContract(unittest.TestCase):
    def test_signed_lane_requires_manual_main_and_tested_source(self):
        workflow = Path(__file__).resolve().parents[2] / '.github/workflows/release.yml'
        parsed = subprocess.check_output([
            'ruby', '-r', 'yaml', '-r', 'json', '-e',
            'puts JSON.generate(YAML.load_file(ARGV.fetch(0)))', str(workflow)
        ], text=True)
        release = json.loads(parsed)
        signed = release['jobs']['signed']
        self.assertNotIn('environment', signed, 'Private GitHub Free must not require a paid environment.')
        self.assertEqual(signed['needs'], 'artifacts')
        self.assertEqual(signed['if'], "github.event_name == 'workflow_dispatch' && (inputs.signed_delivery || inputs.upload_testflight) && github.ref == 'refs/heads/main'")
        self.assertEqual(release['permissions'], {'contents': 'read'})
        self.assertNotIn('permissions', signed)
        checkout = signed['steps'][0]
        self.assertEqual(checkout['with']['ref'], '${{ needs.artifacts.outputs.sha }}')
        self.assertFalse(checkout['with']['persist-credentials'])


if __name__ == '__main__':
    unittest.main()
