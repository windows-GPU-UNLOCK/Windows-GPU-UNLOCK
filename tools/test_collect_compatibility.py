"""Synthetic inventory and collection failure tests; no hardware access."""

import copy
import json
import subprocess
import sys
import unittest
from unittest.mock import patch

from collect_compatibility import collect_inventory, make_report, pci_identity


def inventory():
    return {
        'board': [{'Manufacturer': 'ASUSTeK', 'Product': 'TUF GAMING B650M-PLUS WIFI'}],
        'cpu': [{'Name': 'AMD Ryzen 7 7800X3D', 'Manufacturer': 'AuthenticAMD'}],
        'os': [{'Caption': 'Windows 11 Home', 'Version': '10.0.26200',
                'BuildNumber': '26200', 'OSArchitecture': '64-bit'}],
        'bios': [{'Manufacturer': 'American Megatrends', 'SMBIOSBIOSVersion': 'test'}],
        'video': [
            {'Name': 'NVIDIA RTX 3090', 'DriverVersion': '32.0.15.0000',
             'PNPDeviceID': r'PCI\VEN_10DE&DEV_2204&SUBSYS_145410DE&REV_A1\PRIVATE-SUFFIX'},
            {'Name': 'AMD Radeon Graphics', 'DriverVersion': 'test',
             'PNPDeviceID': r'PCI\VEN_1002&DEV_164E&SUBSYS_88771043&REV_C1\PRIVATE-IGPU'},
        ],
        'failed_sections': [],
    }


class ReportTests(unittest.TestCase):
    def test_no_environment_can_authorize_unlock(self):
        for platform in ('AMD', 'Intel', 'unknown'):
            with self.subTest(platform=platform):
                source = inventory()
                source['cpu'][0]['Name'] = platform
                if platform != 'AMD':
                    source['board'][0]['Product'] = 'another board'
                report = make_report(source)
                self.assertTrue(report['collection_complete'])
                self.assertEqual(report['assessment']['status'], 'not-assessed')
                self.assertIs(report['assessment']['can_unlock'], False)

    def test_model_ids_survive_but_private_fields_do_not(self):
        source = inventory()
        source['hostname'] = 'PRIVATE-HOST'
        for rows in (source[key] for key in ('board', 'cpu', 'os', 'bios', 'video')):
            for row in rows:
                row.update({'SerialNumber': 'PRIVATE-SERIAL', 'UUID': 'PRIVATE-UUID',
                            'PSComputerName': 'PRIVATE-HOST', 'Username': 'PRIVATE-USER'})
        before = copy.deepcopy(source)
        report = make_report(source)
        self.assertEqual(source, before)
        text = json.dumps(report)
        self.assertNotIn('PRIVATE-', text)
        self.assertNotIn('PNPDeviceID', text)
        self.assertEqual(report['hardware']['video'][0]['pci'], {
            'vendor': '10de', 'device': '2204',
            'subsystem_vendor': '10de', 'subsystem_device': '1454',
        })

    def test_missing_or_invalid_sections_remain_explicit(self):
        for value in (None, {}, [], [None], [{'Name': 'CPU only'}]):
            with self.subTest(value=value):
                source = inventory()
                source['cpu'] = value
                report = make_report(source)
                self.assertFalse(report['collection_complete'])
                self.assertIn('cpu', report['missing_sections'])
                self.assertFalse(report['assessment']['can_unlock'])
        source = inventory()
        source['failed_sections'] = ['video', 'PRIVATE-ERROR']
        self.assertEqual(make_report(source)['missing_sections'], ['video'])

    def test_virtual_and_malformed_pci_ids_never_leak_instance_suffix(self):
        for value in (None, 1, '', r'ROOT\DISPLAY\PRIVATE-DEVICE',
                      r'PCI\VEN_10DE&DEV_INVALID\PRIVATE-DEVICE'):
            self.assertIsNone(pci_identity(value))
        result = pci_identity(r'PCI\VEN_8086&DEV_1234\PRIVATE-DEVICE')
        self.assertEqual(result['vendor'], '8086')
        self.assertIsNone(result['subsystem_vendor'])

    def test_invalid_top_level_rejected(self):
        for value in ([], None, {'failed_sections': 'bad'}):
            with self.assertRaises(ValueError):
                make_report(value)

    def test_missing_and_malformed_pci_ids_are_partial_but_virtual_is_explicit(self):
        for identity in (None, '', r'PCI\VEN_10DE&DEV_BAD\PRIVATE-INSTANCE'):
            source = inventory()
            source['video'][0]['PNPDeviceID'] = identity
            report = make_report(source)
            self.assertFalse(report['collection_complete'])
            self.assertIn('video', report['missing_sections'])
            self.assertEqual(report['hardware']['video'][0]['pci_status'], 'unavailable')
        source['video'][0]['PNPDeviceID'] = r'ROOT\DISPLAY\PRIVATE-INSTANCE'
        report = make_report(source)
        self.assertTrue(report['collection_complete'])
        self.assertEqual(report['hardware']['video'][0]['pci_status'], 'non-pci-or-unrecognized')
        self.assertNotIn('PRIVATE-', json.dumps(report))


