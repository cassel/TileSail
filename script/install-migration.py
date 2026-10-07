#!/usr/bin/env python3
"""Stopped-manager migration. Fixture roots are explicit; never mutates HOME."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid
import zipfile

NAMES = ('TileSail', 'AeroSpace', 'AeroSpaceSmooth')
PROCESS_NAMES = (*NAMES, 'AeroSpaceApp')
IDS = ('us.cassel.tilesail', 'bobko.aerospace', 'bobko.aerospace.debug')
LSREGISTER = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'


def safe(path):
    path = Path(os.path.abspath(path))
    for ancestor in (path, *path.parents):
        if ancestor.is_symlink():
            raise ValueError(f'Unsafe symlink: {ancestor}')
    return path


def rewrite(plist, destination):
    result = dict(plist)
    args = plist.get('ProgramArguments', [])
    if not isinstance(args, list) or not all(isinstance(a, str) for a in args):
        raise ValueError('Malformed ProgramArguments')
    args = list(args)
    def app(value):
        return isinstance(value, str) and any(value.endswith('/' + n + '.app') for n in NAMES)
    def exe(value):
        return isinstance(value, str) and any(value.endswith(f'/{n}.app/Contents/MacOS/{n}') for n in NAMES)
    program = plist.get('Program')
    direct = exe(program)
    argv = bool(args and exe(args[0]))
    open_indexes = [i + 1 for i, value in enumerate(args[:-1])
                    if args[0] == '/usr/bin/open' and value == '-a' and app(args[i + 1])]
    if direct and argv and program != args[0]: raise ValueError('Ambiguous startup executable paths')
    if (direct or argv) and open_indexes or len(open_indexes) > 1:
        raise ValueError('Ambiguous startup executable paths')
    if not (direct or argv or open_indexes):
        label = plist.get('Label')
        if label in ('bobko.aerospace', 'us.cassel.tilesail', 'com.cassel.tilesail', 'bobko.aerospace.debug', 'com.cassel.aerospace-smooth'):
            raise ValueError('Unrecognized managed startup agent; migrate it manually')
        return None
    executable = str(destination / 'Contents/MacOS/TileSail')
    if direct: result['Program'] = executable
    if argv: args[0] = executable
    if open_indexes: args[open_indexes[0]] = str(destination)
    if argv or open_indexes: result['ProgramArguments'] = args

    return result


def overlaps(a, b):
    return a == b or a in b.parents or b in a.parents


def validate_layout(p):
    protected = [p['release'], p['backups']]
    targets = p['replacements'] + [p['destination']] + p['cli_targets'] + [f for f, _ in p['startup']]
    for root in protected:
        for target in targets:
            if overlaps(root, target): raise ValueError(f'Unsafe overlapping installation paths: {root}, {target}')
    if overlaps(p['release'], p['backups']):
        raise ValueError('Release and backup roots must be separate')
    for cli in p['cli_targets']:
        if overlaps(cli, p['destination']): raise ValueError('CLI and application paths must be separate')
    for bundle in [r for r in p['replacements'] if r.suffix == '.app']:
        for target in p['cli_targets'] + [f for f, _ in p['startup']]:
            if overlaps(bundle, target): raise ValueError(f'Target overlaps a replaced app: {target}')


def running_managers():
    output = subprocess.check_output(['/bin/ps', '-axo', 'comm='], text=True)
    return [p for p in output.splitlines() if Path(p.strip()).name in PROCESS_NAMES]


def plan(release, applications, system_applications, cli, agents, backups, project, running=None, compatibility_cli=None):
    roots = [safe(p) for p in (release, applications, system_applications, cli, agents, backups, project)]
    for root in roots:
        if root.exists() and not root.is_dir():
            raise ValueError(f'Installation root must be a directory: {root}')
    release, applications, system_applications, cli, agents, backups, project = roots
    if running is None: running = running_managers()
    if running: raise ValueError('Stop the running window manager before installing: ' + ', '.join(running))
    source = safe(release / 'TileSail.app')
    info = plistlib.loads((source / 'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != 'us.cassel.tilesail' or info.get('CFBundleExecutable') != 'TileSail':
        raise ValueError('Prepared app must be a TileSail Release bundle')
    binaries = [source / 'Contents/MacOS/TileSail', release / 'tilesail', release / 'aerospace']
    for binary in binaries:
        safe(binary)
        if not binary.is_file() or not os.access(binary, os.X_OK): raise ValueError(f'Missing executable: {binary}')
    manifest = json.loads(safe(release / 'install-manifest.json').read_text())
    if not isinstance(manifest, dict): raise ValueError('Malformed executable consistency manifest')
    for binary in binaries:
        relative = str(binary.relative_to(release))
        if manifest.get(relative) != hashlib.sha256(binary.read_bytes()).hexdigest():
            raise ValueError(f'Prepared release integrity mismatch: {relative}; rebuild app and CLI together')
    # Build-generated hashes bind app and compatibility CLIs to one prepared release.
    destination = applications / 'TileSail.app'
    replacements = []
    for root in (applications, system_applications):
        for name in NAMES:
            candidate = safe(root / (name + '.app'))
            if candidate.exists():
                if not candidate.is_dir(): raise ValueError(f'Invalid bundle: {candidate}')
                bundle = plistlib.loads((candidate / 'Contents/Info.plist').read_bytes())
                if bundle.get('CFBundleIdentifier') not in IDS: raise ValueError(f'Unrecognized bundle: {candidate}')
                replacements.append(candidate)
    cli_targets = [cli]
    if compatibility_cli is not None:
        compatibility_cli = safe(compatibility_cli)
        if compatibility_cli.exists() and not compatibility_cli.is_dir():
            raise ValueError(f'Compatibility CLI root must be a directory: {compatibility_cli}')
        if compatibility_cli != cli and compatibility_cli.exists(): cli_targets.append(compatibility_cli)
    for target in cli_targets:
        for name in ('tilesail', 'aerospace'):
          candidate = safe(target / name)
          if candidate.exists():
              if not candidate.is_file(): raise ValueError(f'Invalid CLI: {candidate}')
              replacements.append(candidate)
    startup = []
    if agents.exists():
        for file in agents.glob('*.plist'):
            safe(file)
            raw = file.read_bytes()
            obj = plistlib.loads(raw)
            if not isinstance(obj, dict): raise ValueError(f'Malformed startup plist: {file}')
            updated = rewrite(obj, destination)
            if updated is not None:
                fmt = plistlib.FMT_BINARY if raw.startswith(b'bplist') else plistlib.FMT_XML
                startup.append((file, plistlib.dumps(updated, fmt=fmt)))
    if len(startup) > 1: raise ValueError('Multiple managed startup agents; resolve ambiguity before installing')
    derived = []
    for root in ('.release', '.debug', '.build/xcode', 'xcode/.xcode-build', '.xcode-build', '.build/audit-xcode'):
        build_root = safe(project / root)
        if build_root.exists():
            for name in NAMES:
                for product in build_root.rglob(name + '.app'):
                    safe(product)
                    try: identifier = plistlib.loads((product / 'Contents/Info.plist').read_bytes()).get('CFBundleIdentifier')
                    except (OSError, ValueError): continue
                    if identifier in IDS: derived.append(product)
    result = dict(release=release, destination=destination, cli=cli, backups=backups,
                  replacements=list(dict.fromkeys(replacements)), startup=startup, derived=derived, cli_targets=cli_targets, manifest=manifest)
    validate_layout(result)
    return result


def copy_bundle(source, destination):
    subprocess.run(['/usr/bin/ditto', str(source), str(destination)], check=True, capture_output=True)


def archive(path, output):
    subprocess.run(['/usr/bin/ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(path), str(output)],
                   check=True, capture_output=True)
    with zipfile.ZipFile(output) as z:
        if z.testzip() is not None: raise ValueError(f'Archive validation failed: {output}')


def apply(p, fail_at=None, unregister=True):
    validate_layout(p)
    for path in [p['release'], p['backups'], p['destination'], *p['cli_targets'], *p['replacements'], *[f for f, _ in p['startup']]]:
        safe(path)
    if running_managers(): raise ValueError('Stop the running window manager before installing')
    destination, cli = p['destination'], p['cli']
    # Reject unwritable tree directories before any bundle removal.
    for bundle in [r for r in p['replacements'] if r.is_dir()]:
        for directory in [bundle.parent, bundle, *[d for d in bundle.rglob('*') if d.is_dir() and not d.is_symlink()]]:
            if not os.access(directory, os.W_OK | os.X_OK):
                raise PermissionError(f'Cannot replace unwritable bundle directory: {directory}')
    # Stage before mutation; rollback copies retain filesystem modes and plist bytes.
    destination.parent.mkdir(parents=True, exist_ok=True)
    cli.mkdir(parents=True, exist_ok=True)
    p['backups'].mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix='.tilesail-stage-', dir=destination.parent))
    preserve_stage = False
    try:
        copy_bundle(p['release'] / 'TileSail.app', stage / 'TileSail.app')
        for name in ('tilesail', 'aerospace'): shutil.copy2(p['release'] / name, stage / name)
        for relative, expected in p['manifest'].items():
            if relative not in ('TileSail.app/Contents/MacOS/TileSail', 'tilesail', 'aerospace'): continue
            if hashlib.sha256((stage / relative).read_bytes()).hexdigest() != expected:
                raise ValueError(f'Release changed after planning: {relative}')
        originals = {}
        affected = set(p['replacements']) | {destination} | {target / name for target in p['cli_targets'] for name in ('tilesail', 'aerospace')} | {f for f, _ in p['startup']}
        for i, path in enumerate(affected):
            if path.exists():
                backup = stage / f'original-{i}'
                if path.is_dir(): copy_bundle(path, backup)
                else: shutil.copy2(path, backup)
                originals[path] = backup
                archive(path, p['backups'] / (path.name + '-' + uuid.uuid4().hex + '.zip'))
        if fail_at == 'archive': raise RuntimeError('Injected archive failure')
        # Staging and archives may take time; abort before touching a restarted app.
        if running_managers():
            raise ValueError('A window manager restarted during preparation; suspend its startup job and stop it before retrying')
        try:
            for path in p['replacements']:
                if path.is_dir(): shutil.rmtree(path)
                else: path.unlink()
            if fail_at == 'remove': raise RuntimeError('Injected removal failure')
            os.replace(stage / 'TileSail.app', destination)
            for target in p['cli_targets']:
                for name in ('tilesail', 'aerospace'):
                    staged_cli = target / ('.tilesail-' + uuid.uuid4().hex)
                    try:
                        shutil.copy2(stage / name, staged_cli)
                        os.replace(staged_cli, target / name)
                    finally:
                        staged_cli.unlink(missing_ok=True)
            if fail_at == 'copy': raise RuntimeError('Injected copy failure')
            for file, raw in p['startup']:
                temporary = file.with_name(file.name + '.tilesail-' + uuid.uuid4().hex)
                try:
                    temporary.write_bytes(raw)
                    shutil.copymode(file, temporary)
                    os.replace(temporary, file)
                finally:
                    temporary.unlink(missing_ok=True)
            if fail_at == 'plist': raise RuntimeError('Injected plist failure')
        except BaseException as failure:
            recovery_errors = []
            for path in sorted(affected):
                try:
                    if path.exists():
                        if path.is_dir(): shutil.rmtree(path)
                        else: path.unlink()
                    if path in originals:
                        if originals[path].is_dir(): copy_bundle(originals[path], path)
                        else: shutil.copy2(originals[path], path)
                except BaseException as recovery_error:
                    recovery_errors.append(f'{path}: {recovery_error}')
            if recovery_errors:
                preserve_stage = True
                prepared_app = stage / 'TileSail.app'
                if prepared_app.exists():
                    try: prepared_app.rename(stage / 'TileSail.prepared-bundle')
                    except OSError as rename_error:
                        recovery_errors.append(f'Cannot rename uninstalled prepared app {prepared_app}: {rename_error}')
                (stage / 'recovery.json').write_text(json.dumps({str(p): str(b) for p, b in originals.items()}, indent=2))
                raise RuntimeError(f'{failure}; rollback incomplete. Recovery originals retained at {stage}: ' + '; '.join(recovery_errors)) from failure
            raise
    finally:
        if not preserve_stage: shutil.rmtree(stage)
    if unregister:
        failures = []
        for product in p['derived']:
            result = subprocess.run([LSREGISTER, '-u', str(product)], capture_output=True, text=True)
            if result.returncode: failures.append(f'{product}: {result.stderr}')
        if failures: raise RuntimeError('Installation succeeded, but derived unregistration failed: ' + '; '.join(failures))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    project = Path(__file__).resolve().parent.parent
    home = Path.home()
    for option, default in [('release', project / '.release'), ('applications', home / 'Applications'),
                            ('system-applications', Path('/Applications')), ('cli', home / '.local/bin'),
                            ('compatibility-cli', home / '.config/aerospace/bin'), ('agents', home / 'Library/LaunchAgents'), ('backups', project / '.backups'), ('project', project)]:
        parser.add_argument('--' + option, type=Path, default=default)
    parser.add_argument('--dry-run', action='store_true')
    args = vars(parser.parse_args())
    dry = args.pop('dry_run')
    try:
        p = plan(**args)
        print(f"Install {p['destination']} and matching CLIs into {p['cli']}")
        for path in p['replacements']: print(f"Archive and replace {path}")
        for path, _ in p['startup']: print(f"Preserve and update startup path in {path}")
        for path in p['derived']: print(f"Unregister derived product {path}")
        if not dry: apply(p)
    except subprocess.CalledProcessError as error:
        detail = error.stderr.decode(errors='replace') if isinstance(error.stderr, bytes) else error.stderr
        parser.exit(1, f'Installation tool failed ({error.cmd}, exit {error.returncode}): {detail or error}\n')
    except (OSError, ValueError, RuntimeError, plistlib.InvalidFileException) as error:
        parser.exit(1, f'Installation aborted: {error}\n')

if __name__ == '__main__': main()
