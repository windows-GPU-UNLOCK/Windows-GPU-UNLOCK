"""Packaging containment checks; uses fake bytes, never hardware or real firmware."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import prepare_usb
from prepare_usb import prepare


class PackagingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / 'source'
        self.assets = self.base / 'assets'
        self.output = self.base / 'output'
        self.assets.mkdir()
        for name, content in {
            'release/EFI/BOOT/BOOTX64.EFI': b'fake EFI',
            'unlock/app.c': b'fake source', 'LICENSE': b'license',
            'LICENSES/notice.txt': b'notice', 'THIRD_PARTY_NOTICES.md': b'notices',
            'docs/GUIDE.ko.md': b'guide',
            'docs/GUIDE.en.md': b'English guide',
        }.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
        self.write('release/provenance.json', {
            'efi_sha256': self.hash(b'fake EFI'),
            'corresponding_sources': [{'path': 'unlock/app.c', 'sha256': self.hash(b'fake source')}],
        })
        specs = []
        for i in range(5):
            name = f'asset{i}.bin'
            data = bytes([i])
            (self.assets / name).write_bytes(data)
            specs.append({'Name': name, 'Bytes': len(data), 'Sha256': self.hash(data)})
        self.write('unlock/assets.json', specs)
        self.refresh()

    @staticmethod
    def hash(data):
        return hashlib.sha256(data).hexdigest()

    def write(self, relative, value):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value), encoding='utf-8')

    def refresh(self):
        entries = [{'path': p.relative_to(self.root).as_posix(), 'bytes': p.stat().st_size,
                    'sha256': self.hash(p.read_bytes())}
                   for p in sorted(self.root.rglob('*')) if p.is_file() and p.name != 'SOURCE-MANIFEST.json']
        self.write('SOURCE-MANIFEST.json', {'files': entries})

    def test_complete_tree_with_source_and_no_firmware_in_source_zip(self):
        prepare(self.root, self.assets, self.output)
        self.assertEqual((self.output / 'EFI/BOOT/BOOTX64.EFI').read_bytes(), b'fake EFI')
        self.assertEqual(len(list((self.output / 'RTX3090-UNLOCK/ASSETS').iterdir())), 5)
        readme = (self.output / 'USB-README.md').read_text(encoding='utf-8')
        for language in ('en', 'ko'):
            guide = f'RTX3090-UNLOCK/docs/GUIDE.{language}.md'
            self.assertIn(guide, readme)
            self.assertTrue((self.output / guide).is_file())
        with zipfile.ZipFile(self.output / 'RTX3090-UNLOCK/SOURCE.zip') as archive:
            self.assertIn('unlock/app.c', archive.namelist())
            self.assertIn('SOURCE-MANIFEST.json', archive.namelist())
            self.assertFalse(any(name.endswith('.bin') for name in archive.namelist()))

    def test_bad_asset_rejected_before_output_created(self):
        (self.assets / 'asset0.bin').write_bytes(b'wrong')
        with self.assertRaises(ValueError):
            prepare(self.root, self.assets, self.output)
        self.assertFalse(self.output.exists())

    def test_modified_source_rejected(self):
        (self.root / 'unlock/app.c').write_bytes(b'changed')
        with self.assertRaises(ValueError):
            prepare(self.root, self.assets, self.output)
        self.assertFalse(self.output.exists())

    def test_existing_destination_preserved(self):
        self.output.mkdir()
        sentinel = self.output / 'keep.txt'
        sentinel.write_text('keep', encoding='utf-8')
        with self.assertRaises(ValueError):
            prepare(self.root, self.assets, self.output)
        self.assertEqual(sentinel.read_text(encoding='utf-8'), 'keep')

    def test_path_traversal_rejected(self):
        self.write('SOURCE-MANIFEST.json', {'files': [{'path': '../escape', 'bytes': 0, 'sha256': ''}]})
        with self.assertRaises(ValueError):
            prepare(self.root, self.assets, self.output)
        self.assertFalse(self.output.exists())

    def test_asset_changed_after_validation_is_rejected_against_original_pin(self):
        real_copy = prepare_usb.shutil.copyfile
        target = self.assets / 'asset0.bin'
        for changed in (b'\xff', b'changed after validation'):
            with self.subTest(changed=changed):
                target.write_bytes(b'\x00')
                output = self.base / f'output-{len(changed)}'

                def mutate_then_copy(source, destination, *args, **kwargs):
                    if Path(source) == target:
                        target.write_bytes(changed)
                    return real_copy(source, destination, *args, **kwargs)

                with patch.object(prepare_usb.shutil, 'copyfile', side_effect=mutate_then_copy):
                    with self.assertRaisesRegex(ValueError, 'Asset changed during copy'):
                        prepare(self.root, self.assets, output)
                self.assertFalse(output.exists())
                self.assertEqual(list(self.base.glob('.gpu-unlock-stage-*')), [])

    def test_untracked_documentation_and_licenses_are_not_packaged(self):
        for name in ('docs/private-notes.txt', 'docs/local/private.txt', 'LICENSES/untracked.txt'):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'PRIVATE LOCAL NOTES')
        prepare(self.root, self.assets, self.output)
        payload = self.output / 'RTX3090-UNLOCK'
        for name in ('docs/private-notes.txt', 'docs/local/private.txt', 'LICENSES/untracked.txt'):
            self.assertFalse((payload / name).exists())
        with zipfile.ZipFile(payload / 'SOURCE.zip') as archive:
            self.assertFalse(any('private' in name or 'untracked' in name for name in archive.namelist()))

    def test_zip_uses_verified_bytes_instead_of_reopening_source_paths(self):
        real_write = zipfile.ZipFile.write
        target = self.root / 'unlock/app.c'

        def mutate_then_archive(archive, filename, *args, **kwargs):
            if Path(filename) == target:
                target.write_bytes(b'changed after source check')
            return real_write(archive, filename, *args, **kwargs)

        with patch.object(zipfile.ZipFile, 'write', autospec=True, side_effect=mutate_then_archive):
            prepare(self.root, self.assets, self.output)
        with zipfile.ZipFile(self.output / 'RTX3090-UNLOCK/SOURCE.zip') as archive:
            self.assertEqual(archive.read('unlock/app.c'), b'fake source')

    def test_original_manifest_snapshot_is_preserved(self):
        target = self.root / 'SOURCE-MANIFEST.json'
        original = target.read_bytes()
        real_copy = prepare_usb.shutil.copyfile

        def mutate_then_copy(source, destination, *args, **kwargs):
            target.write_bytes(b'{"files":[]}')
            return real_copy(source, destination, *args, **kwargs)

        with patch.object(prepare_usb.shutil, 'copyfile', side_effect=mutate_then_copy):
            prepare(self.root, self.assets, self.output)
        self.assertNotEqual(target.read_bytes(), original)
        with zipfile.ZipFile(self.output / 'RTX3090-UNLOCK/SOURCE.zip') as archive:
            self.assertEqual(archive.read('SOURCE-MANIFEST.json'), original)
            manifest = json.loads(archive.read('SOURCE-MANIFEST.json'))
            for entry in manifest['files']:
                data = archive.read(entry['path'])
                self.assertEqual(len(data), entry['bytes'])
                self.assertEqual(self.hash(data), entry['sha256'])

    def test_late_source_or_document_change_cleans_staging(self):
        real_copy = prepare_usb.shutil.copyfile
        for name in ('unlock/app.c', 'docs/GUIDE.en.md', 'LICENSES/notice.txt'):
            with self.subTest(name=name):
                target = self.root / name
                original = target.read_bytes()

                def mutate_then_copy(source, destination, *args, **kwargs):
                    target.write_bytes(b'changed after validation')
                    return real_copy(source, destination, *args, **kwargs)

                with patch.object(prepare_usb.shutil, 'copyfile', side_effect=mutate_then_copy):
                    with self.assertRaisesRegex(ValueError, 'Source changed during packaging'):
                        prepare(self.root, self.assets, self.output)
                self.assertFalse(self.output.exists())
                self.assertEqual(list(self.base.glob('.gpu-unlock-stage-*')), [])
                target.write_bytes(original)

    def test_required_docs_must_be_manifested_not_just_present(self):
        manifest = json.loads((self.root / 'SOURCE-MANIFEST.json').read_text())
        manifest['files'] = [entry for entry in manifest['files'] if entry['path'] != 'docs/GUIDE.en.md']
        self.write('SOURCE-MANIFEST.json', manifest)
        with self.assertRaisesRegex(ValueError, 'not in the source manifest'):
            prepare(self.root, self.assets, self.output)
        self.assertFalse(self.output.exists())


if __name__ == '__main__':
    unittest.main()
