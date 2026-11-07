"""Behavior/privacy tests for offline comparison; all reports are synthetic."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import unittest

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


comparison = load('comparison_subject', 'compare-compatibility.py')
fixtures = load('comparison_fixtures', 'test_compatibility.py')


class ComparisonTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.CompatibilityTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.fixture.populate()
        self.left = self.fixture.result()
        self.right = copy.deepcopy(self.left)

    def field(self, name):
        result = comparison.compare(self.left, self.right)
        self.assertIs(result['write_eligible'], False)
        return next(field for field in result['fields'] if field['field'] == name)

    def test_same_observations_with_unknown_locations(self):
        self.assertEqual(self.field('chip_id')['state'], 'same')
        self.assertEqual(self.field('display_controller_count')['state'], 'same')
        self.assertEqual(self.field('display_controllers')['state'], 'same')

    def test_bus_and_edid_differences(self):
        for observation in self.right['observations']:
            observation['display_controllers'][0]['location']['bus'] = 1
            observation['edid_by_driver_open_count'] = 1
            observation['edid_active_open_count'] = 1
        self.assertEqual(self.field('display_controllers')['state'], 'different')
        self.assertEqual(self.field('edid_by_driver_open_count')['state'], 'different')

    def test_missing_is_unavailable_even_if_both_sides_missing(self):
        for report in (self.left, self.right):
            for observation in report['observations']:
                observation['chip_id'] = None
        self.assertEqual(self.field('chip_id')['state'], 'unavailable')
        self.right['observations'][0] = {'capture': 'DIAG00.TXT', 'available': False}
        self.assertEqual(self.field('gop_handle_count')['state'], 'unavailable')

    def test_zero_is_observed_and_not_missing(self):
        for observation in self.left['observations']:
            observation['device_memory_size_mib'] = 0
        self.assertEqual(self.field('device_memory_size_mib')['state'], 'different')

    def test_policy_change_defers_comparison(self):
        for key, value in (('envelope_sha256', '0' * 64),
                           ('checker_version', self.left['checker_version'] + 1)):
            self.right = copy.deepcopy(self.left)
            self.right[key] = value
            result = comparison.compare(self.left, self.right)
            self.assertEqual(result['status'], 'different_checker_or_envelope')
            self.assertEqual(result['fields'], [])

    def test_capture_numbers_and_repeated_observations_do_not_identify_machine(self):
        self.right['observations'][0]['capture'] = 'DIAG42.TXT'
        self.right['observations'] = self.right['observations'][:1]
        self.right['capture_count'] = 1
        self.assertEqual(self.field('chip_id')['state'], 'same')

    def test_type_range_and_extra_field_rejections(self):
        for change in ('format', 'bool', 'bus', 'extra', 'approval', 'count', 'missing'):
            with self.subTest(change=change):
                report = copy.deepcopy(self.left)
                observation = report['observations'][0]
                if change == 'format':
                    report['format'] = 1
                elif change == 'bool':
                    observation['gop_handle_count'] = True
                elif change == 'bus':
                    observation['display_controllers'][0]['location']['bus'] = 256
                elif change == 'extra':
                    observation['serial_number'] = 'PRIVATE'
                elif change == 'approval':
                    report['write_eligible'] = True
                elif change == 'count':
                    observation['nvidia_display_count'] = 2
                else:
                    report['observations'][0] = {'capture': 'DIAG00.TXT'}
                with self.assertRaises((ValueError, KeyError, TypeError)):
                    comparison.validate(report)

    def test_duplicate_keys_nonfinite_oversize_and_nesting_are_rejected(self):
        path = self.fixture.folder / 'report.json'
        for raw in ('{"format": 2, "format": 2}', '{"format": NaN}', '[' * 2000,
                    ' ' * (comparison.LIMIT + 1)):
            path.write_text(raw, encoding='utf-8')
            with self.assertRaises((ValueError, RecursionError)):
                comparison.read_report(path)

    def test_utf8_and_windows_powershell_utf16_reports(self):
        path = self.fixture.folder / 'report.json'
        for encoding in ('utf-8-sig', 'utf-16'):
            path.write_text(json.dumps(self.left), encoding=encoding)
            self.assertEqual(comparison.read_report(path), self.left)

    def test_cli_does_not_echo_report_messages_or_write_files(self):
        private = 'PRIVATE-REPORT-MESSAGE-DO-NOT-ECHO'
        self.left['summary'] = private
        self.left['checks'][0]['message'] = private
        left = self.fixture.folder / 'left.json'
        right = self.fixture.folder / 'right.json'
        left.write_text(json.dumps(self.left), encoding='utf-8')
        right.write_text(json.dumps(self.right), encoding='utf-8')
        before = {p.name: p.read_bytes() for p in self.fixture.folder.iterdir()}
        for lang in ('en', 'ko'):
            done = subprocess.run([sys.executable, '-I', str(HERE / 'compare-compatibility.py'),
                                   str(left), str(right), '--json', '--lang', lang], capture_output=True, text=True)
            self.assertEqual(done.returncode, 0, done.stderr)
            self.assertEqual(json.loads(done.stdout)['status'], 'compared')
            self.assertNotIn(private, done.stdout)
            self.assertNotIn(str(left), done.stdout)
        self.assertEqual({p.name: p.read_bytes() for p in self.fixture.folder.iterdir()}, before)
        right.write_text('invalid private report ' + private, encoding='utf-8')
        done = subprocess.run([sys.executable, '-I', str(HERE / 'compare-compatibility.py'),
                               str(left), str(right), '--json'], capture_output=True, text=True)
        self.assertEqual(done.returncode, 2)
        self.assertEqual(json.loads(done.stdout)['status'], 'invalid_report')
        self.assertNotIn(private, done.stdout + done.stderr)


if __name__ == '__main__':
    unittest.main()
