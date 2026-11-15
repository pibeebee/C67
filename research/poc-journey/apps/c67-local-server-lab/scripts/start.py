#!/usr/bin/env python3
"""Start this lab only, with an ephemeral run token kept in ignored .local files."""
import argparse,json,os,secrets,subprocess,time
from pathlib import Path
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--host',default='127.0.0.1');p.add_argument('--port',type=int,default=8767);p.add_argument('--mode',choices=['replay','rest'],default='replay');p.add_argument('--data-dir',type=Path,default=root/'.local');a=p.parse_args()
a.data_dir.mkdir(parents=True,exist_ok=True)
state=a.data_dir/'process.json'
if state.exists():
 old=json.loads(state.read_text())
 try: os.kill(old['pid'],0)
 except ProcessLookupError: pass
 else: raise SystemExit('Existing lab process; stop it explicitly first')
token=secrets.token_urlsafe(32)
env=dict(os.environ,LAB_ACCESS_TOKEN=token,LAB_PROVIDER_MODE=a.mode,LAB_HOST=a.host,LAB_PORT=str(a.port),LAB_DATA_DIR=str(a.data_dir.resolve()))
binary=root/'.build/debug/planner-server'
if not binary.exists(): raise SystemExit('Run swift build first')
with (a.data_dir/'server.log').open('ab') as log:
 process=subprocess.Popen([str(binary),'serve'],cwd=root,env=env,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
config={'baseURL':f'http://{a.host}:{a.port}','token':token,'mode':a.mode}
configfile=a.data_dir/'client-config.json';configfile.write_text(json.dumps(config));configfile.chmod(0o600)
state.write_text(json.dumps({'pid':process.pid,'binary':str(binary),'config':str(configfile),'startedAt':time.time()}));state.chmod(0o600)
print(json.dumps({'pid':process.pid,'url':config['baseURL'],'configFile':str(configfile),'mode':a.mode}))
