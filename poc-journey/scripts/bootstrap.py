#!/usr/bin/env python3
"""Restore only pinned public model assets; never invoke a provider or install credentials."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / 'apps/c67-foundation-lab/Packages/PreferenceLearning/Sources/PreferenceLearning/Resources/Model'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check', action='store_true', help='Verify existing assets without downloading')
args = parser.parse_args()
manifest = json.loads((MODEL / 'manifest.json').read_text())
if not args.check:
    subprocess.run([sys.executable, str(ROOT / 'apps/c67-foundation-lab/scripts/prepare-preference-model.py')], check=True)
    manifest = json.loads((MODEL / 'manifest.json').read_text())
errors = []
for name, expected in manifest['files'].items():
    path = MODEL / name
    if not path.is_file():
        errors.append(name + ': missing; run bootstrap.py')
    elif path.stat().st_size != expected['bytes'] or hashlib.sha256(path.read_bytes()).hexdigest() != expected['sha256']:
        errors.append(name + ': size/hash mismatch')
if errors:
    raise SystemExit('\n'.join(errors))
# The server has its own Bundle.module resource directory.
context_model = ROOT / 'apps/c67-local-server-lab/Sources/PlannerEngine/Resources/Model'
if context_model.is_dir():
    import shutil
    context_manifest = json.loads((context_model / 'manifest.json').read_text())
    for name, expected in context_manifest['files'].items():
        source = MODEL / name
        if hashlib.sha256(source.read_bytes()).hexdigest() != expected['sha256']:
            raise SystemExit('Context Lab model manifest disagrees with the shared pinned assets')
        shutil.copyfile(source, context_model / name)
print('PASS: pinned E5 assets verified and restored to the available app resource roots; no inference or provider request executed.')
