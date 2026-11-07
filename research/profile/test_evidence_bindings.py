import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import unittest

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


if __name__ == '__main__': unittest.main()
