import importlib.util
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('review', Path(__file__).with_name('review-command-log.py'))
m = importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
BASE = ('[Decode] PCI Command before: 0x0\n[Decode] PCI Command after: 0x2 (IO=DISABLED)\n'
        'restore PCI command: actual=0x2 original=0x2 mask=0x6\n'
        'Transaction result=0 safe=1 retained=0 started=1 quiesced=1 flrs=1 DMA_live=0\n')


class Tests(unittest.TestCase):
    def test_transaction_restore_is_not_wrapper_restore(self):
        r = m.review(BASE)
        self.assertTrue(r['transaction_original_differs_from_wrapper_entry'])
        self.assertFalse(r['wrapper_entry_restoration_verified'])
        self.assertFalse(r['write_eligible'])
        self.assertNotIn('PRIVATE', str(m.review(BASE+'PRIVATE PATH\n')))

    def test_failed_before_firmware_can_retain_dma(self):
        text = BASE.replace('0x2 (IO=DISABLED)', '0x3 (IO=ENABLED)').replace('restore PCI command: actual=0x2 original=0x2 mask=0x6\n', '').replace('result=0 safe=1 retained=0 started=1 quiesced=1 flrs=1 DMA_live=0', 'result=-5 safe=0 retained=1 started=0 quiesced=0 flrs=0 DMA_live=20612')
        r = m.review(text)
        self.assertEqual(r['transaction']['dma_live'], 20612)
        self.assertEqual(r['transaction']['started'], 0)
        self.assertIsNone(r['restore'])

    def test_missing_duplicate_and_bounds_refuse(self):
        for text in ('', BASE+BASE, BASE.replace('safe=1', 'safe=2'), BASE.replace('0x0\n', '0x10000\n')):
            with self.subTest(text=text[:25]), self.assertRaises(ValueError): m.review(text)

    def test_windows_and_mixed_line_endings(self):
        expected = m.review(BASE)
        for text in (BASE.replace('\n', '\r\n'),
                     BASE.replace('0x0\n', '0x0\r\n'),
                     BASE.replace('mask=0x6\n', 'mask=0x6\r\n')):
            with self.subTest(text=repr(text)):
                self.assertEqual(m.review(text), expected)

    def test_crlf_duplicates_remain_ambiguous(self):
        for text in (BASE + BASE, BASE + 'restore PCI command: actual=0x2 original=0x2 mask=0x6\n'):
            with self.subTest(text=repr(text)), self.assertRaises(ValueError):
                m.review(text.replace('\n', '\r\n'))

    def test_cli_preserves_original_windows_bytes_and_hashes(self):
        failed = BASE.replace('0x2 (IO=DISABLED)', '0x3 (IO=ENABLED)').replace(
            'restore PCI command: actual=0x2 original=0x2 mask=0x6\n', '').replace(
            'result=0 safe=1 retained=0 started=1 quiesced=1 flrs=1 DMA_live=0',
            'result=-5 safe=0 retained=1 started=0 quiesced=0 flrs=0 DMA_live=20612')
        texts = {'RUN0002-fail.TXT': failed, 'RUN0004-ok.TXT': BASE, 'RUN0005-ok.TXT': BASE}
        for bom in (b'', b'\xef\xbb\xbf'):
            with self.subTest(bom=bool(bom)), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                originals = {}
                for name, text in texts.items():
                    raw = bom + text.replace('\n', '\r\n').encode('utf-8')
                    originals[name] = raw
                    (root / name).write_bytes(raw)
                result = subprocess.run(
                    [sys.executable, '-I', '-B', str(Path(m.__file__)), str(root)],
                    capture_output=True, text=True, check=False)
                self.assertEqual(result.returncode, 0, result.stderr)
                report = json.loads(result.stdout)
                self.assertFalse(report['write_eligible'])
                self.assertEqual(len(report['logs']), 3)
                for row in report['logs']:
                    raw = originals[row['file']]
                    self.assertEqual(row['sha256'], hashlib.sha256(raw).hexdigest())
                    self.assertEqual((root / row['file']).read_bytes(), raw)
                    self.assertFalse(row['hardware_independently_verified'])
                    self.assertFalse(row['write_eligible'])
                self.assertEqual(report['logs'][0]['transaction']['dma_live'], 20612)
                self.assertTrue(report['logs'][1]['transaction_original_differs_from_wrapper_entry'])


if __name__ == '__main__': unittest.main()
