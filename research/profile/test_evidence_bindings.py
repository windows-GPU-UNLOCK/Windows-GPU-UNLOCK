import hashlib
import importlib.util
import json
from pathlib import Path
import unittest
import subprocess
import sys
import tempfile
from unittest.mock import patch, mock_open
from types import SimpleNamespace

spec = importlib.util.spec_from_file_location('binding', Path(__file__).with_name('review-evidence-bindings.py'))
binding = importlib.util.module_from_spec(spec);spec.loader.exec_module(binding)


def sample():
    profile = {'ProfileName': 'LOCAL-example', 'HeaderSha256': 'a'*64, 'PromSha256': 'b'*64,
               'Replay': {'RtxId': '220410de', 'Segment': 0, 'NoEdidDriver': False, 'Aggregate': False, 'ChildCount': 1}}
    raw = json.dumps(profile).encode();digest = hashlib.sha256(raw).hexdigest()
    tree = hashlib.sha256(('internal-boot/a.c '+'c'*64+'\n').encode()).hexdigest()
    receipt = {'Format': 2, 'AllPassed': True, 'HardwareAccess': False, 'ProfileName': 'LOCAL-example',
               'HeaderSha256': 'a'*64, 'PromSha256': 'b'*64, 'ProfileReportSha256': digest, 'TreeSha256': tree,
               'Inputs': [{'Path': 'internal-boot/a.c', 'Sha256': 'c'*64}],
               'Results': {'pass': {'Exit': 0, 'Expected': 0}, 'intentional refusal': {'Exit': 1, 'Expected': 1}}}
    audit = {'Test': 'existing-profile-evidence-review-v1', 'HostEvidenceBindingsMatch': True,
             'ProfileName': 'LOCAL-example', 'HeaderSha256': 'a'*64, 'PromSha256': 'b'*64,
             'ProfileReportSha256': digest, 'SourceTreeSha256': tree, 'SourceInputCount': 1, 'ExpectedHostJobCount': 2,
             'TargetPci': '220410de', 'Segment': 0, 'NoEdidDriver': False, 'ConsoleAggregate': False, 'ChildCount': 1,
             'NumericHeaderPins': {'TargetBus': '1', 'RootPortDevice': '1', 'RootPortFunction': '1', 'Bar0Base': 'fb000000', 'Bar0End': 'fbffffff'}}
    for k in ['ExistingRepoCodeExecuted', 'HostTestsRerun', 'CaptureFilesChanged', 'HardwareIndependentlyVerified', 'RecoveryVerified', 'WriteEligible']:
        audit[k] = False
    return audit, profile, receipt, raw


