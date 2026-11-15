#!/usr/bin/env python3
"""Freeze this development series before any evaluation-case run."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
PACKAGE = Path('/Users/neuhendra/Downloads/foundation-models-evaluation-2026-11-04')
BINARY = Path('/tmp/c67-foundation-model-evaluator-v4')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def command(*args):
    return subprocess.check_output(args, text=True).strip()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--package', type=Path, default=PACKAGE)
    parser.add_argument('--binary', type=Path, default=BINARY)
    args = parser.parse_args()
    package = args.package.resolve()
    binary = args.binary.resolve()
    target = HERE / 'freeze.json'
    if target.exists() or (HERE / 'runs-evaluation-diagnostic.jsonl').exists():
        raise SystemExit('Already frozen or evaluation phase already started')
    cases = [json.loads(line) for line in (package / 'inputs.jsonl').read_text().splitlines()]
    expected = {case['id'] for case in cases if case['split'] == 'development'}
    seen = set()
    for path in (HERE / 'runs-sanity.jsonl', HERE / 'runs-development-diagnostic.jsonl'):
        for line in path.read_text().splitlines():
            item = json.loads(line)
            if item['promptVersion'] == 'package-v1/schema-v4-dynamic-nullable':
                seen.add(item['caseID'])
    if expected != seen:
        raise SystemExit(f'Current-schema development cases missing or unexpected: {expected ^ seen}')
    expected_checksums = json.loads((package / 'checksums.json').read_text())
    mismatches = [name for name, value in expected_checksums.items() if digest(package / name) != value]
    if mismatches:
        raise SystemExit(f'Package checksum mismatch: {mismatches}')
    probe = r'''import Foundation
import FoundationModels
let m = SystemLanguageModel.default
let result: [String: Any] = ["model": "SystemLanguageModel.default", "availability": String(describing: m.availability), "id_ID": m.supportsLocale(Locale(identifier: "id_ID")), "en_US": m.supportsLocale(Locale(identifier: "en_US")), "supportedLanguages": m.supportedLanguages.map { $0.minimalIdentifier }.sorted(), "modelVersion": "not exposed by the observed API"]
print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))'''
    preflight = json.loads(command('xcrun', 'swift', '-e', probe))
    files = [HERE / 'Evaluator.swift', HERE / 'run_evaluation.py', HERE / 'generated-schema-v4.json', binary,
             package / 'inputs.jsonl', package / 'model-instructions.txt',
             package / 'output-contract.json', package / 'local-tool-fixtures.json']
    frozen = {'frozenAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'promptVersion': 'package-v1/schema-v4-dynamic-nullable',
              'note': 'Follow-up after v2 evaluation was exposed; not a fresh holdout. Oracle was not read by model executable.',
              'sha256': {str(path): digest(path) for path in files},
              'settings': {'model': 'SystemLanguageModel.default', 'samplingMode': 'greedy',
                           'temperature': None, 'seed': None, 'maximumResponseTokens': 1400,
                           'maximumToolCalls': 2, 'timeoutSeconds': 20,
                           'network': 'evaluator process sandbox denies network', 'sessions': 'new process and session per run'}}
    target.write_text(json.dumps(frozen, indent=2, ensure_ascii=False) + '\n')
    manifest = {'observedAt': frozen['frozenAt'], 'deviceModel': command('sysctl', '-n', 'hw.model'),
                'processor': command('sysctl', '-n', 'machdep.cpu.brand_string'),
                'memoryBytes': int(command('sysctl', '-n', 'hw.memsize')),
                'os': command('sw_vers'), 'xcode': command('xcodebuild', '-version'),
                'swift': command('xcrun', 'swift', '--version'),
                'macOSSDK': command('xcrun', '--sdk', 'macosx', '--show-sdk-version'),
                'systemLocale': command('defaults', 'read', '-g', 'AppleLocale'),
                'timeZone': command('date', '+%Z %z'),
                'runtimePreflight': preflight,
                'packageChecksums': expected_checksums,
                'packageChecksumVerification': f'All {len(expected_checksums)} supplied hashes matched before freezing.',
                'freezeFile': 'freeze.json', 'scope': 'Mac only; no physical iPhone inference',
                'networkCaveat': 'Evaluator process denied socket access; system daemons are not proven offline.'}
    (HERE / 'manifest.json').write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + '\n')
    print(f'Frozen {len(expected)} development cases; {len(files)} inputs/binaries hashed.')


if __name__ == '__main__':
    main()
