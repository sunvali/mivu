"""Check the smoke runner without starting Xcode."""
import json
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
from unittest.mock import patch

import smoke


class SmokeRunnerTests(unittest.TestCase):
    def test_only_smoke_is_selected_on_the_explicit_simulator(self):
        command = smoke.command('dedicated-simulator', Path('/tmp/smoke-dd'), Path('/tmp/run.xcresult'))
        args = json.loads(command[command.index('--json') + 1])
        self.assertEqual(args['simulatorId'], 'dedicated-simulator')
        self.assertIn('-only-testing:MivuUITests/SmokeUITests', args['extraArgs'])
        self.assertIn('MivuQuick', args['extraArgs'])
        self.assertEqual(args['derivedDataPath'], '/tmp/smoke-dd')

    def test_timeout_stops_only_its_own_process_group_and_returns_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch('smoke.subprocess.Popen') as start, patch('smoke.os.killpg') as kill:
                process = start.return_value
                process.pid = 1234
                process.wait.side_effect = [subprocess.TimeoutExpired('synthetic', 120), None]
                status = smoke.execute(['synthetic'], Path(directory))
                self.assertEqual(status, 124)
                self.assertTrue(start.call_args.kwargs['start_new_session'])
                self.assertEqual(process.wait.call_args_list[0].kwargs['timeout'], 120)
                self.assertEqual(kill.call_args_list[0].args[0], 1234)

    def test_failed_skipped_zero_or_malformed_evidence_never_passes(self):
        good = {'didError': False, 'data': {'summary': {'status': 'SUCCEEDED',
                'counts': {'passed': 1, 'failed': 0, 'skipped': 0}},
                'request': {'onlyTesting': ['MivuUITests/SmokeUITests']}}}
        self.assertTrue(smoke.passed(good))
        for key, value in [('passed', 0), ('failed', 1), ('skipped', 1), ('passed', True)]:
            changed = json.loads(json.dumps(good))
            changed['data']['summary']['counts'][key] = value
            self.assertFalse(smoke.passed(changed))
        self.assertFalse(smoke.passed({}))
        good['didError'] = True
        self.assertFalse(smoke.passed(good))

    def test_quick_is_default_and_full_plan_keeps_every_journey(self):
        root = Path(__file__).resolve().parents[2]
        scheme = ET.parse(root / 'ios/Mivu.xcodeproj/xcshareddata/xcschemes/Mivu.xcscheme')
        plans = scheme.findall('.//TestPlanReference')
        self.assertEqual([p.attrib['reference'] for p in plans if p.get('default') == 'YES'],
                         ['container:Mivu/MivuQuick.xctestplan'])
        quick = json.loads((root / 'ios/Mivu/MivuQuick.xctestplan').read_text())
        targets = {t['target']['name']: t for t in quick['testTargets']}
        self.assertEqual(targets['MivuUITests']['selectedTests'], ['SmokeUITests'])
        self.assertEqual(set(targets), {'MivuUITests'})
        full = json.loads((root / 'ios/Mivu/Mivu.xctestplan').read_text())
        self.assertEqual({t['target']['name'] for t in full['testTargets']}, {'MivuTests', 'MivuUITests'})
        for target in full['testTargets']:
            self.assertNotIn('selectedTests', target)
            self.assertNotIn('skippedTests', target)
