import importlib.util
import hashlib
import json
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('migration', Path(__file__).parents[1] / 'install-migration.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class MigrationFixture(unittest.TestCase):
    def setUp(self):
        self.processes = patch.object(m, "running_managers", return_value=[])
        self.processes.start()
        self.addCleanup(self.processes.stop)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.paths = {k: self.root / k for k in ('release', 'applications', 'system_applications', 'cli', 'agents', 'backups', 'project')}
        for p in self.paths.values(): p.mkdir()
        self.bundle(self.paths['release'] / 'TileSail.app', 'us.cassel.tilesail', 'TileSail', b'new')
        for name in ('tilesail', 'aerospace'):
            f = self.paths['release'] / name
            f.write_bytes(b'new-cli'); f.chmod(0o755)
        release = self.paths['release']
        binaries = ['TileSail.app/Contents/MacOS/TileSail', 'tilesail', 'aerospace']
        (release / 'install-manifest.json').write_text(json.dumps({p: hashlib.sha256((release / p).read_bytes()).hexdigest() for p in binaries}))
        self.old = self.paths['applications'] / 'AeroSpace.app'
        self.bundle(self.old, 'bobko.aerospace', 'AeroSpace', b'old')
        self.oldcli = self.paths['cli'] / 'aerospace'
        self.oldcli.write_bytes(b'old-cli')
        self.agent = self.paths['agents'] / 'custom.plist'
        self.obj = {'Label': 'custom.label', 'KeepAlive': True, 'EnvironmentVariables': {'X': 'Y'},
                    'ProgramArguments': [str(self.old / 'Contents/MacOS/AeroSpace'), '--config-path', '/config/custom.toml']}
        self.agent.write_bytes(plistlib.dumps(self.obj, fmt=plistlib.FMT_BINARY))

    def bundle(self, p, identity, executable, data):
        (p / 'Contents/MacOS').mkdir(parents=True)
        (p / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': identity, 'CFBundleExecutable': executable}))
        f = p / 'Contents/MacOS' / executable
        f.write_bytes(data); f.chmod(0o755)

    def plan(self, **kw): return m.plan(**self.paths, running=kw.get('running', []))

class MigrationTest(MigrationFixture):
    def test_success_preserves_config_format_and_properties(self):
        m.apply(self.plan(), unregister=False)
        self.assertFalse(self.old.exists())
        self.assertTrue((self.paths['applications'] / 'TileSail.app').exists())
        self.assertEqual(self.oldcli.read_bytes(), b'new-cli')
        raw = self.agent.read_bytes()
        self.assertTrue(raw.startswith(b'bplist'))
        obj = plistlib.loads(raw)
        self.assertEqual(obj['ProgramArguments'][0], str(self.paths['applications'] / 'TileSail.app/Contents/MacOS/TileSail'))
        self.assertEqual(obj['ProgramArguments'][1:], self.obj['ProgramArguments'][1:])
        for key in ('Label', 'KeepAlive', 'EnvironmentVariables'): self.assertEqual(obj[key], self.obj[key])
        self.assertGreaterEqual(len(list(self.paths['backups'].glob('*.zip'))), 3)

    def test_bundle_symlink_and_compatibility_client(self):
        bundle = self.paths["release"] / "TileSail.app"
        (bundle / "Contents/current").symlink_to("MacOS")
        compatibility = self.root / "legacy-bin"
        compatibility.mkdir()
        (compatibility / "tilesail").write_bytes(b"legacy")
        p = m.plan(**self.paths, running=[], compatibility_cli=compatibility)
        m.apply(p, unregister=False)
        self.assertTrue((self.paths["applications"] / "TileSail.app/Contents/current").is_symlink())
        self.assertEqual((compatibility / "tilesail").read_bytes(), b"new-cli")

    def test_open_form(self):
        self.obj['ProgramArguments'] = ['/usr/bin/open', '-g', '-a', str(self.old), '--args', '--config-path', '/custom']
        updated = m.rewrite(self.obj, self.paths['applications'] / 'TileSail.app')
        self.assertEqual(updated['ProgramArguments'][3], str(self.paths['applications'] / 'TileSail.app'))
        self.assertEqual(updated['ProgramArguments'][:3], self.obj['ProgramArguments'][:3])
        self.assertEqual(updated['ProgramArguments'][4:], self.obj['ProgramArguments'][4:])

    def test_rollback_matrix(self):
        for phase in ('archive', 'remove', 'copy', 'plist'):
            with self.subTest(phase=phase):
                original = self.agent.read_bytes()
                with self.assertRaises(RuntimeError): m.apply(self.plan(), fail_at=phase, unregister=False)
                self.assertEqual(self.agent.read_bytes(), original)
                self.assertEqual(self.oldcli.read_bytes(), b'old-cli')
                self.assertEqual((self.old / 'Contents/MacOS/AeroSpace').read_bytes(), b'old')
                self.assertFalse((self.paths['applications'] / 'TileSail.app').exists())

    def test_planning_zero_writes(self):
        before = {p: p.read_bytes() for p in self.root.rglob('*') if p.is_file()}
        self.plan()
        self.assertEqual(before, {p: p.read_bytes() for p in self.root.rglob('*') if p.is_file()})

    def test_reject_running_multiple_malformed_symlink(self):
        with self.assertRaises(ValueError): self.plan(running=['TileSail'])
        other = self.agent.with_name('second.plist')
        other.write_bytes(self.agent.read_bytes())
        with self.assertRaises(ValueError): self.plan()
        other.unlink(); other.write_bytes(b'garbage')
        with self.assertRaises(plistlib.InvalidFileException): self.plan()
        other.unlink(); self.oldcli.unlink(); self.oldcli.symlink_to('/tmp')
        with self.assertRaises(ValueError): self.plan()

    def test_overlap_and_late_running_rejection(self):
        paths = dict(self.paths, backups=self.old / "backups")
        with self.assertRaises(ValueError): m.plan(**paths, running=[])
        p = self.plan()
        with patch.object(m, "running_managers", return_value=["TileSail"]):
            with self.assertRaises(ValueError): m.apply(p, unregister=False)
        self.assertTrue(self.old.exists())
        self.assertFalse((self.paths["applications"] / "TileSail.app").exists())

    def test_manifest_required_and_alias_overlap_rejected(self):
        (self.paths["release"] / "install-manifest.json").unlink()
        with self.assertRaises(FileNotFoundError): self.plan()
        alias = self.root / "unused/../release"
        self.assertEqual(m.safe(alias), self.paths["release"])
        with self.assertRaises(ValueError):
            m.validate_layout(dict(release=m.safe(alias), backups=self.paths["backups"], replacements=[],
                                   destination=self.paths["release"] / "TileSail.app", cli_targets=[self.paths["cli"]], startup=[]))

    def test_reject_app_manifest_mismatch(self):
        (self.paths["release"] / "TileSail.app/Contents/MacOS/TileSail").write_bytes(b"other-build")
        with self.assertRaises(ValueError): self.plan()

    def test_reject_mismatched_cli(self):
        (self.paths['release'] / 'tilesail').write_bytes(b'wrong')
        with self.assertRaises(ValueError): self.plan()

    def test_derived_inventory_is_bounded(self):
        p = self.paths['project'] / '.build/xcode/Products/TileSail.app'
        self.bundle(p, 'us.cassel.tilesail', 'TileSail', b'build')
        unrelated = self.paths['project'] / 'nested/TileSail.app'
        self.bundle(unrelated, 'us.cassel.tilesail', 'TileSail', b'unrelated')
        self.assertEqual(self.plan()['derived'], [p])

if __name__ == '__main__': unittest.main()

class ReviewRegressionTest(MigrationFixture):
    def test_regular_file_roots_are_rejected_without_mutation(self):
        invalid = self.root / 'not-a-directory'
        invalid.write_bytes(b'preserve')
        for name in self.paths:
            with self.subTest(root=name), self.assertRaises(ValueError):
                m.plan(**dict(self.paths, **{name: invalid}), running=[])
        with self.assertRaises(ValueError):
            m.plan(**self.paths, running=[], compatibility_cli=invalid)
        self.assertEqual(invalid.read_bytes(), b'preserve')
        self.assertEqual(self.oldcli.read_bytes(), b'old-cli')
        self.assertTrue(self.old.exists())

    def test_different_prepared_cli_bytes_are_accepted(self):
        release = self.paths['release']
        (release / 'tilesail').write_bytes(b'tilesail-specific-signing-identifier')
        manifest_path = release / 'install-manifest.json'
        manifest = json.loads(manifest_path.read_text())
        manifest['tilesail'] = hashlib.sha256((release / 'tilesail').read_bytes()).hexdigest()
        manifest_path.write_text(json.dumps(manifest))
        m.apply(self.plan(), unregister=False)
        self.assertEqual((self.paths['cli'] / 'tilesail').read_bytes(), b'tilesail-specific-signing-identifier')
        self.assertEqual((self.paths['cli'] / 'aerospace').read_bytes(), b'new-cli')

    def test_release_mutation_after_plan_preserves_originals(self):
        p = self.plan()
        (self.paths['release'] / 'TileSail.app/Contents/MacOS/TileSail').write_bytes(b'changed')
        original = self.agent.read_bytes()
        with self.assertRaisesRegex(ValueError, 'changed after planning'): m.apply(p, unregister=False)
        self.assertEqual(self.agent.read_bytes(), original)
        self.assertEqual(self.oldcli.read_bytes(), b'old-cli')
        self.assertEqual((self.old / 'Contents/MacOS/AeroSpace').read_bytes(), b'old')

    def test_restart_after_staging_aborts_without_replacing_originals(self):
        old_tilesail = self.paths['cli'] / 'tilesail'
        old_tilesail.write_bytes(b'old-tilesail')
        p = self.plan()
        paths = [self.old / 'Contents/MacOS/AeroSpace', self.oldcli, old_tilesail, self.agent]
        originals = {path: (path.read_bytes(), path.stat().st_ino, path.stat().st_mtime_ns) for path in paths}
        with patch.object(m, 'running_managers', side_effect=[[], ['TileSail']]) as check:
            with self.assertRaisesRegex(ValueError, 'restarted during preparation'):
                m.apply(p, unregister=False)
            self.assertEqual(check.call_count, 2)
        for path, original in originals.items():
            self.assertEqual((path.read_bytes(), path.stat().st_ino, path.stat().st_mtime_ns), original)
        self.assertTrue(list(self.paths['backups'].glob('*.zip')))
        self.assertFalse((self.paths['applications'] / 'TileSail.app').exists())
        self.assertFalse(list(self.paths['applications'].glob('.tilesail-stage-*')))

    def test_permission_preflight_retains_all_originals(self):
        directory = self.old / 'Contents/MacOS'
        directory.chmod(0o555)
        self.addCleanup(directory.chmod, 0o755)
        with self.assertRaises(PermissionError): m.apply(self.plan(), unregister=False)
        self.assertEqual(self.oldcli.read_bytes(), b'old-cli')
        self.assertEqual((directory / 'AeroSpace').read_bytes(), b'old')
        self.assertFalse(list(self.paths['applications'].glob('.tilesail-stage-*')))

    def test_incomplete_rollback_continues_and_preserves_recovery(self):
        original_copy = m.copy_bundle
        def restore_failure(source, destination):
            if source.name.startswith('original-') and destination == self.old:
                raise PermissionError('Injected restoration denial')
            return original_copy(source, destination)
        with patch.object(m, 'copy_bundle', side_effect=restore_failure):
            with self.assertRaisesRegex(RuntimeError, 'rollback incomplete.*Recovery originals retained at'):
                m.apply(self.plan(), fail_at='remove', unregister=False)
        self.assertEqual(self.oldcli.read_bytes(), b'old-cli')
        self.assertEqual(plistlib.loads(self.agent.read_bytes()), self.obj)
        stages = list(self.paths['applications'].glob('.tilesail-stage-*'))
        self.assertEqual(len(stages), 1)
        self.assertFalse(list(stages[0].rglob('*.app')))
        self.assertTrue((stages[0] / 'TileSail.prepared-bundle').exists())
        self.assertTrue(list(self.paths['backups'].glob('*.zip')))
        recovery = json.loads((stages[0] / 'recovery.json').read_text())
        backup = Path(recovery[str(self.old)])
        self.assertEqual((backup / 'Contents/MacOS/AeroSpace').read_bytes(), b'old')

    def test_duplicate_roots_and_nested_targets(self):
        paths = dict(self.paths, system_applications=self.paths['applications'])
        p = m.plan(**paths, running=[])
        self.assertEqual(p['replacements'].count(self.old), 1)
        nested = self.old / 'Contents/legacy-bin'
        nested.mkdir()
        with self.assertRaisesRegex(ValueError, 'overlaps a replaced app'):
            m.plan(**self.paths, running=[], compatibility_cli=nested)
        nested_agents = self.old / 'Contents/LaunchAgents'
        nested_agents.mkdir()
        (nested_agents / 'managed.plist').write_bytes(self.agent.read_bytes())
        with self.assertRaisesRegex(ValueError, 'overlaps a replaced app'):
            m.plan(**dict(self.paths, agents=nested_agents), running=[])

    def test_startup_exact_paths_and_unrelated_mentions(self):
        destination = self.paths['applications'] / 'TileSail.app'
        executable = str(destination / 'Contents/MacOS/TileSail')
        old_executable = str(self.old / 'Contents/MacOS/AeroSpace')
        direct = m.rewrite(self.obj, destination)
        self.assertEqual(direct['ProgramArguments'][0], executable)
        opened = m.rewrite(dict(self.obj, ProgramArguments=['/usr/bin/open', '-a', str(self.old), '--args', '--config-path', '/cfg']), destination)
        self.assertEqual(opened['ProgramArguments'], ['/usr/bin/open', '-a', str(destination), '--args', '--config-path', '/cfg'])
        program = m.rewrite(dict(self.obj, Program=old_executable), destination)
        self.assertEqual(program['Program'], executable)
        self.assertEqual(program['ProgramArguments'], [executable, '--config-path', '/config/custom.toml'])
        only = m.rewrite({'Program': old_executable, 'ProgramArguments': ['custom-argv0', '--config-path', '/cfg']}, destination)
        self.assertEqual(only['Program'], executable)
        self.assertEqual(only['ProgramArguments'], ['custom-argv0', '--config-path', '/cfg'])
        unrelated = {'Label': 'custom.backup', 'ProgramArguments': ['/usr/bin/echo', 'TileSail.app'], 'Comment': 'AeroSpace notes'}
        self.assertIsNone(m.rewrite(unrelated, destination))
        with self.assertRaisesRegex(ValueError, 'Unrecognized managed startup agent'):
            m.rewrite({'Label': 'com.cassel.aerospace-smooth', 'ProgramArguments': ['/usr/bin/unknown-launch-form']}, destination)


class ProcessDetectionTest(unittest.TestCase):
    def test_spm_app_blocks_but_cli_and_python_do_not(self):
        with patch.object(m.subprocess, 'check_output', return_value='/usr/bin/python3\n/tmp/tilesail\n/tmp/aerospace\n/tmp/AeroSpaceApp\n'):
            self.assertEqual(m.running_managers(), ['/tmp/AeroSpaceApp'])
        with patch.object(m.subprocess, 'check_output', return_value='/usr/bin/python3\n/tmp/tilesail\n/tmp/aerospace\n'):
            self.assertEqual(m.running_managers(), [])
        self.assertNotIn('AeroSpaceApp', m.NAMES)
