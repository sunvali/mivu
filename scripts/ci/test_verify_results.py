import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('verify_results', Path(__file__).with_name('verify_results.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class ResultChecks(unittest.TestCase):
    def test_named_swift_tests_pass(self):
        summary = dict(totalTestCount=2, passedTests=2, failedTests=0, skippedTests=0, expectedFailures=0)
        tests = {'testNodes': [{'nodeType': 'Test Suite', 'name': 'DiaryTests', 'children': [
            {'nodeType': 'Test Case', 'name': 'captureSurvivesRestart()', 'result': 'Passed'},
            {'nodeType': 'Test Case', 'name': 'deletedMealCannotReturn()', 'result': 'Passed'}]}]}
        self.assertEqual(module.validate(summary, tests)[0], 2)

    def test_rejects_zero_failed_skipped_and_unnamed_results(self):
        for summary, tests in [
            (dict(totalTestCount=0, passedTests=0, failedTests=0), {'testNodes': []}),
            (dict(totalTestCount=1, passedTests=0, failedTests=1), {'testNodes': []}),
            (dict(totalTestCount=1, passedTests=0, failedTests=0, skippedTests=1), {'testNodes': []}),
            (dict(totalTestCount=1, passedTests=1, failedTests=0), {'testNodes': []}),
            (dict(totalTestCount=2, passedTests=1, failedTests=1), {'testNodes': []}),
        ]:
            with self.subTest(summary=summary), self.assertRaises(ValueError):
                module.validate(summary, tests)

if __name__ == '__main__':
    unittest.main()
