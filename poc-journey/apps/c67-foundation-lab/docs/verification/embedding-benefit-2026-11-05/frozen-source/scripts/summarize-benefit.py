#!/usr/bin/env python3
"""Paired authored-intent analysis. Repeats are consistency checks, not extra samples."""
import argparse
import collections
import json
import random
import statistics
from pathlib import Path

parser=argparse.ArgumentParser()
parser.add_argument('evidence',type=Path)
args=parser.parse_args()
series=[json.loads((args.evidence/f'masked-{i}'/'series.json').read_text()) for i in range(1,4)]
first=series[0]
ranking=[r for r in first if r['input']['family']!='safety']
methods=['category','lexical','e5','combined']
def metric(run,method):
 return next(row['metrics']['ndcgAt3'] for row in run['rankings'] if row['id']==method)
def summarize(runs):
 return {m:dict(meanNDCGAt3=statistics.mean(metric(r,m) for r in runs),
  meanPrecisionAt3=statistics.mean(next(row['metrics']['precisionAt3'] for row in r['rankings'] if row['id']==m) for r in runs),
  meanTopOneRelevance=statistics.mean(next(row['metrics']['topOneRelevance'] for row in r['rankings'] if row['id']==m) for r in runs)) for m in methods}
def paired(method,baseline):
 groups=collections.defaultdict(list)
 for run in ranking:groups[run['input']['group']].append(metric(run,method)-metric(run,baseline))
 values=[statistics.mean(v) for v in groups.values()]
 rng=random.Random(670511)
 draws=sorted(statistics.mean(rng.choices(values,k=len(values))) for _ in range(5000))
 differences=[metric(r,method)-metric(r,baseline) for r in ranking]
 return dict(meanDelta=statistics.mean(differences),clusterBootstrap95=[draws[124],draws[4874]],
  groups=len(groups),wins=sum(d>1e-10 for d in differences),ties=sum(abs(d)<=1e-10 for d in differences),losses=sum(d< -1e-10 for d in differences),
  lossesByCase=[r['input']['id'] for r,d in zip(ranking,differences) if d< -1e-10])
pairedResults={m:{base:paired(m,base) for base in ['category','lexical']} for m in ['e5','combined']}
consistency=[]
for idx,repeat in enumerate(series[1:],start=2):
 by_id={r['input']['id']:r for r in repeat}
 changed=[]
 for r in first:
  other=by_id[r['input']['id']]
  for method in [rank['id'] for rank in r['rankings']]:
   a=next(rank for rank in r['rankings'] if rank['id']==method)
   b=next(rank for rank in other['rankings'] if rank['id']==method)
   if [row['id'] for row in a['rows']] != [row['id'] for row in b['rows']]:changed.append(r['input']['id']+':'+method)
 consistency.append(dict(repeat=idx,changedRankings=changed,unexpectedStates=sum(r['status']!=r['input']['expectedStatus'] or not r['gatePassed'] for r in repeat)))
unmasked=json.loads((args.evidence/'unmasked-1'/'series.json').read_text())
unmasked=[r for r in unmasked if r['input']['family']!='safety']
all_safety=all(r['gatePassed'] and r['status']==r['input']['expectedStatus'] for s in series for r in s)
qualifying=[m for m in ['e5','combined'] if pairedResults[m]['lexical']['meanDelta']>=.05 and pairedResults[m]['lexical']['clusterBootstrap95'][0]>0 and all_safety]
summary=dict(protocol='benefit-v1',rankingCases=len(ranking),intentGroups=len(set(r['input']['group'] for r in ranking)),
 safetyCases=sum(r['input']['family']=='safety' for r in first),gatesPassed=sum(r['gatePassed'] for r in first),
 methods=summarize(ranking),families={f:summarize([r for r in ranking if r['input']['family']==f]) for f in ['literal','paraphrase']},
 paired=pairedResults,consistency=consistency,unmasked=summarize(unmasked),
 convincingBoundedIncrement=qualifying,
 limitations=['Authored prospective cases, not independent human judgments or a blind holdout.','Queries within an intent and repeat processes are correlated.','Bootstrap is descriptive for 12 authored intent clusters.','Unknown facts, operational availability, user fit and input burden are not established.'],
 timings=[dict(repeat=i+1,totalSeconds=sum(r['totalSeconds'] for r in s),firstCaseSeconds=s[0]['totalSeconds'],
  medianCaseSeconds=statistics.median(r['totalSeconds'] for r in s),documentEncodeCalls=sum(r['documentEncodes'] for r in s),queryEncodeCalls=sum(r['queryEncodes'] for r in s)) for i,s in enumerate(series)])
(args.evidence/'metrics.json').write_text(json.dumps(summary,indent=2)+'\n')
lines=['# Embedding benefit metrics','',f"{len(ranking)} ranking cases, {summary['intentGroups']} authored intents; 6 safety cases. Repeats are not extra samples.",'','| Method | NDCG@3 | Supported P@3 | Mean top-one grade (0-2) |','| --- | --- | --- | --- |']
for m,value in summary['methods'].items():lines.append(f"| {m} | {value['meanNDCGAt3']:.4f} | {value['meanPrecisionAt3']:.4f} | {value['meanTopOneRelevance']:.4f} |")
lines+=['','## Paired differences','']
for m,comparisons in pairedResults.items():
 for base,value in comparisons.items():
  lines.append(f"- {m} minus {base}: {value['meanDelta']:+.4f}; cluster interval {value['clusterBootstrap95']}; W/T/L {value['wins']}/{value['ties']}/{value['losses']}.")
lines+=['',f"Methods meeting the predeclared bounded-signal criterion: {qualifying or 'none'}.",'','Authored source relevance is not user satisfaction or production accuracy.']
(args.evidence/'METRICS.md').write_text('\n'.join(lines)+'\n')
print(json.dumps(summary,indent=2))
