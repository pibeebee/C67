#!/usr/bin/env python3
"""Bounded, resumable pilot enrichment run. Never calls Apple/Google Places or Firecrawl.

Reads private environment files as data (no shell execution), uses an isolated data
folder, and writes only credential-free results. Reusing --output resumes its cache.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import secrets
import shlex
import signal
import socket
import subprocess
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


def dotenv(path):
    values = {}
    if path.exists():
        for line in path.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith('#') or '=' not in line:
                continue
            key, raw = line.removeprefix('export ').split('=', 1)
            pieces = shlex.split(raw, comments=True)
            values[key.strip()] = ' '.join(pieces)
    return values


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--node-path', default=os.environ.get('NODE_PATH', ''))
    parser.add_argument('--max-pages', type=int, default=5, choices=range(1, 9))
    parser.add_argument('--timeout', type=int, default=5400)
    parser.add_argument('--retry-extraction-errors', action='store_true', help='Retry failed model extraction in an offline experiment, preserving existing facts and the original result.')
    parser.add_argument('--verify-cache', action='store_true', help='Check existing pilot cache after restart, preserving the original result.')
    parser.add_argument('--offline-source', type=Path, help='Replay exactly the saved page URLs per branch; no website requests.')
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    os.chmod(output, 0o700)
    local = dotenv(ROOT / '.env.local')
    legacy = dotenv(ROOT.parent / 'c67-local-server-lab/.env.local')
    catalog = dotenv(ROOT.parent / 'c67-preference-lab/.env.catalog.local')
    # Explicit allowlist excludes the legacy Google credentials and Firecrawl key.
    names = ['APPLE_TEAM_ID', 'MAPS_KEY_ID', 'MAPS_KEY_PATH', 'WEATHER_KEY_ID', 'WEATHER_KEY_PATH', 'WEATHER_SERVICE_ID']
    env = {k: v for k, v in os.environ.items() if not any(x in k.upper() for x in ['GOOGLE', 'FIRECRAWL', 'OPENROUTER'])}
    for key in names:
        value = os.environ.get(key) or local.get(key) or legacy.get(key)
        if value:
            env[key] = value
    env['GIOVANC_API_KEY'] = os.environ.get('GIOVANC_API_KEY') or local.get('GIOVANC_API_KEY') or catalog.get('CATALOG_LLM_API_KEY', '')
    env['GIOVANC_MODEL'] = os.environ.get('GIOVANC_MODEL') or local.get('GIOVANC_MODEL') or catalog.get('CATALOG_LLM_MODEL', '')
    env['GIOVANC_TIMEOUT_SECONDS'] = os.environ.get('GIOVANC_TIMEOUT_SECONDS') or local.get('GIOVANC_TIMEOUT_SECONDS') or '90'
    if not env['GIOVANC_API_KEY'] or not env['GIOVANC_MODEL']:
        raise SystemExit('Private luna-provider.example credentials/model are missing.')
    token = secrets.token_hex(32)
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    env.update(LAB_HOST='127.0.0.1', LAB_PORT=str(port), LAB_ACCESS_TOKEN=token, LAB_DATA_DIR=str(output / 'state'),
               LAB_PROVIDER_MODE='rest', VENUE_ENRICHMENT_ENABLED='1', VENUE_WEB_PROVIDER='playwright',
               VENUE_PLAYWRIGHT_MAX_PAGES=str(args.max_pages), VENUE_URL_DISCOVERY='none', NODE_PATH=args.node_path)
    roster_path = ROOT / 'Sources/VenueDiscovery/Resources/pilot-venues.json'
    binary = ROOT / '.build/debug/venue-context-server'
    if not binary.exists():
        # Xcode's new SwiftPM backend may use this products path instead.
        binary = ROOT / '.build/out/Products/Debug/venue-context-server'
    if args.retry_extraction_errors and not args.offline_source:
        raise SystemExit('Extraction retries are allowed only in an offline replay.')
    if args.offline_source:
        source = args.offline_source.resolve()
        saved = json.loads((source / 'state/venue-evidence-v1.json').read_text())
        previous = json.loads((source / 'result.json').read_text())
        state_dir = output / 'state'
        state_dir.mkdir(exist_ok=True)
        state_file = state_dir / 'venue-evidence-v1.json'
        if not state_file.exists():
            state_file.write_text(json.dumps({'facts': {}, 'pages': saved['pages'], 'lastFailure': {}, 'reservedCredits': 0}))
        manifest = output / 'replay-manifest.json'
        manifest.write_text(json.dumps({r['venueID']: r['pageURLs'] for r in previous['diagnostics']}))
        env.update(VENUE_RESEARCH_OFFLINE='1', VENUE_REPLAY_MANIFEST=str(manifest))
        if args.retry_extraction_errors:
            cached = json.loads(state_file.read_text())
            for venue_id, report in (cached.get('reports') or {}).items():
                if report['stage'] == 'extracting_failed':
                    cached['lastFailure'].pop(venue_id, None)
            state_file.write_text(json.dumps(cached))
    config = {'offlineSource': str(args.offline_source.resolve()) if args.offline_source else None, 'model': env['GIOVANC_MODEL'], 'webProvider': 'playwright', 'urlDiscovery': 'none', 'modelTimeoutSeconds': float(env['GIOVANC_TIMEOUT_SECONDS']), 'maxPages': args.max_pages,
              'rosterSHA256': hashlib.sha256(roster_path.read_bytes()).hexdigest(),
              'sourceSHA256': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                               for p in [ROOT / 'Scripts/playwright-collect.cjs', *sorted((ROOT / 'Sources/VenueDiscovery').glob('*.swift'))]},
              'cachePolicyDays': 30, 'googlePlacesCalls': 0, 'appleCalls': 0, 'firecrawlCalls': 0}
    if not args.verify_cache:
        (output / ('retry-run-config.json' if args.retry_extraction_errors else 'run-config.json')).write_text(json.dumps(config, indent=2) + '\n')

    def request(path, method='GET'):
        req = urllib.request.Request(f'http://127.0.0.1:{port}' + path, method=method,
                                     headers={'Authorization': 'Bearer ' + token})
        with urllib.request.urlopen(req, timeout=15) as response:
            return json.load(response)

    def save(name, value):
        temporary = output / (name + '.tmp')
        temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
        temporary.replace(output / name)

    started = time.monotonic()
    with (output / 'server.log').open('a') as log:
        server = subprocess.Popen([str(binary)], cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            for _ in range(120):
                if server.poll() is not None:
                    raise RuntimeError('Server exited; inspect server.log (credentials are never logged by this harness).')
                try:
                    if request('/health')['status'] == 'ok':
                        break
                except (OSError, ValueError):
                    time.sleep(0.5)
            else:
                raise TimeoutError('Server startup timed out.')
            before = request('/v1/lab/evidence/status')
            if args.verify_cache:
                state = json.loads((output / 'state/venue-evidence-v1.json').read_text())
                roster = json.loads(roster_path.read_text())
                now = time.time()
                for venue in roster:
                    facts = state['facts'].get(venue['id'], [])
                    if isinstance(facts, list):
                        facts = dict(zip(facts[::2], facts[1::2]))
                    fresh = sum(f['checkedAt'] <= now < f['checkedAt'] + 30 * 86400 for f in facts.values())
                    if fresh < 3 and now - state['lastFailure'].get(venue['id'], 0) >= 3600:
                        raise RuntimeError('Cache verification refused: a venue is eligible for new work. Run a regular benchmark to resume it.')
            initial = request('/v1/lab/evidence/pilot', 'POST')
            print(json.dumps({'queued': initial, 'model': config['model']}, ensure_ascii=False), flush=True)
            previous = None
            while True:
                status = request('/v1/lab/evidence/status')
                diagnostics = request('/v1/lab/evidence/diagnostics')
                snapshot = {'elapsedSeconds': round(time.monotonic() - started, 3), 'status': status,
                            'results': request('/v1/lab/evidence/pilot'), 'diagnostics': diagnostics}
                if not args.verify_cache:
                    save('retry-progress.json' if args.retry_extraction_errors else 'progress.json', snapshot)
                signature = (status['pending'], status['freshSupportedFacts'], len(diagnostics))
                if signature != previous:
                    print(json.dumps({'elapsed': round(snapshot['elapsedSeconds']), 'pending': status['pending'],
                                      'supported': status['freshSupportedFacts'], 'reports': len(diagnostics)}), flush=True)
                    previous = signature
                if status['pending'] == '0':
                    break
                if time.monotonic() - started > args.timeout:
                    raise TimeoutError('Run deadline reached; partial state and diagnostics are retained.')
                time.sleep(3)
            repeat = request('/v1/lab/evidence/pilot', 'POST')
            after = request('/v1/lab/evidence/status')
            snapshot.update(before=before, initial=initial, repeat=repeat, after=after)
            save('cache-verification.json' if args.verify_cache else 'retry-result.json' if args.retry_extraction_errors else 'result.json', snapshot)
            print(json.dumps({'finished': True, 'elapsedSeconds': snapshot['elapsedSeconds'], 'repeat': repeat}), flush=True)
        finally:
            server.send_signal(signal.SIGINT)
            try:
                server.wait(timeout=20)
            except subprocess.TimeoutExpired:
                server.terminate()
                server.wait(timeout=10)


if __name__ == '__main__':
    main()