class Tests(unittest.TestCase):
    def test_binding_and_intended_refusal(self):
        r = binding.compare(*sample())
        self.assertEqual(r['status'], 'consistent')
        self.assertFalse(r['profile_admitted'])
        self.assertFalse(r['write_eligible'])

    def test_mismatches_refuse(self):
        for change in ['scope', 'count', 'tree', 'header', 'job', 'pin', 'duplicate', 'replay', 'bytes']:
            a, p, r, raw = sample()
            if change == 'scope': a['WriteEligible'] = True
            if change == 'count': a['SourceInputCount'] = 2
            if change == 'tree': r['Inputs'][0]['Sha256'] = 'd'*64
            if change == 'header': r['HeaderSha256'] = 'd'*64
            if change == 'job': r['Results']['pass']['Exit'] = 1
            if change == 'pin': a['NumericHeaderPins']['RootPortFunction'] = '8'
            if change == 'duplicate': r['Inputs'] *= 2
            if change == 'replay': a['TargetPci'] = 'PRIVATE'
            if change == 'bytes': raw += b' '
            with self.subTest(change=change), self.assertRaises(ValueError): binding.compare(a, p, r, raw)


    def check_mutation(self, mutate):
        a, p, r, _ = sample()
        mutate(a, p, r)
        raw = json.dumps(p).encode()
        a['ProfileReportSha256'] = r['ProfileReportSha256'] = hashlib.sha256(raw).hexdigest()
        with self.assertRaises(ValueError):
            binding.compare(a, p, r, raw)

    def test_absent_replay_and_audit_fields(self):
        def mutate(a, p, r):
            del p['Replay']
            for key in ['TargetPci', 'Segment', 'NoEdidDriver', 'ConsoleAggregate', 'ChildCount']:
                del a[key]
        self.check_mutation(mutate)

    def test_paired_missing_null_and_wrong_types(self):
        fields = [('TargetPci', 'RtxId', ['220410de'], 220410),
                  ('Segment', 'Segment', False, 0.0, '0'),
                  ('NoEdidDriver', 'NoEdidDriver', 0, 0.0, 'false'),
                  ('ConsoleAggregate', 'Aggregate', 0, 0.0, 'false'),
                  ('ChildCount', 'ChildCount', True, 1.0, '1')]
        for akey, pkey, *bad_values in fields:
            for value in [None, *bad_values]:
                with self.subTest(field=akey, value=value):
                    self.check_mutation(lambda a, p, r: (a.update({akey: value}), p['Replay'].update({pkey: value})))
            with self.subTest(field=akey, missing=True):
                self.check_mutation(lambda a, p, r: (a.pop(akey), p['Replay'].pop(pkey)))
        for value in [None, '', 1, [], {}]:
            with self.subTest(profile_name=value):
                self.check_mutation(lambda a, p, r: [d.update(ProfileName=value) for d in (a, p, r)])

    def test_numeric_coercion(self):
        for key, values in [('Format', [2.0, '2', True]), ('SourceInputCount', [True, 1.0, '1']),
                            ('ExpectedHostJobCount', [2.0, '2', True])]:
            for value in values:
                with self.subTest(key=key, value=value):
                    self.check_mutation(lambda a, p, r: (r if key == 'Format' else a).update({key: value}))
        self.check_mutation(lambda a, p, r: a.update(Segment=False))
        self.check_mutation(lambda a, p, r: a.update(ChildCount=True))
        for key in ['Exit', 'Expected']:
            for value in [True, 0.0, '0', None]:
                with self.subTest(job_field=key, value=value):
                    self.check_mutation(lambda a, p, r: r['Results']['pass'].update({key: value}))

    def test_container_shapes(self):
        for index in range(3):
            for value in [None, [], 'PRIVATE', 0, False]:
                args = list(sample()); args[index] = value
                with self.subTest(document=index, value=value), self.assertRaises(ValueError):
                    binding.compare(*args)
        for key, owner in [('Replay', 'profile'), ('NumericHeaderPins', 'audit'),
                           ('Inputs', 'receipt'), ('Results', 'receipt')]:
            for value in [None, 'PRIVATE', 0, False]:
                with self.subTest(key=key, value=value):
                    self.check_mutation(lambda a, p, r: {'profile': p, 'audit': a, 'receipt': r}[owner].update({key: value}))
        for value in [None, [], 'PRIVATE', 0, False]:
            with self.subTest(input_row=value):
                self.check_mutation(lambda a, p, r: r.update(Inputs=[value]))

    def test_actual_read_is_bounded(self):
        limit = 2 * 1024 * 1024
        reader = mock_open(read_data=b' ' * (limit + 1))
        with patch.object(sys, 'argv', ['review', 'synthetic']), \
                patch.object(Path, 'is_file', return_value=True), \
                patch.object(Path, 'is_symlink', return_value=False), \
                patch.object(Path, 'stat', return_value=SimpleNamespace(st_size=1)), \
                patch.object(Path, 'open', reader), self.assertRaises(ValueError):
            binding.main()
        reader().read.assert_called_once_with(limit + 1)

    def test_cli_raw_bytes_and_sanitized_rejection(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            a, p, r, _ = sample()
            raw = b'\xef\xbb\xbf' + json.dumps(p, indent=2).replace('\n', '\r\n').encode() + b'\r\n'
            a['ProfileReportSha256'] = r['ProfileReportSha256'] = hashlib.sha256(raw).hexdigest()
            paths = [root / n for n in ['profile-review.json', 'profile.json', 'host-test-receipt-Format2.json']]
            paths[0].write_bytes(json.dumps(a).encode()); paths[1].write_bytes(raw); paths[2].write_bytes(json.dumps(r).encode())
            def run():
                before = [path.read_bytes() for path in paths]
                result = subprocess.run([sys.executable, '-I', str(Path(binding.__file__)), directory], capture_output=True, text=True)
                self.assertEqual(before, [path.read_bytes() for path in paths])
                return result
            result = run()
            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads(result.stdout)
            self.assertEqual(report['profile_report_sha256'], hashlib.sha256(raw).hexdigest())
            self.assertFalse(report['profile_admitted']); self.assertFalse(report['write_eligible'])
            for bad in [json.dumps(a).replace('"Segment": 0', '"Segment": 0, "Segment": 0').encode(),
                        json.dumps(dict(a, Extra=float('nan'))).encode(),
                        json.dumps(dict(a, Extra=float('inf'))).encode(),
                        (json.dumps(a)[:-1] + ', "Extra": 1e999}').encode(), b'null', b'["PRIVATE"]', b'{"private":', json.dumps(dict(a, NumericHeaderPins='PRIVATE')).encode()]:
                paths[0].write_bytes(bad)
                result = run()
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, '')
                self.assertEqual(result.stderr, 'Reported evidence bindings stopped; preserve files. No hardware action requested.\n')
            paths[0].write_bytes(json.dumps(a).encode())
            paths[1].write_bytes(raw + b' ')
            self.assertEqual(run().returncode, 1)


if __name__ == '__main__': unittest.main()
