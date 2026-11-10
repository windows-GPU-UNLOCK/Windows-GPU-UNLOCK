"""Synthetic intake/comparison regressions, never hardware evidence."""
import copy
import importlib.util
import json
from pathlib import Path
import re
import unittest

HERE = Path(__file__).resolve().parent


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


fixtures = load('parent_intake_fixtures', 'test_compatibility.py')
comparison = load('parent_intake_comparison', 'compare-compatibility.py')


def baseline(text, depth=1, attrs=0x200):
    cfg = [int(word, 16) for word in re.search(r'^cfg dwords=(.*)$', text, re.M)[1].split()]
    target = re.search(r'^probe-target seg=0x([0-9a-f]+) bus=0x([0-9a-f]+)', text, re.M)
    segment, bus = (int(v, 16) for v in target.groups())
    rows = [f'parent-baseline status=0x0000000000000000 available=1 parents=0x{depth:02x}']
    configs = [cfg]
    for index in range(depth):
        parent = [0] * 64
        parent[0], parent[1], parent[2], parent[3] = 0x12348086, 7, 0x06040001, 0x00010000
        parent[6] = index | ((bus if index == depth - 1 else index + 1) << 8) | (255 << 16)
        parent[4], parent[11], parent[20] = 0xdead0000, 0xcafebabe, 0xfedcba98
        configs.append(parent)
    for index, config in enumerate(configs):
        rows.append(f'parent-baseline-device index=0x{index:02x} segment=0x{segment:04x} bus=0x{bus if index == 0 else index-1:02x} device=0x00 function=0x00 attributes=0x{attrs if index == 0 else 0x700:016x} supported=0x0000000000000700')
        rows.append(f'parent-baseline-config index=0x{index:02x} words=' + ' '.join(f'{v:08x}' for v in config) + ' ')
    return '\n'.join(rows) + '\n'


class ParentIntakeTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.CompatibilityTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.text = self.fixture.populate(command=2)

    def report(self, supplemental, text=None):
        for path in self.fixture.folder.glob('DIAG*.TXT'):
            source = self.text if text is None else text
            path.write_text(source.replace('pci-attributes status=', supplemental + 'pci-attributes status=', 1))
        return self.fixture.result()

    def observation(self, report):
        return report['observations'][0]['parent_baseline']

    def field(self, left, right):
        result = comparison.compare(left, right)
        self.assertIs(result['hardware_tested'], False)
        self.assertIs(result['write_eligible'], False)
        return next(row for row in result['fields'] if row['field'] == 'parent_baseline')

    def test_recorded_depth_segment_bus_boundaries_and_trailing_space(self):
        for depth, segment, bus in ((1, 0, 1), (15, 1, 43), (15, 0xffff, 255)):
            with self.subTest(depth=depth, segment=segment, bus=bus):
                text = self.fixture.populate(command=2, bus=bus)
                text = text.replace('probe-target seg=0x0000', f'probe-target seg=0x{segment:04x}')
                text = text.replace('segment=0x0 bus=', f'segment=0x{segment:x} bus=')
                report = self.report(baseline(text, depth), text)
                value = self.observation(report)
                self.assertEqual(value['state'], 'recorded', value)
                self.assertEqual(len(value['devices']), depth + 1)
                self.assertEqual(value['devices'][-1]['secondary_bus'], bus)
                self.assertEqual(report['status'], 'candidate', report)
                self.assertEqual(self.field(report, report)['state'], 'same')

    def test_legacy_missing_unavailable_invalid_never_compare_as_same(self):
        for records, state in (('', 'not_recorded'),
                ('parent-baseline status=0x8000000000000003 available=0 parents=0x00\n', 'unavailable'),
                ('parent-baseline PRIVATE-MALFORMED\n', 'invalid')):
            report = self.report(records)
            self.assertEqual(self.observation(report), {'state': state, 'devices': []})
            self.assertEqual(self.field(report, report)['state'], 'unavailable')
        legacy = copy.deepcopy(report)
        for row in legacy['observations']:
            del row['parent_baseline']
        current = self.report(baseline(self.text))
        self.assertEqual(self.field(legacy, legacy)['state'], 'unavailable')
        self.assertEqual(self.field(legacy, current)['state'], 'unavailable')
        self.assertEqual(self.field(legacy, current)['left'], [None])

    def test_missing_duplicate_reordered_and_malformed_records_preserve_admission(self):
        valid = baseline(self.text)
        rows = valid.splitlines(keepends=True)
        bad = [''.join(rows[:i] + rows[i+1:]) for i in range(len(rows))]
        bad += [valid + row for row in rows]
        bad += [valid.replace('available=1', 'available=0'),
                valid.replace('status=0x0000000000000000', 'status=0x0000000000000001'),
                valid.replace('parents=0x01', 'parents=0x10'),
                valid.replace('index=0x01', 'index=0x02'),
                valid.replace('device=0x00', 'device=0x20'),
                valid.replace('segment=0x0000 bus=0x00', 'segment=0x0001 bus=0x00'),
                valid.replace('12348086 00000007', '12348086 00000003'),
                valid.replace('00ff2b00', '00ff2a00'),
                valid.replace('00010000', '00000000'),
                valid.replace('38811462', '38811463'),
                valid.replace('words=', 'words=ffffffff '),
                valid.replace(' words=', ' words=PRIVATE '),
                valid + 'parent-baseline-unknown PRIVATE\n',
                ' ' + valid,
                ''.join([rows[0], rows[2], rows[1], *rows[3:]])]
        before = self.report('')
        for index, records in enumerate(bad):
            with self.subTest(case=index):
                report = self.report(records)
                self.assertEqual(self.observation(report)['state'], 'invalid')
                for row in report['observations']:
                    row['parent_baseline'] = {'state': 'not_recorded', 'devices': []}
                self.assertEqual(report, before)

    def test_primary_full_config_and_graph_must_agree(self):
        records = baseline(self.text)
        for old, new in (('cfg dwords=220410de', 'cfg dwords=220310de'),
                         ('pci config-dwords=220410de', 'pci config-dwords=220310de'),
                         ('pci location-status=0x0 segment=0x0 bus=0x2b',
                          'pci location-status=0x0 segment=0x0 bus=0x2a')):
            with self.subTest(old=old):
                self.assertEqual(self.observation(self.report(records, self.text.replace(old, new)))['state'], 'invalid')

    def test_private_raw_address_changes_are_not_reported(self):
        records = baseline(self.text)
        left = self.report(records)
        right = self.report(records.replace('dead0000', 'abcd0000').replace('cafebabe', '12345678')
                            .replace('fedcba98', '76543210'))
        self.assertEqual(left, right)
        public = json.dumps(left) + json.dumps(comparison.compare(left, right))
        for private in ('dead0000', 'cafebabe', 'fedcba98', 'abcd0000', '12345678', '76543210'):
            self.assertNotIn(private, public)
        self.assertEqual(self.field(left, right)['state'], 'same')

    def test_auxiliary_attributes_are_not_required_to_match_primary_timing(self):
        # The ancestry collector and ProbeBar's primary pci-attributes record are
        # separate reads; a difference is informational, not an admission veto.
        report = self.report(baseline(self.text, attrs=0x300))
        self.assertEqual(self.observation(report)['state'], 'recorded')
        self.assertEqual(self.observation(report)['devices'][0]['decode_attributes'], 0x300)
        self.assertEqual(report['status'], 'candidate')
        self.assertIs(report['hardware_tested'], False)
        self.assertIs(report['write_eligible'], False)

    def test_bridge_identity_and_decode_differences_are_visible(self):
        records = baseline(self.text)
        left = self.report(records)
        for changed in (records.replace('12348086', '43218086'),
                        records.replace('12348086 00000007', '12348086 00000003')
                               .replace('attributes=0x0000000000000700', 'attributes=0x0000000000000300'),
                        records.replace('bus=0x00 device=0x00', 'bus=0x00 device=0x01')):
            right = self.report(changed)
            self.assertEqual(self.observation(right)['state'], 'recorded')
            self.assertEqual(self.field(left, right)['state'], 'different')

    def test_auxiliary_schema_rejects_address_fields_and_bad_types(self):
        report = self.report(baseline(self.text))
        for change in ('address', 'boolean', 'extra', 'missing', 'length', 'state', 'cycle', 'mask'):
            value = copy.deepcopy(report)
            parent = self.observation(value)
            if change == 'address': parent['devices'][1]['subsystem_id'] = 'cafebabe'
            elif change == 'boolean': parent['devices'][1]['bus'] = False
            elif change == 'extra': parent['private'] = 'PRIVATE'
            elif change == 'missing': del parent['devices'][0]['command']
            elif change == 'length': parent['devices'] *= 16
            elif change == 'state': parent['state'] = 'unavailable'
            elif change == 'cycle': parent['devices'][1]['bus'] = 43
            else: parent['devices'][1]['decode_attributes'] = 0x701
            with self.subTest(change=change), self.assertRaises((ValueError, KeyError, TypeError)):
                comparison.validate(value)


if __name__ == '__main__':
    unittest.main()
