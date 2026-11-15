#!/usr/bin/env python3
"""Inspect existing OpenRouter credentials/catalogue without printing secrets or generating tokens."""
import json, shlex, time, subprocess
from pathlib import Path

LAB = Path(__file__).resolve().parents[1]
OUT = LAB / 'artifacts/personal-recommendation-2026-11-08'
OUT.mkdir(parents=True, exist_ok=True)
def config():
    result = {}
    for path in [LAB.parent/'ai-trip-planner/.env', LAB/'.env.local']:
        if not path.exists(): continue
        for line in path.read_text().splitlines():
            line = line.strip().removeprefix('export ')
            if not line or line.startswith('#') or '=' not in line: continue
            key, value = line.split('=', 1)
            if not key.strip().startswith('OPENROUTER_'): continue
            try:
                parts = shlex.split(value, comments=True)
                if len(parts) == 1: result[key.strip()] = parts[0]
            except ValueError: pass
    return result

def get(path, key=None):
    try:
        # macOS curl uses the system trust store. Key travels over stdin, never argv or disk.
        cfg = 'url = ' + json.dumps('https://openrouter.ai/api/v1/' + path) + '\n'
        if key: cfg += 'header = ' + json.dumps('Authorization: Bearer ' + key) + '\n'
        run = subprocess.run(['curl','-sS','--max-time','20','-K','-','-w','\n%{http_code}'],
            input=cfg,text=True,capture_output=True)
        body, status = run.stdout.rsplit('\n',1)
        return int(status), json.loads(body) if body else {}
    except Exception as e: return 0, {'errorType':type(e).__name__}

if __name__ == '__main__':
    cfg = config(); key = cfg.get('OPENROUTER_API_KEY')
    status, value = get('key', key) if key else (0,{})
    data = value.get('data', {})
    result = {'checkedAt':time.time(), 'keyPresent':bool(key), 'keyHTTP':status,
              'isFreeTier':data.get('is_free_tier'), 'rateLimit':data.get('rate_limit')}
    status, value = get('models')
    free = [m for m in value.get('data', []) if m.get('id','').endswith(':free')
            and float(m.get('pricing',{}).get('prompt',1)) == 0
            and float(m.get('pricing',{}).get('completion',1)) == 0]
    result['catalogueHTTP'] = status
    result['freeModels'] = [{'id':m['id'], 'supportedParameters':m.get('supported_parameters',[]),
        'contextLength':m.get('context_length'), 'pricing':m.get('pricing')} for m in free]
    result['previousModel'] = cfg.get('OPENROUTER_MODEL')
    (OUT/'openrouter-preflight.json').write_text(json.dumps(result,indent=2))
    print(json.dumps(result,indent=2))
