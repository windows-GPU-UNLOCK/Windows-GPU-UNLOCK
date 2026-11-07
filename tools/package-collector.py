"""Create a transparent collector-only ZIP; no downloads, compilation or execution."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

FILES = ('LICENSE', 'tools/collect_compatibility.py', 'tools/test_collect_compatibility.py',
         'tools/test-collector.ps1', 'docs/COLLECTOR-ONLY.en.md', 'docs/COLLECTOR-ONLY.ko.md')


def package(root, output):
    if output.exists():
        raise ValueError('Output exists; preserve it and choose a new path.')
    content = {}
    for name in FILES:
        path = root/name
        if not path.is_file() or path.is_symlink() or path.stat().st_size > 256*1024:
            raise ValueError('Unexpected package input')
        content[name] = path.read_bytes()
    manifest = {'package': 'windows-collector-only-v1', 'files': [
        {'path': name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
        for name, data in content.items()], 'contains_efi_or_native_binaries': False,
        'antivirus_verdict': 'not-established'}
    content['collector-files.json'] = (json.dumps(manifest, indent=2)+'\n').encode()
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, 'x', compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in content.items():
            info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0));info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, data)
    return hashlib.sha256(output.read_bytes()).hexdigest()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    print(package(Path(__file__).resolve().parents[1], args.output))
