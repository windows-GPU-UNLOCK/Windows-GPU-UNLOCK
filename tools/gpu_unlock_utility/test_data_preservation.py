"""Offline regressions. Fake assets only: no DLL, download, PowerShell or hardware."""
import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name, HERE / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


captures = load('generate_captures')
assets = load('download_assets')


class CapturePreservation(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name)
        self.output = self.base / 'synthetic'

    def test_existing_evidence_is_unchanged(self):
        self.output.mkdir()
        names = ('DIAG00.TXT', 'DIAG01.TXT', 'IMG00.BIN', 'PROM.BIN')
        for name in names:
            (self.output / name).write_bytes(b'EXISTING TEST SENTINEL, NOT HARDWARE DATA')
        before = {p.name: p.read_bytes() for p in self.output.iterdir()}
        with self.assertRaises(FileExistsError):
            captures.generate_captures(self.output)
        self.assertEqual(before, {p.name: p.read_bytes() for p in self.output.iterdir()})

    def test_empty_existing_folder_is_refused(self):
        self.output.mkdir()
        with self.assertRaises(FileExistsError):
            captures.generate_captures(self.output)
        self.assertEqual(list(self.output.iterdir()), [])

    def test_dangling_symlink_is_refused(self):
        try:
            self.output.symlink_to(self.base / 'absent', target_is_directory=True)
        except (OSError, NotImplementedError):
            self.skipTest('symlinks unavailable')
        with self.assertRaises(FileExistsError):
            captures.generate_captures(self.output)
        self.assertFalse((self.base / 'absent').exists())

    def test_new_fixtures_are_explicitly_synthetic(self):
        result = captures.generate_captures(self.output, no_edid=False)
        self.assertEqual(result['purpose'], 'synthetic-test-fixture')
        self.assertFalse(result['hardware_tested'])
        self.assertFalse(result['write_eligible'])
        manifest = json.loads((self.output / 'SYNTHETIC-FIXTURE.json').read_text())
        self.assertEqual({key: value for key, value in result.items() if key != 'output_dir'}, manifest)
        self.assertNotIn('output_dir', manifest)
        self.assertTrue((self.output / 'IMG01.BIN').is_file())
        self.assertEqual((self.output / 'PROM.BIN').stat().st_size, 1048576)
        for name in result['captures']:
            self.assertTrue((self.output / name).read_text().startswith('SYNTHETIC TEST FIXTURE;'))
        self.assertIn('No hardware was observed', (self.output / 'README-SYNTHETIC.txt').read_text())

    def test_generation_failure_leaves_no_partial_output(self):
        with patch.object(captures, 'driver_image', side_effect=OSError('fixture failure')):
            with self.assertRaises(OSError):
                captures.generate_captures(self.output)
        self.assertFalse(self.output.exists())
        self.assertEqual(list(self.base.glob('.synthetic-fixture-*')), [])

    def test_output_appearing_during_generation_is_preserved(self):
        original = captures.driver_image

        def appear(*args):
            self.output.mkdir()
            (self.output / 'keep.txt').write_bytes(b'KEEP')
            return original(*args)

        with patch.object(captures, 'driver_image', side_effect=appear):
            with self.assertRaises(FileExistsError):
                captures.generate_captures(self.output)
        self.assertEqual((self.output / 'keep.txt').read_bytes(), b'KEEP')
        self.assertEqual(list(self.base.glob('.synthetic-fixture-*')), [])

    def test_invalid_count_writes_nothing(self):
        for count in (0, -1, 33, True):
            with self.subTest(count=count), self.assertRaises(ValueError):
                captures.generate_captures(self.output, count=count)
            self.assertFalse(self.output.exists())

    def test_gui_does_not_use_selected_capture_folder_for_generation(self):
        # Static wiring check only, not a substitute for native WPF testing.
        text = (HERE / 'GpuUnlockUtility.ps1').read_text(encoding='utf-8-sig')
        event = text.split('$btnGenEfiCaptures.Add_Click({', 1)[1].split('$btnStageProbeUsb.Add_Click', 1)[0]
        self.assertNotIn('$txtCaptureFolder.Text.Trim()', event)
        self.assertIn('synthetic-captures\\fixture-', event)
        self.assertIn('[Guid]::NewGuid()', event)
        self.assertIn('SYNTHETIC TEST FIXTURES', event)
        export = text.split('function Export-EfiDiagnosticCaptures', 1)[1].split('function Stage-DiagnosticProbeUsb', 1)[0]
        self.assertIn('$LASTEXITCODE -ne 0', export)
        self.assertNotIn('New-Item -ItemType Directory', export)


