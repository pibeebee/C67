#!/usr/bin/env python3
"""Restore the original signed app; preserve the data container and verify its normal store."""
import argparse,hashlib,json,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--device',required=True);p.add_argument('--original-app',type=Path,required=True);p.add_argument('--before',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
if not a.original_app.is_dir() or not a.before.is_dir():raise SystemExit('Original app and pre-install backup are required')
a.output.mkdir(parents=True,exist_ok=False)
def run(name,args):
 r=subprocess.run(['xcrun','devicectl','device',*args],capture_output=True,text=True)
 (a.output/(name+'.log')).write_text(r.stdout+r.stderr);return r.returncode
installed=run('restore-install',['install','app','--device',a.device,str(a.original_app),'--timeout','60'])==0
if not installed:raise SystemExit('Restore install failed; original backup retained')
after=a.output/'normal-store-after'
copied=run('restore-data-copy',['copy','from','--device',a.device,'--domain-type','appDataContainer','--domain-identifier','giovanchristoffel.c67-trip-integration','--source','Library/Application Support/C67TripIntegration-v1','--destination',str(after),'--timeout','30'])==0
def hashes(root):return {str(f.relative_to(root)):hashlib.sha256(f.read_bytes()).hexdigest() for f in root.rglob('*') if f.is_file()}
before=hashes(a.before);actual=hashes(after) if copied else {}
launched=run('restore-launch',['process','launch','--device',a.device,'--terminate-existing','--timeout','15','giovanchristoffel.c67-trip-integration'])==0
result={'installed':installed,'launched':launched,'before':before,'after':actual,'identical':copied and bool(before) and before==actual}
(a.output/'verification.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({k:result[k] for k in ['installed','launched','identical']}))
raise SystemExit(0 if result['identical'] and launched else 2)
