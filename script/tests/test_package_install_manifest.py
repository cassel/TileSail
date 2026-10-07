import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile


class PackageManifestTest(unittest.TestCase):
    def test_archive_manifest_paths_and_hashes_match_packaged_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            package = root / 'TileSail-vfixture'
            inputs = {'TileSail.app/Contents/MacOS/TileSail': b'fixture-app',
                      'tilesail': b'fixture-tilesail-identity',
                      'aerospace': b'fixture-aerospace-identity'}
            manifest = {path: hashlib.sha256(data).hexdigest() for path, data in inputs.items()}
            prepared = root / 'install-manifest.json'
            prepared.write_text(json.dumps(manifest))
            prepared_bytes = prepared.read_bytes()
            for path, data in inputs.items():
                packaged_path = 'bin/' + path if path in ('tilesail', 'aerospace') else path
                output = package / packaged_path
                output.parent.mkdir(parents=True, exist_ok=True)
                output.write_bytes(data)
            subprocess.run([sys.executable, str(Path(__file__).parents[1] / 'package-install-manifest.py'),
                            str(prepared), str(package / 'install-manifest.json')], check=True)
            self.assertEqual(prepared.read_bytes(), prepared_bytes)
            archive = root / 'fixture.zip'
            with zipfile.ZipFile(archive, 'w') as z:
                for file in package.rglob('*'):
                    if file.is_file(): z.write(file, file.relative_to(root))
            with zipfile.ZipFile(archive) as z:
                packaged_manifest = json.loads(z.read(package.name + '/install-manifest.json'))
                self.assertEqual(set(packaged_manifest), {'TileSail.app/Contents/MacOS/TileSail', 'bin/tilesail', 'bin/aerospace'})
                for path, expected in packaged_manifest.items():
                    self.assertEqual(hashlib.sha256(z.read(package.name + '/' + path)).hexdigest(), expected)


if __name__ == '__main__': unittest.main()
