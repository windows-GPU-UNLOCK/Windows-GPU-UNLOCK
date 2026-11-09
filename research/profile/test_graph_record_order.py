"""Synthetic regressions for graph framing; no firmware or hardware execution."""
import importlib.util
from pathlib import Path
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('order_fixtures', HERE / 'test_compatibility.py')
fixtures = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixtures)


class GraphRecordOrderTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.CompatibilityTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.fixture.populate()

    def test_valid_producer_order_stays_candidate(self):
        self.assertEqual(self.fixture.result()['status'], 'candidate')

    def test_completion_cannot_precede_graph(self):
        self.assert_invalid_order('capture-complete=1\n', prepend=True)

    def test_success_result_cannot_precede_graph(self):
        self.assert_invalid_order('diagnostic-result status=0x0000000000000000\n', prepend=True)

    def test_graph_header_cannot_follow_records(self):
        self.assert_invalid_order(
            'gpu-console-graph-v1 observational-only; no-detach no-unlock no-nvram-write\n',
            prepend=False)

    def test_trailing_partial_graph_is_rejected(self):
        for tail in ('handle id=0xff\n', 'protocol guid=broken\n',
                     'opens status=0x0 count=0x0\n',
                     'pci config-status=0x0000000000000000\n',
                     'path-node raw=7fff0400\n'):
            with self.subTest(tail=tail):
                self.fixture.populate()
                for path in self.fixture.folder.glob('DIAG*.TXT'):
                    path.write_text(path.read_text() + tail)
                self.assertEqual(self.fixture.result()['status'], 'invalid_data')

    def test_truncated_and_control_delimited_outside_records_are_rejected(self):
        for row in ('opens', 'open', 'handle', 'opens-status=broken',
                    'open\t', 'protocol\tguid=broken',
                    'protocol guid=broken', 'cfg dwords=broken', 'mmio broken',
                    'pci-attributes broken', 'probe-target broken',
                    'binding handle=broken', 'img dump index=00'):
            for separator in ('\n', '\v', '\f', '\x85', '\u2028', '\u2029'):
                with self.subTest(row=row, separator=repr(separator)):
                    self.fixture.populate()
                    for path in self.fixture.folder.glob('DIAG*.TXT'):
                        path.write_text(path.read_text() + separator + row + '\n', encoding='utf-8')
                    result = self.fixture.result()
                    self.assertEqual(result['status'], 'invalid_data')
                    self.assertIs(result['hardware_tested'], False)
                    self.assertIs(result['write_eligible'], False)

    def test_ordinary_unicode_transport_prose_is_allowed(self):
        for path in self.fixture.folder.glob('DIAG*.TXT'):
            path.write_text('상태: 정상\u2028Transport ready\n' + path.read_text() +
                            '\x85메모: 완료\vTransport ended\n', encoding='utf-8')
        self.assertEqual(self.fixture.result()['status'], 'candidate')

    def test_surrounding_transport_and_handoff_logs_are_allowed(self):
        for path in self.fixture.folder.glob('DIAG*.TXT'):
            text = path.read_text()
            path.write_text('transport log begins\nprepare status=0x0\n' + text +
                            'windows status=0x0\nhandoff-stopped status=0x0')
        self.assertEqual(self.fixture.result()['status'], 'candidate')

    def test_control_separators_cannot_frame_the_header(self):
        marker = 'gpu-console-graph-v1 observational-only; no-detach no-unlock no-nvram-write'
        for separator in ('\v', '\f', '\x85', '\u2028', '\u2029'):
            with self.subTest(separator=repr(separator)):
                self.fixture.populate()
                for path in self.fixture.folder.glob('DIAG*.TXT'):
                    text = path.read_text().replace(marker + '\n', marker + separator, 1)
                    path.write_text(text, encoding='utf-8')
                self.assertEqual(self.fixture.result()['status'], 'invalid_data')

    def test_no_final_newline_is_allowed(self):
        for path in self.fixture.folder.glob('DIAG*.TXT'):
            path.write_text(path.read_text().rstrip('\n'))
        self.assertEqual(self.fixture.result()['status'], 'candidate')

    def assert_invalid_order(self, token, *, prepend):
        for path in self.fixture.folder.glob('DIAG*.TXT'):
            text = path.read_text(encoding='ascii')
            self.assertEqual(text.count(token), 1)
            text = text.replace(token, '')
            path.write_text(token + text if prepend else text + token, encoding='ascii')
        result = self.fixture.result()
        self.assertEqual(result['status'], 'invalid_data', result['checks'])
        self.assertIs(result['hardware_tested'], False)
        self.assertIs(result['write_eligible'], False)


if __name__ == '__main__':
    unittest.main()
