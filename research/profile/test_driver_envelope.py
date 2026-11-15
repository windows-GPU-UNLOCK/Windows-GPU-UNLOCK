import copy
import importlib.util
import json
from pathlib import Path
import unittest

here = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('review', here/'review-driver-envelope.py')
review = importlib.util.module_from_spec(spec);spec.loader.exec_module(review)
envelope = json.loads((here/'proven.json').read_text())


def sample(version='60010', card='250410de', chip='b76000a1'):
    code = next(r for r in envelope['nvgop'] if r['version'] == version)
    resource = {'HardwareVerified': False, 'WriteEligible': False,
                'CaptureMarkers': [{'Capture': 'DIAG00.TXT', 'Sha256': 'a'*64, 'CompleteMarkers': ['1'], 'FailedMmioReads': 0}],
                'Compatibility': {'observations': [{'capture': 'DIAG00.TXT', 'available': True, 'chip_id': chip,
                  'display_controllers_truncated': False, 'display_controllers': [{'pci_id': card}]}]}}
    driver = {'test': 'captured-driver-review-v1', 'status': 'observed', 'capture_sha256': 'a'*64,
              'drivers': [{'role': 'nvgop', 'status': 'observed', 'version': int(version, 16), 'code_sha256': code['text_sha256']}]}
    for key in ['hardware_verified', 'ownership_verified', 'signature_trust_verified', 'profile_generated', 'write_eligible']:
        driver[key] = False
    return resource, driver


class Tests(unittest.TestCase):
    def test_global_does_not_admit_card_pair(self):
        r = review.compare(*sample('6000a'), envelope)
        self.assertTrue(r['global_nvgop_match']);self.assertFalse(r['card_chip_nvgop_match'])
        self.assertFalse(r['edid_global_allowlist_applicable']);self.assertFalse(r['write_eligible'])

    def test_actual_card_tables_and_combined_input(self):
        for version, card, chip in [('60010', '250410de', 'b76000a1'), ('60009', '220410de', 'b72000a1')]:
            r, d = sample(version, card, chip)
            self.assertTrue(review.compare(r, {'Test': 'resource-files-review-v1', 'Drivers': d}, envelope)['card_chip_nvgop_match'])
        r, d = sample();d['drivers'][0]['code_sha256'] = 'b'*64
        self.assertFalse(review.compare(r, d, envelope)['global_nvgop_match'])

    def test_binding_scope_and_ambiguity_refuse(self):
        for change in ['digest', 'scope', 'truncated', 'duplicate', 'chip', 'mmio', 'incomplete']:
            r, d = sample()
            if change == 'digest': d['capture_sha256'] = 'b'*64
            if change == 'scope': d['write_eligible'] = True
            if change == 'truncated': r['Compatibility']['observations'][0]['display_controllers_truncated'] = True
            if change == 'duplicate': d['drivers'] *= 2
            if change == 'chip': r['Compatibility']['observations'][0]['chip_id'] = 'unknown'
            if change == 'mmio': r['CaptureMarkers'][0]['FailedMmioReads'] = 1
            if change == 'incomplete': r['CaptureMarkers'][0]['CompleteMarkers'] = ['0']
            with self.subTest(change=change), self.assertRaises(ValueError): review.compare(r, d, envelope)


if __name__ == '__main__': unittest.main()
