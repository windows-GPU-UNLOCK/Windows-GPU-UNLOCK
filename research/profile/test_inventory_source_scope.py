import copy
import importlib.util
import json
from pathlib import Path
import unittest

here = Path(__file__).resolve().parent;root = here.parents[1]
spec = importlib.util.spec_from_file_location('scope', here/'review-inventory-source-scope.py')
scope = importlib.util.module_from_spec(spec);spec.loader.exec_module(scope)
envelope = json.loads((here/'proven.json').read_text())
source = (root/'internal-boot/unlock/machine-profile.h').read_text()


def sample(sub='5051'):
    return {'schema_version': 1, 'purpose': 'compatibility-research-inventory', 'hardware': {'video': [
        {'pci': {'vendor': '10de', 'device': '2482', 'subsystem_vendor': '1462', 'subsystem_device': sub}}]}}


class Tests(unittest.TestCase):
    def test_same_device_different_subsystem(self):
        r = scope.review(sample(), envelope, source)
        self.assertFalse(r['adapters'][0]['generic_probe_device_listed'])
        self.assertIn('ASUS-TUF-GAMING-B660M-E-D4-4003-RTX3070TI', r['adapters'][0]['fixed_profile_same_device'])
        self.assertEqual(r['adapters'][0]['fixed_profile_same_device_and_subsystem'], [])
        self.assertFalse(r['physical_pcb_inferred_from_subsystem'])

    def test_exact_identity_does_not_qualify_machine(self):
        r = scope.review(sample('5052'), envelope, source)
        self.assertTrue(r['adapters'][0]['fixed_profile_same_device_and_subsystem'])
        self.assertFalse(r['machine_profile_verified']);self.assertFalse(r['write_eligible'])

    def test_unknown_scope_and_identity_refuse(self):
        for bad in [{}, {'schema_version': 1, 'purpose': 'compatibility-research-inventory', 'hardware': {'video': []}}]:
            with self.assertRaises(ValueError): scope.review(bad, envelope, source)
        bad = sample();bad['hardware']['video'][0]['pci']['device'] = 'PRIVATE'
        with self.assertRaises(ValueError): scope.review(bad, envelope, source)


if __name__ == '__main__': unittest.main()
