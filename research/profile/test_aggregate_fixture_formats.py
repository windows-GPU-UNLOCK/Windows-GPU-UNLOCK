"""Capture-free fixture regressions for #225, #302 and #368.

All records are synthesized from the existing topology model. No firmware,
private capture, hardware access, or LOCAL write-evidence file is involved.
"""
import importlib.util
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('aggregate_format_data', HERE / 'test_local_topology.py')
data = importlib.util.module_from_spec(spec)
spec.loader.exec_module(data)
GENERATOR = HERE.parents[1] / 'internal-boot/boot/make-console-fixture.py'


def current_format(text):
    """Use diagnostic.c's driver fields and first-node-only path prefix."""
    bindings = data.mp.parse_bindings(text.splitlines())

    def driver(match):
        binding = data.mp.binding_for(bindings, int(match[2], 16))
        return match[0] + f" version=0x{binding['version']:x} stop-address=0x{binding['stop']:x}"

    text = re.sub(r'^driver image=0x([0-9a-f]+) binding=0x([0-9a-f]+)$', driver, text, flags=re.M)
    return re.sub(r'(image-file-path-node raw=[0-9a-f]+\n)image-file-path-node raw=',
                  r'\1path-node raw=', text)


def unrelated_first(text):
    """A firmware enumeration need not put the GPU's ownership edge first."""
    match = re.search(r'^handle id=0x8\n.*?(?=^handle id=|^capture-complete=)', text, re.M | re.S)
    block = match[0]
    text = text[:match.start()] + text[match.end():]
    at = text.index('handle id=')
    return text[:at] + block + text[at:]


class AggregateFixtureFormatTests(unittest.TestCase):
    def generate(self, text, success=True):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / 'DIAG00.TXT'
            target = Path(folder) / 'fixture.h'
            source.write_text(text, encoding='ascii')
            result = subprocess.run([sys.executable, '-I', str(GENERATOR), str(source),
                                     '--aggregate', '--single-rtx', '--no-igpu', '--no-edid-child',
                                     '--output=' + str(target)], capture_output=True, text=True)
            if success:
                self.assertEqual(result.returncode, 0, result.stderr)
                return target.read_text()
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertFalse(target.exists(), 'Refusal must not publish a partial fixture')

    def test_legacy_and_current_formats_produce_the_same_replay(self):
        for children in (1, 2):
            with self.subTest(children=children):
                legacy = data.synthetic_capture(aggregate=True, no_edid=False, children=children)
                expected = self.generate(legacy).splitlines()[1:]
                self.assertEqual(self.generate(current_format(legacy)).splitlines()[1:], expected)

    def test_current_driver_fields_are_mandatory_when_present_and_must_match(self):
        text = current_format(data.synthetic_capture(aggregate=True, no_edid=False))
        row = re.search(r'^driver image=.*$', text, re.M)[0]
        variants = [
            re.sub(r' version=0x[0-9a-f]+', ' version=0xffffffff', row),
            re.sub(r' stop-address=0x[0-9a-f]+', ' stop-address=0x1', row),
            re.sub(r' stop-address=0x[0-9a-f]+', '', row),
            re.sub(r' version=0x[0-9a-f]+', '', row),
            row + ' unexpected=1',
            row + '\n' + row,
            row + '\ndriver image=malformed',
        ]
        for changed in variants:
            with self.subTest(changed=changed):
                self.generate(text.replace(row, changed, 1), success=False)

    def test_complete_image_path_including_terminator_remains_required(self):
        text = current_format(data.synthetic_capture(aggregate=True, no_edid=False))
        path = re.search(r'^image-file-path-node raw=[0-9a-f]+\npath-node raw=7fff0400\n', text, re.M)[0]
        variants = [
            path.replace('path-node raw=7fff0400\n', ''),
            path.replace('7fff0400', '7fff0401'),
            path.replace('image-file-', '', 1),
            path.replace('\npath-node', '\nnot-a-path-node\npath-node'),
            path + path,
            path + 'unrelated-record\n' + path,
        ]
        for changed in variants:
            with self.subTest(changed=changed):
                self.generate(text.replace(path, changed, 1), success=False)

    def test_target_edge_is_first_without_dropping_unrelated_ownership(self):
        for children in (1, 2):
            with self.subTest(children=children):
                text = unrelated_first(current_format(data.synthetic_capture(
                    aggregate=True, no_edid=False, children=children)))
                parsed = data.mp.parse_handles(text)
                ordinal = {handle: index + 1 for index, handle in enumerate(parsed)}
                self.assertEqual(next(iter(parsed)), 8)
                header = self.generate(text)
                rows = header.split('static const EDGE FixtureEdges[]={\n', 1)[1].split('};', 1)[0].splitlines()
                self.assertTrue(rows[0].startswith(
                    f'{{(EFI_HANDLE){ordinal[1]},(EFI_HANDLE){ordinal[3]},(EFI_HANDLE){ordinal[1]},'
                    '{0x4cf5b200,0x68b8,0x4ca5,'), rows[0])
                self.assertTrue(rows[0].endswith(',16,1},'))
                protected = (f'{{(EFI_HANDLE){ordinal[8]},(EFI_HANDLE){ordinal[10]},'
                             f'(EFI_HANDLE){ordinal[8]},{{0x12345678,')
                self.assertEqual(sum(row.startswith(protected) for row in rows), 1)
                expected_count = sum(edge[3] not in (1, 2, 4)
                                     for block in parsed.values() for edge in block['edges'])
                self.assertEqual(len(rows), expected_count)


if __name__ == '__main__':
    unittest.main()
