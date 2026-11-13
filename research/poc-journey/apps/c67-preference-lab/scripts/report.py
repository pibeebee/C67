#!/usr/bin/env python3
import collections, hashlib, json, statistics
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]; ART=ROOT/'artifacts'
rows=json.loads((ART/'live.json').read_text()); replay=json.loads((ART/'replayed.json').read_text())
cases=json.loads((ROOT/'Sources/PreferenceCore/Resources/cases.json').read_text())
manifest=json.loads((ROOT/'Sources/PreferenceCore/Resources/manifest.json').read_text())
for name,digest in manifest['files'].items():
 assert hashlib.sha256((ROOT/'Sources/PreferenceCore/Resources'/name).read_bytes()).hexdigest()==digest
assert len(cases)==18 and len(rows)==114
for case in cases:
 for arm in ['A-broad','A-broad-e5','B-rules','B-rules-e5','B-two-rounds','C-adaptive']:
  assert sum(x['caseID']==case['id'] and x['arm']==arm for x in rows)==1
for row in rows:
 assert len(row['topIDs'])==len(set(row['topIDs']))
 item=next(c for c in cases if c['id']==row['caseID'])
 assert set(row['topIDs']) <= {x['id'] for x in item['candidates']}
 expected=set(item['preferredIDs']); top=row['topIDs']
 assert row['top1']==bool(top and top[0] in expected)
 assert abs(row['precision3']-len(expected.intersection(top))/3)<1e-9
for old in rows:
 if old['arm']=='A-current-llm-contract':continue
 arm='C-replayed' if old['arm']=='C-adaptive' else old['arm']
 new=next(x for x in replay if x['caseID']==old['caseID'] and x['arm']==arm)
 assert all(old[k]==new[k] for k in ('topIDs','top1','precision3','intentCaptured','answered'))
summary={}
for arm in sorted({r['arm'] for r in rows}):
 group=[x for x in rows if x['arm']==arm]
 summary[arm]={'n':len(group),'top1Correct':sum(x['top1'] for x in group),
  'completeIntent':sum(x['intentCaptured'] for x in group),
  'precisionAt3':statistics.mean(x['precision3'] for x in group),
  'meanAnswers':statistics.mean(x['answered'] for x in group),
  'medianReportedSeconds':statistics.median(x['seconds'] for x in group),
  'modes':dict(collections.Counter(x['mode'] for x in group))}
control=json.loads((ART/'current-contract-17s.json').read_text())
summary['corrected17sControl']={'n':len(control),'returnedValid':sum(x['mode']=='llm' for x in control),
 'medianClientSeconds':statistics.median(x['clientSeconds'] for x in control)}
llm=[r for r in rows if r['arm']=='C-adaptive' and r['mode']=='llm']
summary['advisorLLMOnly']={'n':len(llm),'top1Correct':sum(r['top1'] for r in llm),
 'medianSeconds':statistics.median(r['seconds'] for r in llm),'maxSeconds':max(r['seconds'] for r in llm)}
summary['audit']={'fixtureHashesValid':True,'metricsRecomputed':True,'liveOutcomesReplayed':True,
 'distinctCases':len(cases),'mainObservations':len(rows),'independentParticipants':0}
(ART/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
sources={}
for directory in ['Sources','scripts','App/Sources','App/UITests']:
 for p in sorted((ROOT/directory).rglob('*')):
  if p.is_file() and '__pycache__' not in str(p) and p.suffix in ('.swift','.py','.json'):
   sources[str(p.relative_to(ROOT))]=hashlib.sha256(p.read_bytes()).hexdigest()
old=ROOT.parent/'c67-local-server-lab/Sources/RecommendationEngine'
for name in ['OpenRouterClient.swift','CandidatePolicy.swift']:
 sources['reference-current-lab/'+name]=hashlib.sha256((old/name).read_bytes()).hexdigest()
(ART/'source-hashes.json').write_text(json.dumps(sources,indent=2)+'\n')
print(json.dumps(summary,indent=2))
