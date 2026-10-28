"""Plan/apply a reviewed native-only Apple provider change to the external homelab Compose project.

Default plan is read-only. Apply requires the exact plan fingerprint and a separate approval flag.
No Apple private key, OAuth client secret, schema change or web OAuth setup is involved.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import re
import shutil
import subprocess
import time

ROOT = Path('/home/giovan/apps/supabase')
FILES = [ROOT / 'docker-compose.yml', ROOT / 'docker-compose.cf-tunnel.yml']
BUNDLE_ID = 'io.pibeebee.c67.starter'
KEYS = {'GOTRUE_EXTERNAL_APPLE_ENABLED': 'true',
        'GOTRUE_EXTERNAL_APPLE_CLIENT_ID': BUNDLE_ID,
        'GOTRUE_EXTERNAL_APPLE_SKIP_NONCE_CHECK': 'false'}


def command(*args):
    return subprocess.check_output(args, stderr=subprocess.PIPE, cwd=ROOT)


def container(name):
    return json.loads(command('docker', 'inspect', name))[0]


def compose(*args):
    prefix = ['docker', 'compose']
    for path in FILES:
        prefix += ['-f', str(path)]
    return command(*prefix, *args)


def snapshot():
    names = command('docker', 'ps', '--filter', 'label=com.docker.compose.project=supabase',
                    '--format', '{{.Names}}').decode().splitlines()
    result = {}
    for name in names:
        obj = container(name)
        result[name] = {'id': obj['Id'], 'started': obj['State']['StartedAt']}
    return result


def fingerprint():
    h = hashlib.sha256()
    for p in [ROOT / '.env', *FILES]:
        h.update(str(p).encode()); h.update(p.read_bytes())
    return h.hexdigest()


def updated_compose(text):
    for key in KEYS:
        if re.search(r'(?m)^\s+' + key + r':', text):
            raise RuntimeError('Apple provider settings already exist; review drift instead of overwriting')
    marker = '      GOTRUE_URI_ALLOW_LIST: ${ADDITIONAL_REDIRECT_URLS}'
    if text.count(marker) != 1:
        raise RuntimeError('Unexpected Auth configuration layout')
    additions = '\n'.join('      ' + k + ': "' + v + '"' for k, v in KEYS.items())
    return text.replace(marker, marker + '\n' + additions)


def preflight():
    obj = container('supabase-auth')
    labels = obj['Config'].get('Labels') or {}
    assert labels.get('com.docker.compose.project') == 'supabase'
    assert labels.get('com.docker.compose.project.working_dir') == str(ROOT)
    assert set(labels.get('com.docker.compose.project.config_files', '').split(',')) == set(map(str, FILES))
    assert not any('/data/compose/' in str(p) for p in FILES)
    assert obj['Config']['Image'] == 'supabase/gotrue:v2.197.0'
    assert obj['State'].get('Health', {}).get('Status') == 'healthy'
    current = json.loads(compose('config', '--format', 'json'))
    env = current['services']['auth']['environment']
    assert not env.get('GOTRUE_EXTERNAL_APPLE_SECRET'), 'Existing Apple secret requires a separate review'
    assert not env.get('GOTRUE_EXTERNAL_APPLE_ENABLED'), 'Existing Apple configuration requires review'
    updated_compose(FILES[0].read_text())
    return current


def plan():
    preflight()
    return {'mode': 'plan', 'fingerprint': fingerprint(), 'project': 'supabase', 'service': 'auth',
            'image': 'supabase/gotrue:v2.197.0', 'native_bundle_id': BUNDLE_ID, 'settings': KEYS,
            'files_to_change': [str(FILES[0])], 'restart': 'auth only; --no-deps --pull never',
            'database_changes': False, 'apple_private_key_required': False,
            'expected_downtime': 'brief Auth restart; existing JWTs retain normal expiry',
            'backup_root': '/home/giovan/backups/c67/before-apple-auth-<UTC timestamp>',
            'rollback': 'restore backed-up docker-compose.yml; recreate only auth; recheck health',
            'verification': 'Auth healthy, exact runtime keys, other service IDs/start times unchanged'}


def wait_healthy():
    for _ in range(45):
        obj = container('supabase-auth')
        if obj['State'].get('Health', {}).get('Status') == 'healthy':
            return obj
        time.sleep(1)
    raise RuntimeError('Auth did not become healthy')


def apply(expected):
    base = preflight()
    assert fingerprint() == expected, 'Configuration changed since the reviewed plan'
    before = snapshot()
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H%M%SZ')
    backup = Path('/home/giovan/backups/c67') / ('before-apple-auth-' + stamp)
    backup.mkdir(mode=0o700)
    for p in [ROOT / '.env', *FILES]:
        shutil.copyfile(p, backup / p.name); (backup / p.name).chmod(0o600)
    (backup / 'baseline.json').write_text(json.dumps(before, indent=2)); (backup / 'baseline.json').chmod(0o600)
    hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in backup.iterdir() if p.is_file()}
    (backup / 'checksums.json').write_text(json.dumps(hashes, indent=2)); (backup / 'checksums.json').chmod(0o600)
    temp = FILES[0].with_name('docker-compose.yml.c67-apple-tmp')
    try:
        with temp.open('x') as f:
            f.write(updated_compose(FILES[0].read_text()))
        temp.chmod(0o600); temp.replace(FILES[0])
        updated = json.loads(compose('config', '--format', 'json'))
        assert set(base['services']) == set(updated['services'])
        for name in base['services']:
            if name != 'auth':
                assert base['services'][name] == updated['services'][name], 'Unrelated service drift'
        old = base['services']['auth']; new = updated['services']['auth']
        assert {k: v for k, v in old.items() if k != 'environment'} == {k: v for k, v in new.items() if k != 'environment'}
        changed = {k for k in set(old['environment']) | set(new['environment'])
                   if old['environment'].get(k) != new['environment'].get(k)}
        assert changed == set(KEYS), 'Unexpected Auth environment drift'
        compose('up', '-d', '--no-deps', '--pull', 'never', 'auth')
        obj = wait_healthy()
        runtime = dict(x.split('=', 1) for x in obj['Config']['Env'] if '=' in x)
        assert all(runtime.get(k) == v for k, v in KEYS.items())
        after = snapshot()
        assert set(before) == set(after)
        assert all(after[n] == v for n, v in before.items() if n != 'supabase-auth')
        report = {'applied': True, 'backup': str(backup), 'auth_healthy': True,
                  'other_services_unchanged': len(before) - 1, 'settings': KEYS}
        (backup / 'result.json').write_text(json.dumps(report, indent=2)); (backup / 'result.json').chmod(0o600)
        return report
    except Exception:
        shutil.copyfile(backup / FILES[0].name, FILES[0]); FILES[0].chmod(0o600)
        compose('up', '-d', '--no-deps', '--pull', 'never', 'auth')
        wait_healthy()
        raise
    finally:
        if temp.exists():
            temp.unlink()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['plan', 'apply'], nargs='?', default='plan')
    parser.add_argument('--fingerprint')
    parser.add_argument('--approved-apple-auth', action='store_true')
    args = parser.parse_args()
    if args.action == 'apply':
        if not args.approved_apple_auth or not args.fingerprint:
            parser.error('Apply requires separate approval and the reviewed fingerprint')
        result = apply(args.fingerprint)
    else:
        result = plan()
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        # Compose diagnostics/configuration can contain secrets; never print raw subprocess output.
        raise SystemExit('Apple Auth operation failed: ' + type(error).__name__)
