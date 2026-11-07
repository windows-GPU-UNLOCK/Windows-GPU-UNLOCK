"""Offline graph export regressions; no firmware or GPU access."""
import importlib.util
import json
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('graph_summary', Path(__file__).with_name('summarize-graph.py'))
graph = importlib.util.module_from_spec(spec)
spec.loader.exec_module(graph)


class GraphSummaryTests(unittest.TestCase):
    def test_graph_relationships_survive_without_raw_paths(self):
        data = (b'handle id=0x1234\nopen agent=0x5 controller=0x6 attributes=0x8 count=0x1\n'
                b'path-node raw=PRIVATE-GUID\nimage-file-path PRIVATE-NAME\n'
                b'image PRIVATE-USER=0x1234\nimage username=0x1234\n'
                b'capture-complete=0\ndiagnostic-result status=0x8000000000000006\n')
        result = graph.summarize(data)
        self.assertEqual(len(result['records']), 2)
        self.assertNotIn('PRIVATE', json.dumps(result))
        self.assertNotIn('username', json.dumps(result))
        self.assertEqual(result['complete_markers'], ['0'])
        self.assertFalse(result['graph_only_marker'])

    def test_pci_header_and_conflicting_footers_are_preserved_as_observations(self):
        line = 'pci config-dwords=' + '220410de ' * 16
        result = graph.summarize((line + '\ncapture-complete=1\ncapture-complete=0\n').encode())
        self.assertEqual(result['records'], [line.rstrip()])
        self.assertEqual(result['complete_markers'], ['1', '0'])

    def test_failure_reasons_survive_without_private_text(self):
        data = (b'incomplete reason=gop-info status=0x8000000000000006\n'
                b'incomplete reason=PRIVATE-PATH status=0x8000000000000006\n'
                b'incomplete reason=gop-info status=PRIVATE\n'
                b'capture-complete=0\n'
                b'diagnostic-result status=0x8000000000000006\n')
        result = graph.summarize(data)
        self.assertEqual(result['incomplete_reason_count'], 3)
        self.assertEqual(result['incomplete_reasons'], [
            {'reason': 'gop-info', 'status': '0x8000000000000006'}])
        self.assertEqual(result['unexported_reason_count'], 2)
        self.assertEqual(result['complete_markers'], ['0'])
        self.assertNotIn('PRIVATE', json.dumps(result))

    def test_duplicate_and_conflicting_reasons_are_not_deduplicated(self):
        result = graph.summarize(
            b'incomplete reason=gop-info status=0x8000000000000006\n'
            b'incomplete reason=gop-info status=0x8000000000000007\n')
        self.assertEqual(len(result['incomplete_reasons']), 2)
        self.assertEqual(result['unexported_reason_count'], 0)

    def test_device_path_pci_routing_without_payloads_or_variable_paths(self):
        data = (b'path-node raw=010106000001\n'  # console variable, no handle
                b'handle id=0x1234\n'
                b'protocol guid=09576e91-6d3f-11d2-8e39-00a0c969723b\n'
                b'path-node raw=010106000001\n'
                b'path-node raw=01041500505249564154452d475549442d44415441\n'
                b'path-node raw=7f010400\n'
                b'image-file-path-node raw=0404040050524956415445\n'
                b'protocol guid=9042a9de-23dc-4a38-96fb-7aded080516a\n'
                b'path-node raw=010106000002\n'
                b'incomplete reason=gop-info status=0x8000000000000006\n')
        result = graph.summarize(data)
        paths = [r for r in result['records'] if r.startswith('path-node ')]
        self.assertEqual(paths, [
            'path-node type=0x01 subtype=0x01 bytes=0x0006 function=0x00 device=0x01',
            'path-node type=0x01 subtype=0x04 bytes=0x0015',
            'path-node type=0x7f subtype=0x01 bytes=0x0004'])
        self.assertTrue(result['records'][-1].startswith('incomplete reason=gop-info'))
        self.assertNotIn('50524956415445', json.dumps(result))
        self.assertNotIn('raw=', json.dumps(result))

    def test_invalid_pci_nodes_or_lengths_are_not_interpreted(self):
        for line in ('path-node raw=010106000801', 'path-node raw=010106000020',
                     'path-node raw=010107000001', 'path-node raw=0101060000010'):
            self.assertIsNone(graph.path_observation(line))

    def test_invalid_encoding_is_not_repaired(self):
        with self.assertRaises(UnicodeError):
            graph.summarize(b'\x8f')


if __name__ == '__main__':
    unittest.main()
