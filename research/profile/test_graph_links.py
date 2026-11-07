import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('links', Path(__file__).with_name('review-graph-links.py'))
links = importlib.util.module_from_spec(spec)
spec.loader.exec_module(links)


def sample():
    rows = ['handle id=0x1', 'protocol guid=' + links.PCI,
            'pci location-status=0x0 segment=0x0 bus=0x0 device=0x2 function=0x0',
            'pci config-status=0x0',
            'pci config-dwords=a7a88086 00000000 03000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000 13b91462 00000000 00000000 00000000 00000000',
            'open agent=0x3 controller=0x2 attributes=0x8 count=0x1',
            'handle id=0x2', 'protocol guid=' + links.GOP, 'gop framebuffer=0x4000 bytes=0x1000']
    return {'test': 'graph-only-v3', 'hardware_verified': False, 'write_eligible': False,
            'captures': [{'sha256': 'a' * 64, 'graph_only_marker': True, 'complete_markers': ['1'],
                          'diagnostic_statuses': ['0x0000000000000000'], 'incomplete_reason_count': 0,
                          'unexported_reason_count': 0, 'records': rows}]}


class Tests(unittest.TestCase):
    def test_link_and_no_raw_export(self):
        r = links.review(sample())
        self.assertEqual(r['captures'][0]['gop_links'][0]['status'], 'unique-protocol-link')
        self.assertEqual(r['captures'][0]['gop_links'][0]['candidate_adapter_indices'], [0])
        self.assertFalse(r['physical_routing_verified'])
        self.assertNotIn('handle', str(r))

    def test_wrong_protocol_and_no_child_edge(self):
        for change in ['protocol', 'attribute']:
            d = sample(); rows = d['captures'][0]['records']
            if change == 'protocol':
                rows.insert(5, 'protocol guid=09576e91-6d3f-11d2-8e39-00a0c969723b')
            else:
                rows[5] = rows[5].replace('attributes=0x8', 'attributes=0x2')
            self.assertEqual(links.review(d)['captures'][0]['gop_links'][0]['status'], 'unresolved')

    def test_ambiguous_and_duplicate(self):
        d = sample(); rows = d['captures'][0]['records']; rows[6:6] = [r.replace('handle id=0x1', 'handle id=0x4') for r in rows[:6]]
        self.assertEqual(links.review(d)['captures'][0]['gop_links'][0]['status'], 'ambiguous')
        d = sample();d['captures'][0]['records'] += ['handle id=0x1']
        with self.assertRaises(ValueError): links.review(d)

    def test_scope_incomplete_bounds(self):
        d = sample();d['write_eligible'] = True
        with self.assertRaises(ValueError): links.review(d)

    def test_device_path_requires_same_sole_driver(self):
        d = sample();rows = d['captures'][0]['records']
        rows[5:6] = ['open agent=0x3 controller=0x1 attributes=0x10 count=0x1',
                     'protocol guid=' + links.DEVICE_PATH,
                     'open agent=0x3 controller=0x2 attributes=0x8 count=0x1']
        r = links.review(d)['captures'][0]['gop_links'][0]
        self.assertEqual(r['status'], 'unresolved')
        self.assertEqual(r['device_path_driver_child_adapter_indices'], [0])
        for old, new in [('agent=0x3 controller=0x2', 'agent=0x4 controller=0x2'),
                         ('attributes=0x10', 'attributes=0x2'), ('attributes=0x8 count=0x1', 'attributes=0x8 count=0x2')]:
            bad = copy.deepcopy(d)
            bad['captures'][0]['records'] = [r.replace(old, new) for r in rows]
            self.assertEqual(links.review(bad)['captures'][0]['gop_links'][0]['device_path_driver_child_status'], 'unresolved')
        bad = copy.deepcopy(d);bad['captures'][0]['records'].insert(5, rows[5])
        self.assertEqual(links.review(bad)['captures'][0]['gop_links'][0]['device_path_driver_child_status'], 'unresolved')
        d = sample();d['captures'][0]['complete_markers'] = ['0']
        self.assertEqual(links.review(d)['captures'][0]['status'], 'incomplete')
        d = sample();d['captures'][0]['records'] += ['PRIVATE' * 1000]
        with self.assertRaises(ValueError): links.review(d)


if __name__ == '__main__': unittest.main()