class DownloadPreservation(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name)
        self.destination = self.base / 'archive.tar.xz'
        self.data = b'FAKE ARCHIVE RESPONSE'
        self.digest = hashlib.sha256(self.data).hexdigest()
        self.url = 'https://fixture.invalid/archive'  # urlopen is always mocked.
        quiet = contextlib.redirect_stdout(io.StringIO())
        quiet.__enter__()
        self.addCleanup(quiet.__exit__, None, None, None)

    def response(self):
        response = io.BytesIO(self.data)
        response.headers = {'Content-Length': str(len(self.data))}
        return response

    def download(self):
        return assets.download_with_progress(self.url, self.destination, self.digest)

    def test_existing_mismatched_archive_is_not_replaced(self):
        self.destination.write_bytes(b'UNRELATED EXISTING FILE')
        with patch.object(assets.urllib.request, 'urlopen', side_effect=lambda *a, **k: self.response()) as network:
            with self.assertRaises(ValueError):
                self.download()
        network.assert_not_called()
        self.assertEqual(self.destination.read_bytes(), b'UNRELATED EXISTING FILE')

    def test_existing_fixed_temporary_filename_is_not_used(self):
        previous_temporary = self.destination.with_suffix('.download')
        previous_temporary.write_bytes(b'KEEP TEMP SENTINEL')
        with patch.object(assets.urllib.request, 'urlopen', side_effect=lambda *a, **k: self.response()):
            self.assertEqual(self.download(), self.destination)
        self.assertEqual(self.destination.read_bytes(), self.data)
        self.assertEqual(previous_temporary.read_bytes(), b'KEEP TEMP SENTINEL')
        self.assertEqual(set(self.base.iterdir()), {self.destination, previous_temporary})

    def test_destination_appearing_during_download_is_preserved(self):
        def appear(*args, **kwargs):
            self.destination.write_bytes(b'NEW OWNER')
            return self.response()

        with patch.object(assets.urllib.request, 'urlopen', side_effect=appear):
            with self.assertRaises(FileExistsError):
                self.download()
        self.assertEqual(self.destination.read_bytes(), b'NEW OWNER')
        self.assertEqual(list(self.base.iterdir()), [self.destination])

    def test_bad_digest_leaves_no_final_or_temporary_file(self):
        self.digest = '0' * 64
        with patch.object(assets.urllib.request, 'urlopen', side_effect=lambda *a, **k: self.response()):
            with self.assertRaises(ValueError):
                self.download()
        self.assertEqual(list(self.base.iterdir()), [])

    def test_network_failure_cleans_only_its_temporary_file(self):
        sentinel = self.destination.with_suffix('.download')
        sentinel.write_bytes(b'KEEP')
        with patch.object(assets.urllib.request, 'urlopen', side_effect=OSError('fake offline failure')):
            with self.assertRaises(OSError):
                self.download()
        self.assertEqual(list(self.base.iterdir()), [sentinel])
        self.assertEqual(sentinel.read_bytes(), b'KEEP')

    def test_failed_copy_removes_owned_partial_destination(self):
        def fail_copy(source, target):
            target.write(b'PARTIAL')
            raise OSError('fake disk failure')

        with patch.object(assets.urllib.request, 'urlopen', side_effect=lambda *a, **k: self.response()), \
                patch.object(assets.shutil, 'copyfileobj', side_effect=fail_copy):
            with self.assertRaises(OSError):
                self.download()
        self.assertEqual(list(self.base.iterdir()), [])

    def test_verified_existing_archive_is_reused_without_network(self):
        self.destination.write_bytes(self.data)
        with patch.object(assets.urllib.request, 'urlopen', side_effect=lambda *a, **k: self.response()) as network:
            self.assertEqual(self.download(), self.destination)
        network.assert_not_called()
        self.assertEqual(self.destination.read_bytes(), self.data)

    def test_symlinked_archive_is_refused_without_network(self):
        target = self.base / 'keep'
        target.write_bytes(self.data)
        try:
            self.destination.symlink_to(target)
        except (OSError, NotImplementedError):
            self.skipTest('symlinks unavailable')
        with patch.object(assets.urllib.request, 'urlopen', side_effect=lambda *a, **k: self.response()) as network:
            with self.assertRaises(ValueError):
                self.download()
        network.assert_not_called()
        self.assertTrue(self.destination.is_symlink())
        self.assertEqual(target.read_bytes(), self.data)


