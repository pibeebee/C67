#!/usr/bin/env python3
"""Post-primary lexical sensitivity; independent score/metric reproduction, no model retuning."""
import argparse
import collections
import hashlib
import itertools
import json
import math
import re
import statistics
import unicodedata
from pathlib import Path

parser=argparse.ArgumentParser();parser.add_argument('evidence',type=Path);args=parser.parse_args()
runs=json.loads((args.evidence/'masked-1/series.json').read_text());runs=[r for r in runs if r['input']['family']!='safety']
stop=set('a an and are as at be been but by can could do for from had has have how i in into is it its me my of on or our should show some that the their them there these they this to us want was we were what where which who will with would you your'.split())
# Keep the Swift list byte-for-byte in meaning, including "while" and "was".
stop.update(['while'])
english={'coffee':'drinking coffee allowed','reading':'reading books on site','quietPolicy':'a designated silent reading area','outdoor':'outdoor area','nature':'nature and park','art':'visual art','culture':'culture and learning','wifi':'Wi-Fi','smokingArea':'smoking area'}
def tokens(s):
 s=''.join(c for c in unicodedata.normalize('NFD',s.lower()) if unicodedata.category(c)!='Mn')
 return [t for t in re.findall(r'[^\W_]+',s) if t not in stop]
def bm25(query,documents):
 terms=set(tokens(query));docs=[tokens(d) for d in documents];avg=statistics.mean(map(len,docs))
 output=[]
 for doc in docs:
  value=0
  for t in terms:
   tf=doc.count(t)
   if not tf:continue
   df=sum(t in d for d in docs);idf=math.log(1+(len(docs)-df+.5)/(df+.5))
   value+=idf*tf*2.2/(tf+1.2*(1-.75+.75*len(doc)/avg))
  output.append(value)
 return output
def ndcg(rows,qrels):
 order=sorted(rows,key=lambda r:(-r['primary'],-r['secondary'],r['id']))
 ideal=sum((2**g['grade']-1)/math.log2(i+2) for i,g in enumerate(sorted(qrels.values(),key=lambda g:-g['grade'])[:3]))
 value=0;position=0
 for _,group in itertools.groupby(order,key=lambda r:(r['primary'],r['secondary'])):
  group=list(group);gain=statistics.mean(2**qrels.get(r['id'],{'grade':0})['grade']-1 for r in group)
  for i in range(position,min(position+len(group),3)):value+=gain/math.log2(i+2)
  position+=len(group)
  if position>=3:break
 return value/ideal if ideal else 0
summary={};percase=[];maxScoreError=0;maxMetricError=0
for run in runs:
 p=run['input']['profile'];candidates={c['id']:c for c in run['catalog']['candidates']};docs={d['id']:d['text'] for d in run['documents']}
 cat=next(r for r in run['rankings'] if r['id']=='category')['rows'];ids=[r['id'] for r in cat]
 passages=[docs[id]+' '+' '.join(english[c['feature']]+': '+c['value']+'.' for c in candidates[id]['claims']) for id in ids]
 desired=sorted(set(p['must'])|set(p['prefer']))
 query=('General Jakarta activities' if not desired else '; '.join(english[f] for f in desired))+('. Additional direction: '+p['direction'] if p['direction'] else '')
 reproduced=bm25(query,passages)
 actual={r['id']:r['secondary'] for r in next(r for r in run['rankings'] if r['id']=='lexical')['rows']}
 maxScoreError=max(maxScoreError,max(abs(score-actual[id]) for id,score in zip(ids,reproduced)))
 result={'case':run['input']['id'],'family':run['input']['family']}
 for name,q,ds in [('original-reproduction',query,passages),('direction-only',p['direction'],passages),('direction-description-only',p['direction'],[docs[id] for id in ids])]:
  scores=bm25(q,ds);rows=[dict(id=row['id'],primary=row['primary'],secondary=score) for row,score in zip(cat,scores)]
  result[name]=ndcg(rows,run['input']['judgments'])
 for ranking in run['rankings']:
  maxMetricError=max(maxMetricError,abs(ndcg(ranking['rows'],run['input']['judgments'])-ranking['metrics']['ndcgAt3']))
 result['e5']=next(r['metrics']['ndcgAt3'] for r in run['rankings'] if r['id']=='e5')
 percase.append(result)
assert maxScoreError<1e-10,(maxScoreError,'Independent BM25 does not reproduce Swift')
assert maxMetricError<1e-10,(maxMetricError,'Independent tie NDCG does not reproduce Swift')
for method in ['original-reproduction','direction-only','direction-description-only']:
 deltas=[r['e5']-r[method] for r in percase]
 summary[method]=dict(meanNDCGAt3=statistics.mean(r[method] for r in percase),e5MeanDelta=statistics.mean(deltas),wins=sum(d>1e-10 for d in deltas),ties=sum(abs(d)<=1e-10 for d in deltas),losses=sum(d< -1e-10 for d in deltas))
result=dict(phase='post-primary diagnostic on the same cases; not independent confirmation',independentBM25MaxError=maxScoreError,independentMetricMaxError=maxMetricError,variants=summary,cases=percase)
(args.evidence/'lexical-sensitivity.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({k:v for k,v in result.items() if k!='cases'},indent=2))
