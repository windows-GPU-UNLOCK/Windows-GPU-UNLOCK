"""Create a new local USB tree; never format disks or write to a chosen USB."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
import zipfile


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest() if hasattr(hashlib, 'file_digest') else hashlib.sha256(stream.read()).hexdigest()


def safe_file(root, relative):
    item = Path(relative)
    if item.is_absolute() or '..' in item.parts or '\\' in relative or ':' in relative:
        raise ValueError('Unsafe manifest path')
    path = root / item
    if not path.is_file() or path.is_symlink() or not path.resolve().is_relative_to(root.resolve()):
        raise ValueError('Missing or unsafe file: ' + relative)
    return path


def prepare(root, assets, output):
    if output.exists() or output.is_symlink() or not output.parent.is_dir():
        raise ValueError('Choose a new output folder under an existing local parent')
    manifest_bytes = safe_file(root, 'SOURCE-MANIFEST.json').read_bytes()
    source = json.loads(manifest_bytes.decode('utf-8-sig'))
    files = []
    seen = set()
    expected = {}
    for entry in source['files']:
        name = entry['path']
        path = safe_file(root, name)
        if name in seen or path.stat().st_size != entry['bytes'] or sha(path) != entry['sha256']:
            raise ValueError('Changed or duplicate public file: ' + name)
        seen.add(name)
        expected[name] = entry
        files.append((name, path))
    required = {'LICENSE', 'THIRD_PARTY_NOTICES.md', 'docs/GUIDE.en.md',
                'docs/GUIDE.ko.md', 'release/provenance.json', 'unlock/assets.json'}
    if not required.issubset(expected) or not any(name.startswith('LICENSES/') for name in expected):
        raise ValueError('Required package documentation or metadata is not in the source manifest')

    def source_bytes(name, path):
        # Hash and consume the same bytes, including metadata and ZIP members.
        # Never verify a path and then reopen it for an unchecked copy.
        entry = expected[name]
        with path.open('rb') as stream:
            data = stream.read(entry['bytes'] + 1)
        if len(data) != entry['bytes'] or hashlib.sha256(data).hexdigest() != entry['sha256']:
            raise ValueError('Source changed during packaging: ' + name)
        return data

    binary = safe_file(root, 'release/EFI/BOOT/BOOTX64.EFI')
    release = json.loads(source_bytes('release/provenance.json', safe_file(root, 'release/provenance.json')).decode('utf-8-sig'))
    if sha(binary) != release['efi_sha256']:
        raise ValueError('EFI does not match successful-case hash')
    for entry in release['corresponding_sources']:
        if sha(safe_file(root, entry['path'])) != entry['sha256']:
            raise ValueError('EFI corresponding source mismatch')
    specs = json.loads(source_bytes('unlock/assets.json', safe_file(root, 'unlock/assets.json')).decode('utf-8-sig'))
    if len(specs) != 5 or len({x['Name'] for x in specs}) != 5:
        raise ValueError('Unexpected asset specification')
    checked_assets = []
    for entry in specs:
        path = safe_file(assets, entry['Name'])
        if path.stat().st_size != entry['Bytes'] or sha(path) != entry['Sha256']:
            raise ValueError('Wrong asset: ' + entry['Name'])
        checked_assets.append((path, entry['Bytes'], entry['Sha256']))
    # Stage only after every input has passed. Refuse existing destinations.
    with tempfile.TemporaryDirectory(prefix='.gpu-unlock-stage-', dir=output.parent) as temporary:
        stage = Path(temporary) / 'package'
        boot = stage / 'EFI/BOOT'
        payload = stage / 'RTX3090-UNLOCK'
        asset_out = payload / 'ASSETS'
        boot.mkdir(parents=True)
        asset_out.mkdir(parents=True)
        shutil.copyfile(binary, boot / 'BOOTX64.EFI')
        for path, size, digest in checked_assets:
            shutil.copyfile(path, asset_out / path.name)
            if (asset_out / path.name).stat().st_size != size or sha(asset_out / path.name) != digest:
                raise ValueError('Asset changed during copy')
        if sha(boot / 'BOOTX64.EFI') != release['efi_sha256']:
            raise ValueError('EFI changed during copy')
        (stage / 'USB-README.md').write_text(
            '# Windows GPU UNLOCK\n\nRead RTX3090-UNLOCK/docs/GUIDE.en.md before booting.\n'
            'Korean: RTX3090-UNLOCK/docs/GUIDE.ko.md\n'
            'Full public guide: https://github.com/impacifist/Windows-GPU-UNLOCK\n'
            'After unlock, use Boot Override -> Windows Boot Manager WITHOUT resetting.\n', encoding='utf-8')
        with zipfile.ZipFile(payload / 'SOURCE.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
            for name, path in files:
                data = source_bytes(name, path)
                archive.writestr(name, data)
                if name.startswith(('LICENSES/', 'docs/')) or name in ('LICENSE', 'THIRD_PARTY_NOTICES.md'):
                    # Include only manifested documentation. Untracked local
                    # notes and extra files must not leak through copytree().
                    target = payload / name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(data)
            archive.writestr('SOURCE-MANIFEST.json', manifest_bytes)
        if output.exists() or output.is_symlink():
            raise ValueError('Output appeared during preparation')
        stage.rename(output)
    print('Created local package:', output)
    print('Back up your FAT32 USB, then copy the contents manually. No disk was modified.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--assets', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    prepare(Path(__file__).resolve().parents[1], args.assets.resolve(), args.output.absolute())


if __name__ == '__main__':
    main()
