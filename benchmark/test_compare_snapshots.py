"""Saved-file race, size and privacy checks; no GPU, CUDA or firmware access."""
import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import compare_results as reader
from test_compare_results import fixture, seal, write_json


class SnapshotTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='private-benchmark-test-')
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.before, self.after = root / 'before', root / 'after'
        fixture(self.before)
        fixture(self.after, (1.01, 1.65, 1.65))

    def compare(self):
        return reader.compare(self.before, self.after, same_machine_confirmed=True)

    def test_edit_between_verification_and_parsing_cannot_change_results(self):
        expected = self.compare()
        real = reader.read_json
        changed = []

        def edit_then_parse(path, *args, **kwargs):
            if path.parent == self.after and path.name.startswith('trial-'):
                value = json.loads(path.read_text(encoding='utf-8-sig'))
                for benchmark in value['benchmarks']:
                    for key in ('median_ms', 'min_ms', 'max_ms'):
                        benchmark[key] /= 3
                    benchmark['gflops'] *= 3
                write_json(path, value)
                changed.append(path.name)
            return real(path, *args, **kwargs)

        with patch.object(reader, 'read_json', side_effect=edit_then_parse):
            result = self.compare()
        self.assertEqual(len(changed), 3)
        self.assertEqual(result, expected)
        # Later calls must read fresh evidence and reject those unsealed edits.
        with self.assertRaisesRegex(ValueError, 'changed after run completion'):
            self.compare()

    def test_context_edit_after_hashing_is_not_parsed(self):
        real = reader.read_json

        def edit_then_parse(path, *args, **kwargs):
            if path.name == 'comparison-context.json':
                value = json.loads(path.read_text(encoding='utf-8-sig'))
                value['gpu_settings'][3] = '250.00'
                write_json(path, value)
            return real(path, *args, **kwargs)

        with patch.object(reader, 'read_json', side_effect=edit_then_parse):
            context, _, _ = reader.load_run(self.after)
        self.assertEqual(context['gpu_settings'][3], '350.00')

    def test_required_files_are_read_once_and_not_changed(self):
        originals = {path: path.read_bytes() for path in self.after.iterdir()}
        with patch.object(reader, 'read_result', wraps=reader.read_result) as reads:
            reader.load_run(self.after)
        self.assertEqual(len(reads.call_args_list), 5)
        self.assertEqual({call.args[0] for call in reads.call_args_list}, set(originals))
        self.assertEqual({path: path.read_bytes() for path in originals}, originals)

    def test_every_required_file_is_size_bounded(self):
        for name in ('comparison-complete.json', 'comparison-context.json',
                     'trial-1.json', 'trial-2.json', 'trial-3.json'):
            with self.subTest(name=name):
                path = self.after / name
                original = path.read_bytes()
                path.write_bytes(b' ' * (reader.MAX_RESULT_BYTES + 1))
                if name != 'comparison-complete.json':
                    seal(self.after)
                with self.assertRaisesRegex(ValueError, '1 MiB limit'):
                    reader.load_run(self.after)
                path.write_bytes(original)
                seal(self.after)

    def test_nonregular_result_is_refused_without_reading(self):
        path = self.after / 'trial-1.json'
        path.unlink()
        path.mkdir()
        with self.assertRaisesRegex(ValueError, 'regular result file'):
            reader.load_run(self.after)

    def test_valid_json_at_the_size_limit_still_loads(self):
        path = self.after / 'comparison-context.json'
        raw = path.read_bytes()
        path.write_bytes(raw + b' ' * (reader.MAX_RESULT_BYTES - len(raw)))
        seal(self.after)
        reader.load_run(self.after)

    def test_replacement_between_stat_and_open_is_refused(self):
        target = self.after / 'trial-1.json'
        replacement = self.after / 'replacement.json'
        replacement.write_bytes(target.read_bytes())
        real = Path.lstat
        replaced = []

        def replace_after_stat(path, *args, **kwargs):
            info = real(path, *args, **kwargs)
            if path == target and not replaced:
                replacement.replace(target)
                replaced.append(True)
            return info

        with patch.object(Path, 'lstat', autospec=True, side_effect=replace_after_stat):
            with self.assertRaisesRegex(ValueError, 'changed while opening'):
                reader.load_run(self.after)
        self.assertEqual(replaced, [True])

    def test_symlink_result_is_refused(self):
        path = self.after / 'trial-1.json'
        payload = self.after / 'saved-trial.json'
        path.rename(payload)
        try:
            path.symlink_to(payload.name)
        except OSError:
            self.skipTest('This host cannot create a file symlink')
        with self.assertRaisesRegex(ValueError, 'regular result file'):
            reader.load_run(self.after)

    def test_invalid_encoding_nesting_and_nonfinite_metadata_are_refused(self):
        path = self.after / 'comparison-context.json'
        original = path.read_bytes()
        cases = [b'\xffPRIVATE-CONTENT', b'[' * 1200 + b'0' + b']' * 1200,
                 original.replace(b'"cuda_runtime": 12060', b'"extra": NaN, "cuda_runtime": 12060'),
                 original.replace(b'"cuda_runtime": 12060', b'"extra": 1e1000, "cuda_runtime": 12060')]
        for raw in cases:
            with self.subTest(raw=raw[:30]):
                path.write_bytes(raw)
                seal(self.after)
                with self.assertRaises(ValueError):
                    reader.load_run(self.after)
        path.write_bytes(original)
        seal(self.after)

    def test_cli_does_not_reveal_private_path_or_duplicate_key(self):
        path = self.after / 'comparison-complete.json'
        for raw in (None, b'{"PRIVATE-CONTENT":1,"PRIVATE-CONTENT":2}'):
            with self.subTest(raw=raw):
                if raw is None:
                    path.unlink()
                else:
                    path.write_bytes(raw)
                out, err = io.StringIO(), io.StringIO()
                with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                    status = reader.main([str(self.before), str(self.after), '--same-machine-confirmed'])
                self.assertEqual(status, 2)
                self.assertEqual(out.getvalue(), '')
                self.assertNotIn(self.temp.name, err.getvalue())
                self.assertNotIn('PRIVATE-CONTENT', err.getvalue())
                self.assertIn('Comparison refused', err.getvalue())


if __name__ == '__main__':
    unittest.main()
