"""Synthetic results and Python-only child processes; no compiler/firmware/hardware."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch
import tempfile
import hashlib

spec = importlib.util.spec_from_file_location('decode_runner', Path(__file__).with_name('test-decode-sync.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class MutationEvidenceTests(unittest.TestCase):
    def result(self, code=0, stdout='', stderr=''):
        return subprocess.CompletedProcess(['synthetic'], code, stdout.encode('utf-8'), stderr.encode('utf-8'))

    def test_explicit_expected_assertion(self):
        self.assertEqual(runner.require_mutation_detection(
            self.result(), self.result(1, stderr='FAIL expected guard\n'), 'expected guard'),
            {'exit': 1, 'assertion': 'expected guard'})

    def test_reject_other_process_outcomes(self):
        cases = [
            self.result(0), self.result(0, stderr='FAIL expected guard\n'),
            self.result(-11), self.result(-6, stderr='FAIL expected guard\n'),
            self.result(139, stderr='FAIL expected guard\n'),
            self.result(3221225477, stderr='FAIL expected guard\n'),
            self.result(2, stderr='FAIL expected guard\n'),
            self.result(1), self.result(1, stderr='FAIL other guard\n'),
            self.result(1, stdout='FAIL expected guard\n'),
            self.result(1, stderr='prefix FAIL expected guard\n'),
            self.result(1, stderr='FAIL expected guard\nextra diagnostic\n'),
            self.result(1, stderr='FAIL expected guard'),
            self.result(1, stderr='FAIL expected guard\v'),
            self.result(1, stderr='FAIL expected guard\x85'),
            self.result(1, stderr='FAIL expected guard\u2028'),
        ]
        for result in cases:
            with self.subTest(result=result), self.assertRaises(RuntimeError):
                runner.require_mutation_detection(self.result(), result, 'expected guard')

    def test_windows_line_ending(self):
        self.assertEqual(runner.require_mutation_detection(
            self.result(), self.result(1, stderr='FAIL expected guard\r\n'), 'expected guard'),
            {'exit': 1, 'assertion': 'expected guard'})

    def test_compiler_failure_is_not_detection(self):
        with self.assertRaises(RuntimeError):
            runner.require_mutation_detection(self.result(1),
                self.result(1, stderr='FAIL expected guard\n'), 'expected guard')


class MutantCaptureTests(unittest.TestCase):
    def test_actual_subprocess_output_contract(self):
        endings = (b'\n', b'\r\n', b'\r', b'', b'\v', b'\x85', b'\xe2\x80\xa8')
        compiled = subprocess.CompletedProcess([], 0, b'', b'')
        with tempfile.TemporaryDirectory() as folder:
            log = Path(folder) / 'run.log'
            for ending in endings:
                with self.subTest(ending=ending):
                    raw = b'FAIL expected guard' + ending
                    command = [sys.executable, '-I', '-B', '-c',
                               f'import sys; sys.stderr.buffer.write({raw!r}); sys.exit(1)']
                    tested = runner.capture_mutant(command, log)
                    self.assertEqual(tested.stderr, raw)
                    self.assertEqual(log.read_bytes(), raw)
                    if ending in (b'\n', b'\r\n'):
                        self.assertEqual(runner.require_mutation_detection(compiled, tested, 'expected guard'),
                                         {'exit': 1, 'assertion': 'expected guard'})
                    else:
                        with self.assertRaises(RuntimeError):
                            runner.require_mutation_detection(compiled, tested, 'expected guard')


class IdentityTests(unittest.TestCase):
    def test_bounded_hashes_and_private_paths(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            here = root / 'research/pci-decode'
            here.mkdir(parents=True)
            shared = root / 'internal-boot/unlock/gpu-path.h'
            shared.parent.mkdir(parents=True)
            shared.write_text('shared')
            (here / 'fixture.c').write_text('fixture')
            script = here / 'test-decode-sync.py'
            script.write_text('runner')
            compiler = root / 'compiler-wrapper'
            compiler.write_text('synthetic wrapper')
            version = subprocess.CompletedProcess([], 0,
                b'/home/alice/private-sdk token=sample-not-a-secret\nInstalledDir: /private\n',
                b'private stderr information')
            def query_version(*args, **kwargs):
                if kwargs.get('text'):
                    return subprocess.CompletedProcess([], 0, version.stdout.decode(), version.stderr.decode())
                return version

            with patch.object(runner, 'ROOT', root), patch.object(runner, 'HERE', here), \
                    patch.object(runner, '__file__', str(script)), \
                    patch.object(runner.shutil, 'which', return_value=str(compiler)), \
                    patch.object(runner.subprocess, 'run', side_effect=query_version):
                identity = runner.collect_identity(str(compiler), [str(compiler), '-I', str(here)])
            self.assertEqual(identity['source_sha256']['research/pci-decode/fixture.c'],
                             hashlib.sha256(b'fixture').hexdigest())
            self.assertEqual(identity['compiler_command_sha256'], hashlib.sha256(b'synthetic wrapper').hexdigest())
            self.assertEqual(identity['explicit_flags'], ['-I', '<repo>/research/pci-decode'])
            for private in ('alice', 'sample-not-a-secret', 'private stderr information'):
                self.assertNotIn(private, str(identity))
            self.assertNotIn('compiler_command_name', identity)
            self.assertNotIn('compiler_version_first_line', identity)
            self.assertEqual(identity['compiler_version_stdout_sha256'], hashlib.sha256(version.stdout).hexdigest())
            self.assertEqual(identity['compiler_version_stderr_sha256'], hashlib.sha256(version.stderr).hexdigest())
            self.assertNotIn(folder, str(identity))
            self.assertNotIn('/private', str(identity))

    def test_failed_version_query_refuses_summary(self):
        for result in (subprocess.CompletedProcess([], 1, b'', b'error'),
                       subprocess.CompletedProcess([], 0, b'', b'')):
            with self.subTest(result=result), \
                    patch.object(runner.subprocess, 'run', return_value=result), \
                    self.assertRaises(RuntimeError):
                runner.collect_identity('synthetic', ['synthetic'])


if __name__ == '__main__':
    unittest.main()
