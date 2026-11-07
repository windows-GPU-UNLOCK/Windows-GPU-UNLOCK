"""Exercise the offline PowerShell launcher with real processes, not hardware."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(sys.platform == 'win32' and shutil.which('powershell'), 'Windows PowerShell required')
class LauncherTests(unittest.TestCase):
    def run_launcher(self, python, text=None):
        with tempfile.TemporaryDirectory(prefix='capture test ') as folder:
            text = text or ('incomplete reason=probe-unreviewed-envelope status=0x8000000000000003\n'
                    'capture-complete=0\ndiagnostic-result status=0x8000000000000006\n')
            path = Path(folder) / 'DIAG00.TXT'
            path.write_text(text, encoding='ascii')
            result = subprocess.run(['powershell', '-NoProfile', '-File',
                                     str(ROOT / 'tools/test-existing-captures.ps1'),
                                     '-Captures', folder, '-Python', python],
                                    capture_output=True, text=True, timeout=45)
            self.assertEqual(path.read_text(encoding='ascii'), text)
        lines = [line for line in result.stdout.splitlines() if line.startswith('Results folder: ')]
        self.assertEqual(len(lines), 1, result.stdout + result.stderr)
        output = Path(lines[0].removeprefix('Results folder: '))
        return result, json.loads((output / 'result.json').read_text(encoding='utf-8')), output

    def test_explicit_python_runs_checker_and_keeps_refusal(self):
        result, receipt, output = self.run_launcher(sys.executable)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(receipt['phase'], 'done')
        self.assertEqual(receipt['status'], 'invalid_data')
        self.assertEqual(receipt['checker_exit'], 2)
        report = json.loads((output / 'report.json').read_text(encoding='utf-8'))
        self.assertIn('probe_envelope_refused', [x['code'] for x in report['checks']])
        self.assertIs(report['write_eligible'], False)

    def test_issue104_single_capture_without_prom_or_driver_images(self):
        # Reported excerpt only: this fixture is not a complete hardware capture.
        text = ('probe-target seg=0x0000 bus=0x0009 dev=0x0000 fun=0x0000\n'
                'cfg256 status=0x0000000000000000\n'
                'subsystem=0x00000000146a10b0\n'
                'incomplete reason=probe-unreviewed-envelope status=0x8000000000000003\n'
                'probe targets=0001 cfg-incomplete=0000\ngops=0001\n'
                'capture-complete=0\ndiagnostic-result status=0x8000000000000006\n')
        result, receipt, output = self.run_launcher(sys.executable, text)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(receipt['checker_exit'], 2)
        report = json.loads((output / 'report.json').read_text(encoding='utf-8'))
        codes = [x['code'] for x in report['checks']]
        self.assertIn('probe_envelope_refused', codes)
        self.assertNotIn('invalid_graph', codes)
        self.assertEqual(report['status'], 'invalid_data')
        self.assertIs(report['hardware_tested'], False)
        self.assertIs(report['write_eligible'], False)

    def test_non_python_application_is_rejected_before_checker(self):
        result, receipt, output = self.run_launcher(shutil.which('where.exe'))
        self.assertEqual(result.returncode, 1)
        self.assertEqual(receipt['phase'], 'python-check')
        self.assertEqual(receipt['status'], 'FAILED')
        self.assertIsNone(receipt['checker_exit'])
        self.assertFalse((output / 'report.json').exists())


if __name__ == '__main__':
    unittest.main()
