#!/usr/bin/env python3
"""Check the public, cloneable handoff without calling a model/provider."""
from pathlib import Path
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
REPO = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], cwd=ROOT, text=True).strip())
issues = []
unavailable = json.loads((ROOT / "evidence/unavailable-local-links.json").read_text())["links"]
known_missing = {(item["source"], item["target"]) for item in unavailable if item.get("reason")}
missing_count = 0
sources = subprocess.check_output(['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard', '--', str(ROOT.relative_to(REPO))], cwd=REPO).decode().split('\0')
paths = [REPO / p for p in sources if p and (REPO / p).is_file()]
links = re.compile(r'\]\((<[^>\n]+>|[^)\n]+)\)')
secret = re.compile(r'\b(?:sk-or-v1-[A-Za-z0-9]{20,}|sk-proj-[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{25,}|ghp_[A-Za-z0-9]{25,}|github_pat_[A-Za-z0-9_]{25,}|sb_secret_[A-Za-z0-9_-]{20,}|eyJ[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{10,})\b')
for path in paths:
    rel = path.relative_to(REPO)
    if path.stat().st_size > 100 * 1024 * 1024:
        issues.append(f'{rel}: exceeds ordinary Git file limit')
    if path.name.startswith('.env') and path.name != '.env.example':
        issues.append(f'{rel}: local environment file')
    if path.suffix in {'.p12', '.p8', '.mobileprovision', '.onnx', '.ipa'} or any(p in {'.git', '.build', 'DerivedData', 'node_modules', 'xcuserdata'} for p in rel.parts):
        issues.append(f'{rel}: excluded private/generated asset')
    try:
        text = path.read_text()
    except UnicodeError:
        continue
    if secret.search(text) or '-----BEGIN ' + 'PRIVATE KEY-----' in text:
        issues.append(f'{rel}: credential-like literal (value withheld)')
    if re.search(r'/Users/[A-Za-z0-9_-]+/', text):
        issues.append(f'{rel}: original home-directory dependency/metadata')
    if re.search(r'\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}\b', text):
        issues.append(f'{rel}: hardware identifier (value withheld)')
    if path.suffix == '.md':
        for match in links.finditer(text):
            target = match.group(1).strip().strip('<>')
            if target.startswith(('https:', 'http:', 'mailto:', '#', 'data:')):
                continue
            if target.startswith(('thread:', 'plugin:', 'codex:', 'app:')):
                issues.append(f'{rel}: private chat/app link')
            elif not (path.parent / target.split('#')[0]).exists():
                if (path.relative_to(ROOT).as_posix(), target) in known_missing:
                    missing_count += 1
                else:
                    issues.append(f'{rel}: missing local target {target}')
    if path.name == 'Package.swift':
        for target in re.findall(r'\.package\(path:\s*"([^"]+)"', text):
            if not (path.parent / target).is_dir():
                issues.append(f'{rel}: missing local package {target}')
if issues:
    print('\n'.join(issues))
    raise SystemExit(1)
print(f'PASS: {len(paths)} publication files; local links/packages and configured private-data patterns checked.')
print(f'Historical unavailable attachments: {missing_count}; exact paths recorded in evidence/unavailable-local-links.json.')
print('This is a bounded static scan, not a guarantee that no sensitive content exists.')
