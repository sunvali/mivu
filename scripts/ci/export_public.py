#!/usr/bin/env python3
"""Export the app source at a release tag into a public mirror checkout.

Usage: python3 scripts/ci/export_public.py v1.1.0 ../mivu-public

Only ios/ and the files in public/ leave this repository. The export is checked for
secret-looking strings before anything is written; a previous export is replaced
while its .git history is kept. Nothing is committed or pushed.
"""
import io
import re
import shutil
import subprocess
import sys
import tarfile
from pathlib import Path

PATHS = ['ios', 'public']
SECRETS = re.compile(rb'sk-(?:proj-)?[A-Za-z0-9_-]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}'
                     rb'|gh[pousr]_[A-Za-z0-9]{36}|client_secret\s*[:=]\s*["\'][^"\']+')


def main(ref, out):
    archive = subprocess.run(['git', 'archive', '--format=tar', ref, *PATHS], check=True, capture_output=True).stdout
    files = {}
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        for member in tar.getmembers():
            if member.isfile():
                name = member.name.removeprefix('public/')
                files[name] = tar.extractfile(member).read()
    leaks = sorted(name for name, data in files.items() if SECRETS.search(data))
    if leaks:
        sys.exit('Refusing to export; secret-looking content in: ' + ', '.join(leaks))
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    for child in out.iterdir():
        if child.name != '.git':
            shutil.rmtree(child) if child.is_dir() else child.unlink()
    for name, data in files.items():
        (out / name).parent.mkdir(parents=True, exist_ok=True)
        (out / name).write_bytes(data)
    print(f'Exported {len(files)} files from {ref} to {out}')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
