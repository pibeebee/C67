#!/usr/bin/env python3
import argparse,base64,datetime,json,os,subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--simulator',required=True);p.add_argument('--run',required=True);p.add_argument('--config',type=Path,default=root/'.local/client-config.json');p.add_argument('--no-auto',action='store_true');p.add_argument('--url');p.add_argument('--live-manifest',type=Path);a=p.parse_args()
c=json.loads(a.config.read_text())
if c['mode']=='rest':
 if not a.live_manifest:raise SystemExit('REST launch requires --live-manifest')
 manifest=json.loads(a.live_manifest.read_text())
 if manifest['status']!='prepared' or manifest['mode']!='rest':raise SystemExit('Live manifest not prepared')
 if datetime.datetime.now(datetime.timezone.utc)>datetime.datetime.fromisoformat(manifest['validUntil']):raise SystemExit('Live manifest expired')
elif c['mode']!='replay':raise SystemExit('Unsupported provider mode')
env=dict(os.environ,SIMCTL_CHILD_LAB_URL=a.url or c['baseURL'],SIMCTL_CHILD_LAB_ACCESS_TOKEN=c['token'],SIMCTL_CHILD_LAB_RUN_ID=a.run,SIMCTL_CHILD_LAB_PROVIDER_MODE=c['mode'])
if c['mode']=='rest':
 env['SIMCTL_CHILD_LAB_LIVE_APPROVED']=manifest['liveGateValue']
 env['SIMCTL_CHILD_LAB_LIVE_SUBSET']=manifest['subset']
 if manifest.get('comparison'):env['SIMCTL_CHILD_LAB_COMPARISON']=manifest['comparison']
 if manifest.get('families'):env['SIMCTL_CHILD_LAB_CASE_FAMILIES']=','.join(manifest['families'])
 if manifest.get('caseIDs'):env['SIMCTL_CHILD_LAB_CASE_IDS']=','.join(manifest['caseIDs'])
 if manifest.get('pinSnapshotFile'):
  data=Path(manifest['pinSnapshotFile']).read_bytes()
  env['SIMCTL_CHILD_LAB_PIN_SNAPSHOT_BASE64']=base64.b64encode(data).decode()
 env['SIMCTL_CHILD_LAB_PROVIDER_CALLS_OFFSET']=str(manifest.get('earlierCampaignCallsReserved',0))
 env['SIMCTL_CHILD_LAB_ETA_CELLS_OFFSET']=str(manifest.get('earlierCampaignCellsReserved',0))
subprocess.run(['xcrun','simctl','terminate',a.simulator,'giovanchristoffel.c67-trip-integration'],capture_output=True)
cmd=['xcrun','simctl','launch',a.simulator,'giovanchristoffel.c67-trip-integration']
if not a.no_auto:cmd+=['--lab-auto']
raise SystemExit(subprocess.run(cmd,env=env).returncode)
