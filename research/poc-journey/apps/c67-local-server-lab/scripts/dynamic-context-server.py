#!/usr/bin/env python3
"""Start an isolated authenticated context server with privately loaded provider keys."""
import argparse,json,os,secrets,shlex,signal,subprocess,time,urllib.request
from pathlib import Path
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('action',choices=['start','stop']);p.add_argument('--port',type=int,default=8778);a=p.parse_args()
directory=root/'.local/dynamic-context-simulator';directory.mkdir(parents=True,exist_ok=True)
state=directory/'process.json'
if a.action=='stop':
 if not state.exists():raise SystemExit('No context process recorded')
 d=json.loads(state.read_text())
 command=subprocess.run(['ps','-p',str(d['pid']),'-o','command='],capture_output=True,text=True).stdout
 if str(root/'.build/debug/planner-server') not in command:raise SystemExit('Recorded process no longer matches lab server')
 os.kill(d['pid'],signal.SIGTERM)
 state.unlink();(directory/'client-config.json').unlink(missing_ok=True)
 print('Context server stopped and local client token file revoked')
 raise SystemExit(0)
if state.exists():raise SystemExit('A context process is already recorded; stop it explicitly first')
env=dict(os.environ)
allowed={'GOOGLE_PLACES_API_KEY','APPLE_TEAM_ID','MAPS_KEY_ID','MAPS_KEY_PATH','WEATHER_KEY_ID','WEATHER_KEY_PATH','WEATHER_SERVICE_ID','OPENROUTER_API_KEY','OPENROUTER_MODEL','OPENROUTER_FALLBACK_MODEL'}
for raw in (root/'.env.local').read_text().splitlines():
 line=raw.strip().removeprefix('export ')
 if '=' not in line:continue
 name,value=line.split('=',1);name=name.strip()
 if name not in allowed:continue
 values=shlex.split(value,comments=True)
 if len(values)>1:raise SystemExit('Invalid private config format')
 if not env.get(name):env[name]=values[0] if values else ''
# Reuse the existing private OpenRouter key without rewriting the original CLI configuration.
legacy=root.parent/'ai-trip-planner/.env'
if legacy.exists():
 for raw in legacy.read_text().splitlines():
  line=raw.strip().removeprefix('export ')
  if '=' not in line:continue
  name,value=line.split('=',1);name=name.strip()
  if name not in {'OPENROUTER_API_KEY'} or env.get(name):continue
  values=shlex.split(value,comments=True)
  if len(values)==1:env[name]=values[0]
env.setdefault('OPENROUTER_MODEL','stealth/crouton-alpha')
env.setdefault('OPENROUTER_FALLBACK_MODEL','nvidia/nemotron-3.5-super-vl:free')
token=secrets.token_urlsafe(32)
env.update(LAB_ACCESS_TOKEN=token,LAB_PROVIDER_MODE='rest',LAB_HOST='127.0.0.1',LAB_PORT=str(a.port),LAB_DATA_DIR=str(directory),LAB_CONTEXT_EXPERIMENTS='1',LAB_CONTEXT_HTTP_CAP='900',LAB_CONTEXT_ETA_CAP='720',GOOGLE_PLACES_MAX_REQUESTS='60')
with (directory/'server.log').open('ab') as log:
 proc=subprocess.Popen([str(root/'.build/debug/planner-server'),'serve'],cwd=root,env=env,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
config={'baseURL':f'http://127.0.0.1:{a.port}','token':token}
for path,data in [(directory/'client-config.json',config),(state,{'pid':proc.pid,'binary':str(root/'.build/debug/planner-server')})]:
 path.write_text(json.dumps(data));path.chmod(0o600)
for attempt in range(120):
 if proc.poll() is not None:raise SystemExit('Context server exited; inspect private log')
 try:
  with urllib.request.urlopen(config['baseURL']+'/health',timeout=1) as r:
   if r.status==200:break
 except Exception:time.sleep(.5)
else:raise SystemExit('Server health timeout; process remains recorded for diagnosis')
path=root/'ContextHarness/RunConfig.json';path.write_text(json.dumps(config));path.chmod(0o600)
print(json.dumps({'status':'ready','baseURL':config['baseURL'],'clientConfig':str(path)}))
