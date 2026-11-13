#!/usr/bin/env python3
"""Apply the predeclared host-sleep recovery rule, retaining raw blocks independently."""
import argparse,datetime,json,shutil
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--before',type=Path,required=True);p.add_argument('--resume',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
first=json.loads((a.before/'observations.json').read_text());second=json.loads((a.resume/'observations.json').read_text())
status=json.loads((a.resume/'status.json').read_text())
if not status['complete'] or len(second)!=33:raise SystemExit('Resume not complete; primary result cannot yet be assembled')
manifest=json.loads((a.resume/'live-manifest.json').read_text())
assert manifest['families']==['N5','REV5','MIX5','TIGHT5','SIX','UNKNOWN','N1']
retained=[x for x in first if x['family'] in ['N3','N4']]
excluded=[x for x in first if x['family'] not in ['N3','N4']]
assert len(retained)==18
sleep=datetime.datetime.fromisoformat('2026-11-06T20:20:19+07:00').timestamp()
for x in retained:
 assert x['outcome']['outcome']=='ready'
 assert x['outcome']['plan']['createdAt']+x['clientSeconds']<sleep,'Retained observation overlaps host sleep'
old=json.loads((a.before/'manifest.json').read_text());new=json.loads((a.resume/'manifest.json').read_text())
engine_differences=[path for path,h in old['sourceHashes'].items() if path.startswith('Sources/') and new['sourceHashes'].get(path)!=h]
assert not engine_differences,engine_differences
assert (a.before/'common-pins.json').read_bytes()==(a.resume/'common-pins.json').read_bytes()
merged=[]
for block,items in [(a.before,retained),(a.resume,second)]:
 for row in items:merged.append(dict(row,sourceRun=block.name))
assert len(merged)==51 and len({(r['caseID'],r['variant']) for r in merged})==51
families={family:sum(r['family']==family for r in merged) for family in ['N1','N3','N4','N5','REV5','MIX5','TIGHT5','SIX','UNKNOWN']}
assert all(families[x]==9 for x in ['N1','N3','N4','N5'])
assert all(families[x]==3 for x in ['REV5','MIX5','TIGHT5','SIX','UNKNOWN'])
a.output.mkdir(parents=True,exist_ok=True)
(a.output/'observations.json').write_text(json.dumps(merged,separators=(',',':'))+'\n')
(a.output/'selection-manifest.json').write_text(json.dumps({'rule':manifest['selectionRule'],'retainedBeforeSleep':18,'resumeObservations':33,'allDiscardedFromPrimaryButPreservedInRaw':[{'case':x['caseID'],'variant':x['variant'],'outcome':(x.get('outcome')or{}).get('outcome'),'seconds':x['clientSeconds'],'error':x.get('error')} for x in excluded],'sourceEngineDifferences':engine_differences,'sameSharedPins':True,'families':families,'blocks':[str(a.before),str(a.resume)],'allExcludedBeforeAndAfterDataRemainAvailable':True},indent=2)+'\n')
for name in ['common-pins.json','historical-input-comparison.json']:
 if (a.before/name).exists():shutil.copyfile(a.before/name,a.output/name)
print('Primary campaign assembled:',len(merged),'observations from two declared blocks; raw evidence retained')
