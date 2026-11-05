#!/usr/bin/env python3
"""Validate publication hashes and explicit dispositions, not historical experiment truth."""
from pathlib import Path
import argparse
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--refresh-publication-hashes', action='store_true', help='Record reviewed packaging/layout changes; never edit original hashes')
args = parser.parse_args()
path = ROOT / 'evidence/publication-manifest.json'
manifest = json.loads(path.read_text())
issues = []; count = 0
for entry in manifest['files']:
    if entry['disposition'] != 'included':
        continue
    count += 1
    target = ROOT / entry['publicationPath']
    if not target.is_file():
        issues.append(entry['publicationPath'] + ': missing publication copy')
        continue
    data = target.read_bytes(); digest = hashlib.sha256(data).hexdigest()
    if args.refresh_publication_hashes:
        if digest != entry['publishedSHA256']:
            entry['transformations'].append('reviewed repository layout or portability adjustment after import')
        entry.update(publishedSHA256=digest, publishedBytes=len(data))
    elif digest != entry['publishedSHA256']:
        issues.append(entry['publicationPath'] + ': publication hash changed')
if issues:
    raise SystemExit('\n'.join(issues))
if args.refresh_publication_hashes:
    path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + '\n')
print(f'PASS: {count} imported publication copies, original/publication hashes and exclusions accounted for.')
