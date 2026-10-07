#!/usr/bin/env python3
"""Translate prepared executable hashes to release-package relative paths."""
import json
from pathlib import Path
import sys


def package_manifest(source, destination):
    manifest = json.loads(Path(source).read_text())
    packaged = {('bin/' + path if path in ('tilesail', 'aerospace') else path): digest
                for path, digest in manifest.items()}
    Path(destination).write_text(json.dumps(packaged, indent=2) + '\n')


if __name__ == '__main__':
    package_manifest(*sys.argv[1:])
