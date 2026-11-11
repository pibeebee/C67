#!/usr/bin/env python3
import argparse,hashlib,json,platform,subprocess,datetime
from pathlib import Path
root=Path(__file__).resolve().parents[1];workspace=root.parents[1]
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def hashes():
 files=[root/'Package.swift',root/'Package.resolved']
 for folder in ['Sources','ClientHarness','Tests','scripts','fixtures']:
  files += [p for p in (root/folder).rglob('*') if p.is_file() and '__pycache__' not in p.parts and p.name not in ['RunConfig.json'] and p.suffix not in ['.png']]
 return {str(p.relative_to(root)):digest(p) for p in sorted(files) if p.exists()}
p=argparse.ArgumentParser();p.add_argument('output',type=Path);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
original=json.loads((root/'fixtures/original-source-manifest.json').read_text())
changed=[s for s,h in original.items() if not (workspace/s).exists() or digest(workspace/s)!=h]
manifest={'createdAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'platform':platform.platform(),'sourceHashes':hashes(),'originalSourceCount':len(original),'originalSourceChanged':changed,
 'policy':{'mode':'synthetic_replay','oracle':'distance-time-v1','clock':'2026-11-06T00:00:00Z','dateEncoding':'unix-double','order':['ABC','BCA','CAB'],'objective':'elapsed_v2','objectiveToleranceSeconds':1,'hardConstraintSlackSeconds':0,'workerConcurrency':1,'providerConcurrency':1,'responseCacheCrossJob':False,'callCap':3000,'cellCap':6000,'clientTimeoutSeconds':240,'speedGate':'live_only_3_complete_pairs_per_N3_N4_N5_median_C_over_A_at_most_0.70','qualityClockFixed':True}}
manifest['policyHash']=hashlib.sha256(json.dumps(manifest['policy'],sort_keys=True).encode()).hexdigest()
(a.output/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
if changed: raise SystemExit('Original source changed: '+str(changed))
print('Frozen manifest; original files unchanged:',len(original))
