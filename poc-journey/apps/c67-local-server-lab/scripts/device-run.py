#!/usr/bin/env python3
"""Install/launch only after a successful backup; pass token via child environment, not argv/logs."""
import argparse,datetime,json,os,subprocess,sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--device',required=True);p.add_argument('--app',type=Path,required=True);p.add_argument('--run',required=True);p.add_argument('--backup',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--config',type=Path,default=root/'.local/client-config.json');p.add_argument('--live-manifest',type=Path);a=p.parse_args()
if not a.backup.is_dir() or not list(a.backup.rglob('*.json')): raise SystemExit('A verified original data backup is required')
a.output.mkdir(parents=True,exist_ok=True)
config=json.loads(a.config.read_text())
if config['mode'] == 'rest':
 if not a.live_manifest: raise SystemExit('Live requires --live-manifest after replay and credentials gates')
 manifest=json.loads(a.live_manifest.read_text())
 if manifest['status']!='prepared' or manifest['mode']!='rest': raise SystemExit('Live manifest not prepared')
 if datetime.datetime.now(datetime.timezone.utc)>datetime.datetime.fromisoformat(manifest['validUntil']): raise SystemExit('Live manifest expired; re-run preflight')
base=['xcrun','devicectl','device']
install=subprocess.run(base+['install','app','--device',a.device,str(a.app),'--timeout','60'],capture_output=True,text=True)
(a.output/'install.log').write_text(install.stdout+install.stderr)
if install.returncode:raise SystemExit('Install failed; see install.log')
env=dict(os.environ,DEVICECTL_CHILD_LAB_URL=config['baseURL'],DEVICECTL_CHILD_LAB_ACCESS_TOKEN=config['token'],DEVICECTL_CHILD_LAB_RUN_ID=a.run,DEVICECTL_CHILD_LAB_PROVIDER_MODE=config['mode'])
if config['mode']=='rest':
 env['DEVICECTL_CHILD_LAB_LIVE_APPROVED']=manifest['liveGateValue']
 env['DEVICECTL_CHILD_LAB_LIVE_SUBSET']=manifest['subset']
launch=subprocess.run(base+['process','launch','--device',a.device,'--terminate-existing','--timeout','30','giovanchristoffel.c67-trip-integration','--lab-auto'],env=env,capture_output=True,text=True)
(a.output/'launch.log').write_text(launch.stdout+launch.stderr)
print('Launch exit:',launch.returncode)
raise SystemExit(launch.returncode)