class CachePreservation(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name)
        self.cache = self.base / 'cache'
        self.output = self.base / 'assets'
        self.specs = self.base / 'assets.json'
        self.fake = {'v67-ga102-610.43.03.bin': b'fake-v67', 'gsp_ga10x.bin': b'fake-gsp',
                     'one.bin': b'1', 'two.bin': b'2', 'three.bin': b'3'}
        self.specs.write_text(json.dumps([
            {'Name': name, 'Bytes': len(data), 'Sha256': hashlib.sha256(data).hexdigest()}
            for name, data in self.fake.items()]))
        self.source_names = ('NVIDIA-kernel-module-source-610.43.03.tar.xz',
                             'nvidia-utils-610.43.03-1-x86_64_v3.pkg.tar.zst')

    def run_fake(self, *, keep=False, fail=False):
        def fake_download(url, path, digest):
            if not path.exists():
                path.write_bytes(b'FAKE ARCHIVE')
            return path

        def fake_extract(path, temporary):
            (temporary / 'owned-extraction.txt').write_bytes(b'FAKE EXTRACT')
            if fail:
                raise RuntimeError('mock extraction failure')
            return self.fake['gsp_ga10x.bin']

        with contextlib.ExitStack() as stack:
            stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
            for name, options in (
                ('ASSETS_JSON', {'new': self.specs}),
                ('download_with_progress', {'side_effect': fake_download}),
                ('build_v67_payload', {'return_value': self.fake['v67-ga102-610.43.03.bin']}),
                ('extract_kernel_module_assets', {'return_value': {n: self.fake[n] for n in ('one.bin', 'two.bin', 'three.bin')}}),
                ('extract_gsp_from_pkg', {'side_effect': fake_extract}),
            ):
                stack.enter_context(patch.object(assets, name, **options))
            return assets.acquire_all_assets(self.output, self.cache, keep_cache=keep)

    def test_unrelated_existing_cache_files_are_preserved(self):
        self.cache.mkdir()
        (self.cache / 'keep.txt').write_bytes(b'KEEP')
        (self.cache / 'temp_extract').mkdir()
        (self.cache / 'temp_extract/keep.txt').write_bytes(b'KEEP TOO')
        self.assertTrue(self.run_fake())
        self.assertEqual((self.cache / 'keep.txt').read_bytes(), b'KEEP')
        self.assertEqual((self.cache / 'temp_extract/keep.txt').read_bytes(), b'KEEP TOO')
        for name in self.source_names:
            self.assertFalse((self.cache / name).exists())

    def test_output_inside_cache_survives_cleanup(self):
        self.output = self.cache / 'assets'
        self.assertTrue(self.run_fake())
        for name, data in self.fake.items():
            self.assertEqual((self.output / name).read_bytes(), data)

    def test_existing_source_archives_are_preserved(self):
        self.cache.mkdir()
        for name in self.source_names:
            (self.cache / name).write_bytes(b'EXISTING ARCHIVE FIXTURE')
        self.assertTrue(self.run_fake())
        for name in self.source_names:
            self.assertEqual((self.cache / name).read_bytes(), b'EXISTING ARCHIVE FIXTURE')

    def test_keep_cache_retains_new_archives(self):
        self.assertTrue(self.run_fake(keep=True))
        for name in self.source_names:
            self.assertEqual((self.cache / name).read_bytes(), b'FAKE ARCHIVE')
        self.assertEqual(list(self.cache.glob('gpu-unlock-extract-*')), [])

    def test_extraction_failure_preserves_existing_directory(self):
        (self.cache / 'temp_extract').mkdir(parents=True)
        (self.cache / 'temp_extract/keep.txt').write_bytes(b'KEEP')
        with self.assertRaises(RuntimeError):
            self.run_fake(fail=True)
        self.assertEqual((self.cache / 'temp_extract/keep.txt').read_bytes(), b'KEEP')
        self.assertEqual(list(self.cache.glob('gpu-unlock-extract-*')), [])

    def test_new_empty_cache_directory_is_removed(self):
        self.assertTrue(self.run_fake())
        self.assertFalse(self.cache.exists())


