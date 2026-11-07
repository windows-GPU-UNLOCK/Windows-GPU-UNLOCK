import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('package', Path(__file__).with_name('package-collector.py'))
package = importlib.util.module_from_spec(spec);spec.loader.exec_module(package)


class Tests(unittest.TestCase):
    def test_exact_source_allowlist_and_reproducibility(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)/'source';root.mkdir()
            for name in package.FILES:
                p = root/name;p.parent.mkdir(parents=True, exist_ok=True);p.write_bytes(('source '+name).encode())
            (root/'UNRELATED.EFI').write_bytes(b'not included')
            a = Path(tmp)/'a.zip';b = Path(tmp)/'b.zip'
            self.assertEqual(package.package(root, a), package.package(root, b))
            with zipfile.ZipFile(a) as z:
                self.assertEqual(set(z.namelist()), set(package.FILES)|{'collector-files.json'})
                manifest = json.loads(z.read('collector-files.json'))
                for row in manifest['files']:
                    data = z.read(row['path'])
                    self.assertEqual(data, (root/row['path']).read_bytes())
                    self.assertEqual(hashlib.sha256(data).hexdigest(), row['sha256'])
                self.assertEqual(manifest['antivirus_verdict'], 'not-established')
            with self.assertRaises(ValueError): package.package(root, a)

    def test_missing_input_refuses(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(ValueError): package.package(Path(tmp), Path(tmp)/'out.zip')


if __name__ == '__main__': unittest.main()
