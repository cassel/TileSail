import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

class CleanProjectTest(unittest.TestCase):
    def test_actual_clean_script_preserves_local_and_nested_checkouts(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            subprocess.run(['git', 'init', '-q', str(root)], check=True)
            (root / 'script').mkdir()
            shutil.copy2(Path(__file__).parents[1] / 'clean-project.sh', root / 'script/clean-project.sh')
            (root / '.gitignore').write_text('.build/\n.backups/\n.local/\n.agents/\nAeroSpaceSmooth/\n')
            for path in ('.build/output', '.backups/app.zip', '.local/config', '.agents/tool', 'Sources/source.swift', 'AeroSpaceSmooth/source.swift'):
                file = root / path
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text(path)
            nested = root / '.build/nested-checkout'
            subprocess.run(['git', 'init', '-q', str(nested)], check=True)
            (nested / 'source.swift').write_text('nested source')
            subprocess.run(['git', '-C', str(nested), 'add', 'source.swift'], check=True)
            before = {str(p.relative_to(root)): p.read_bytes() for p in root.rglob('*') if p.is_file()}
            subprocess.run(['bash', str(root / 'script/clean-project.sh'), '--dry-run'], check=True, capture_output=True)
            self.assertEqual(before, {str(p.relative_to(root)): p.read_bytes() for p in root.rglob('*') if p.is_file()})
            subprocess.run(['bash', str(root / 'script/clean-project.sh')], check=True, capture_output=True)
            self.assertFalse((root / '.build/output').exists())
            for path in ('.backups/app.zip', '.local/config', '.agents/tool', 'Sources/source.swift', 'AeroSpaceSmooth/source.swift', '.build/nested-checkout/source.swift', '.build/nested-checkout/.git'):
                self.assertTrue((root / path).exists(), path)

if __name__ == '__main__': unittest.main()