class UsbStagingPreservation(unittest.TestCase):
    def setUp(self):
        self.ps_text = (HERE / 'GpuUnlockUtility.ps1').read_text(encoding='utf-8-sig')

    def test_staging_function_contract_enforces_opt_in(self):
        func = self.ps_text.split('function Stage-DiagnosticProbeUsb', 1)[1].split('function Build-And-Stage-Local-Unlock', 1)[0]
        self.assertIn('[switch]$OptIn', func)
        self.assertIn('-not $OptIn', func)
        self.assertIn('explicit opt-in operation', func)

    def test_staging_validates_removable_usb_and_rejects_system_and_boot(self):
        func = self.ps_text.split('function Stage-DiagnosticProbeUsb', 1)[1].split('function Build-And-Stage-Local-Unlock', 1)[0]
        self.assertIn("$disk.BusType -ne 'USB'", func)
        self.assertIn("$vol.FileSystem -ne 'FAT32'", func)
        self.assertIn('$part.IsSystem', func)
        self.assertIn('$disk.IsBoot', func)
        self.assertIn('$part.IsBoot', func)
        self.assertIn('Get-SystemWindowsEspGuid', func)
        self.assertIn('staging refused', func)

    def test_staging_refuses_existing_destination_files_without_overwrite(self):
        func = self.ps_text.split('function Stage-DiagnosticProbeUsb', 1)[1].split('function Build-And-Stage-Local-Unlock', 1)[0]
        self.assertIn('Destination file already exists', func)
        self.assertIn('Destination file appeared during staging', func)
        # Verify backup-and-replace is removed
        self.assertNotIn('RTX3090-UNLOCK\\backup', func)
        self.assertNotIn('BOOTX64-$oldSha.EFI', func)

    def test_deploy_to_usb_does_not_silently_stage_probe(self):
        deploy_func = self.ps_text.split('function Deploy-ToUsb', 1)[1].split('function Restore-WindowsFirstBootOrder', 1)[0]
        self.assertIn("$disk.BusType -ne 'USB'", deploy_func)
        self.assertIn('$part.IsSystem', deploy_func)
        self.assertIn('$disk.IsBoot', deploy_func)
        self.assertNotIn('Stage-DiagnosticProbeUsb -Letter', deploy_func)
        self.assertIn('Please stage and boot the Diagnostic Probe USB explicitly first', deploy_func)

    def test_cli_and_gui_wiring_enforce_opt_in(self):
        # CLI param declaration
        self.assertIn('[switch]$OptIn', self.ps_text[:2000])
        # CLI dispatch
        cli_stage = self.ps_text.split("'StageProbe' {", 1)[1].split("'BuildLocalUsb' {", 1)[0]
        self.assertIn('Stage-DiagnosticProbeUsb -Letter $DriveLetter -OptIn:$OptIn', cli_stage)
        cli_dump = self.ps_text.split("'ProbeUsb' {", 1)[1].split("'DownloadAssets' {", 1)[0]
        self.assertIn('Stage-DiagnosticProbeUsb -Letter $DriveLetter -OptIn:$OptIn', cli_dump)
        # GUI event handlers
        gui_direct = self.ps_text.split('$btnStageProbeDirect.Add_Click({', 1)[1].split('$btnDeployUsb.Add_Click', 1)[0]
        self.assertIn('Stage-DiagnosticProbeUsb -Letter $letter -OptIn', gui_direct)
        gui_tab = self.ps_text.split('$btnStageProbeUsb.Add_Click({', 1)[1].split('$btnExportJson.Add_Click', 1)[0]
        self.assertIn('Stage-DiagnosticProbeUsb -Letter $letter -OptIn', gui_tab)

    def test_powershell_mock_regressions(self):
        test_script = HERE / 'test_usb_staging.ps1'
        self.assertTrue(test_script.is_file())
        try:
            res = subprocess.run(
                ['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(test_script)],
                capture_output=True, text=True, check=True
            )
            self.assertIn('All 13 USB staging safety regression tests PASSED', res.stdout)
        except (FileNotFoundError, subprocess.CalledProcessError) as exc:
            if isinstance(exc, FileNotFoundError):
                self.skipTest('powershell is not available on PATH')
            self.fail(f"test_usb_staging.ps1 failed:\n{exc.stdout}\n{exc.stderr}")


class EfiFlushWarningPreservation(unittest.TestCase):
    def test_gu_log_flush_rejects_warnings(self):
        app_io = (REPO_ROOT / 'internal-boot/unlock/app_io.c').read_text(encoding='utf-8')
        flush_block = app_io.split('VOID GuLogFlush(VOID) {', 1)[1].split('}', 1)[0]
        self.assertIn('flush_status != EFI_SUCCESS', flush_block)
        self.assertNotIn('((INTN)flush_status) < 0', flush_block)

    def test_headless_tests_cover_flush_warning(self):
        headless_c = (REPO_ROOT / 'internal-boot/unlock/tests/test_headless.c').read_text(encoding='utf-8')
        self.assertIn('HeadFlush', headless_c)
        self.assertIn('Case==16', headless_c)
        self.assertIn('EFI_WARN_UNKNOWN_GLYPH', headless_c)
        self.assertIn('for(int mode=0;mode<=16;mode++)', headless_c)

    def test_app_tests_cover_flush_warning(self):
        app_c = (REPO_ROOT / 'internal-boot/unlock/tests/test_app.c').read_text(encoding='utf-8')
        self.assertIn('APP_FLUSH_WARN', app_c)
        self.assertIn('"report-flush-warn"', app_c)
        self.assertIn('app_mode==APP_FLUSH_WARN', app_c)


if __name__ == '__main__':
    unittest.main()