class CollectionTests(unittest.TestCase):
    @patch('collect_compatibility.sys.platform', 'win32')
    @patch('collect_compatibility.subprocess.run')
    def test_collection_uses_fixed_command_and_timeout(self, run):
        run.return_value = subprocess.CompletedProcess([], 0, json.dumps(inventory()).encode(), b'')
        self.assertTrue(collect_inventory()['collection_complete'])
        args, kwargs = run.call_args
        self.assertIn('-NonInteractive', args[0])
        self.assertIn('-EncodedCommand', args[0])
        self.assertNotIn('shell', kwargs)
        self.assertEqual(kwargs['timeout'], 45)
        self.assertNotIn('encoding', kwargs)
        self.assertNotIn('text', kwargs)

    @patch('collect_compatibility.sys.platform', 'win32')
    @patch('collect_compatibility.subprocess.run')
    def test_failure_and_raw_stderr_do_not_escape(self, run):
        for response in (
            subprocess.CompletedProcess([], 1, b'', b'\x8fPRIVATE-ERROR'),
            subprocess.CompletedProcess([], 0, b'PRIVATE-INVALID-JSON', b''),
            subprocess.CompletedProcess([], 0, b'[]', b''),
            subprocess.CompletedProcess([], 0, b'\x8fPRIVATE-INVALID-UTF8', b''),
        ):
            run.return_value = response
            with self.assertRaises(RuntimeError) as error:
                collect_inventory()
            self.assertNotIn('PRIVATE-', str(error.exception))
        for error in (subprocess.TimeoutExpired('PRIVATE-COMMAND', 45),
                      OSError('PRIVATE-PATH')):
            run.side_effect = error
            with self.assertRaises(RuntimeError) as caught:
                collect_inventory()
            self.assertNotIn('PRIVATE-', str(caught.exception))

    @patch('collect_compatibility.sys.platform', 'win32')
    def test_real_child_with_localized_stderr_and_utf8_inventory(self):
        source = inventory()
        source['os'][0]['Caption'] = 'Windows français / Русский / 한국어'
        payload = ('\ufeff' + json.dumps(source, ensure_ascii=False)).encode('utf-8')
        real_run = subprocess.run
        def child(command, **kwargs):
            # Exercise actual subprocess pipes, including Python's Windows
            # reader threads, without PowerShell or any hardware query.
            code = ('import sys; sys.stdout.buffer.write(' + repr(payload) + '); '
                    "sys.stderr.buffer.write(b'\\x8fPRIVATE-LOCAL-PATH')")
            return real_run([sys.executable, '-I', '-c', code], **kwargs)
        with patch('collect_compatibility.subprocess.run', side_effect=child), \
                patch('threading.excepthook') as thread_error:
            report = collect_inventory()
        thread_error.assert_not_called()
        self.assertTrue(report['collection_complete'])
        self.assertEqual(report['hardware']['os'][0]['Caption'], source['os'][0]['Caption'])
        self.assertNotIn('PRIVATE-', json.dumps(report))

    @patch('collect_compatibility.sys.platform', 'win32')
    def test_japanese_cp932_stderr_does_not_break_complete_dell_inventory(self):
        # Transcribed public identity plus synthetic localized text, not an
        # owner capture. CP932 0x83 starts a multibyte character, not UTF-8.
        source = inventory()
        source['board'] = [{'Manufacturer': 'Dell Inc.', 'Product': '0R6PCT'}]
        source['bios'][0]['SMBIOSBIOSVersion'] = '1.32.0'
        source['os'][0]['Caption'] = 'Windows 11 日本語'
        source['video'] = [{'Name': 'NVIDIA GeForce RTX 3060',
                            'DriverVersion': '32.0.16.1060',
                            'PNPDeviceID': r'PCI\VEN_10DE&DEV_2504&SUBSYS_C9741028\PRIVATE-INSTANCE'}]
        payload = json.dumps(source, ensure_ascii=False).encode('utf-8')
        warning = 'テスト PRIVATE-LOCAL-PATH'.encode('cp932')
        self.assertEqual(warning[0], 0x83)
        real_run = subprocess.run
        def child(command, **kwargs):
            code = ('import sys; sys.stdout.buffer.write(' + repr(payload) + '); '
                    'sys.stderr.buffer.write(' + repr(warning) + ')')
            return real_run([sys.executable, '-I', '-c', code], **kwargs)
        with patch('collect_compatibility.subprocess.run', side_effect=child), \
                patch('threading.excepthook') as thread_error:
            report = collect_inventory()
        thread_error.assert_not_called()
        self.assertTrue(report['collection_complete'])
        self.assertEqual(report['hardware']['os'][0]['Caption'], 'Windows 11 日本語')
        self.assertEqual(report['hardware']['video'][0]['pci']['subsystem_device'], 'c974')
        self.assertIs(report['assessment']['can_unlock'], False)
        self.assertNotIn('PRIVATE-', json.dumps(report))

    @patch('collect_compatibility.sys.platform', 'linux')
    @patch('collect_compatibility.subprocess.run')
    def test_non_windows_never_launches_a_process(self, run):
        with self.assertRaises(RuntimeError):
            collect_inventory()
        run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
