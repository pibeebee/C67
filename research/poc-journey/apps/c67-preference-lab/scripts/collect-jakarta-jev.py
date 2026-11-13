#!/usr/bin/env python3
"""Bounded Jakarta-wide Google IDs + Jev eligibility and labels experiment."""
import json, os, sys, time, hashlib, importlib.util, threading
from pathlib import Path
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from server import ROOT, credentials, curl_json

def load_module(name, filename):
 s=importlib.util.spec_from_file_location(name,ROOT/'scripts'/filename); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); return m
scope=load_module('scope','benchmark-destination-scope.py'); base=scope.baseline; jev=scope.jev
os.umask(0o077)
D=ROOT/'.local/jakarta-wide-jev-2026-11-10'; D.mkdir(parents=True,exist_ok=True)
for p in ['search','google','scope','labels']: (D/p).mkdir(exist_ok=True)
os.umask(0o077)
# Rectangles are sampling windows, not administrative boundaries.
AREAS={
 'Jakarta Pusat':(106.79,-6.205,106.87,-6.155),
 'Jakarta Barat':(106.69,-6.22,106.80,-6.13),
 'Jakarta Utara':(106.75,-6.16,106.93,-6.095),
 'Jakarta Timur':(106.85,-6.35,106.97,-6.17),
 'Jakarta Selatan':(106.76,-6.34,106.86,-6.20),
 'Kepulauan Seribu':(106.48,-5.88,106.65,-5.55),
}
QUERIES=[('museum','museum'),('taman','park'),('galeri seni','art_gallery'),('perpustakaan','library'),('kolam renang','swimming_pool'),('bioskop','movie_theater'),('toko buku','book_store'),('pasar','market'),('kafe','cafe'),('restoran','restaurant'),('tempat wisata','tourist_attraction'),('toko roti','bakery'),('pusat perbelanjaan','shopping_mall'),('taman bermain','playground')]
TARGET=500; PER_REGION=84; SEARCH_CAP=110; DETAIL_CAP=500
GEOM=ROOT/'.local/DerivedData/Build/Products/Debug-iphonesimulator/TripIntelligence_TripIntelligence.bundle/jakarta.geojson'
polys=json.loads(GEOM.read_text())['features'][0]['geometry']['coordinates']
def ring_contains(p,ring):
 x,y=p; inside=False; j=len(ring)-1
 for i in range(len(ring)):
  xi,yi=ring[i][:2]; xj,yj=ring[j][:2]
  if ((yi>y)!=(yj>y)) and x < (xj-xi)*(y-yi)/(yj-yi)+xi: inside=not inside
  j=i
 return inside
def in_jakarta(loc,address):
 if not loc: return False
 pt=(loc['longitude'],loc['latitude'])
 if any(ring_contains(pt,p[0]) and not any(ring_contains(pt,h) for h in p[1:]) for p in polys): return True
 # Existing ADM1 shape omits Kepulauan Seribu. Recognize only an explicit address,
 # inside the island sampling rectangle; this is weaker than an island polygon.
 a=address.lower(); return 'kepulauan seribu' in a and 106.48<=pt[0]<=106.65 and -5.88<=pt[1]<=-5.55

def main():
 keys=credentials(); google=keys['GOOGLE_PLACES_API_KEY']; okey=keys['OPENROUTER_API_KEY']
 old=json.loads((ROOT/'.local/google-places-jakarta-selatan-2026-11-10.json').read_text()); oldids=set(old['placeIDs'])
 oldcat=json.loads((ROOT/'.local/destination-scope-500-2026-11-10/catalogue.json').read_text())
 defs=jev.taxonomy()[1]; parents=jev.taxonomy()[2]; tax=json.loads((ROOT/'catalog/place-labels.json').read_text()); types={a:b for g in tax['types'].values() for a,b in g.items()}
 fields=base.FIELDS+['location','formattedAddress']; requests=base.Requests(D); campaign=scope.Campaign(D,okey)
 # Separate usage ledgers: the old helpers use different formats.
 class Google:
  def __init__(self): self.lock=threading.Lock(); self.last=0; self.stopped=False
  def send(self,url,body,headers,kind,method='POST'):
   with self.lock:
    if self.stopped: raise RuntimeError('google_stopped_after_429')
    pause=max(0,self.last+.17-time.monotonic())
    if pause: time.sleep(pause)
    self.last=time.monotonic()
    p=D/'google-usage.json'; d=base.load(p) if p.exists() else {'search':0,'details':0}; cap=SEARCH_CAP if kind=='search' else DETAIL_CAP
    if d[kind]>=cap: raise RuntimeError(kind+'_cap')
    d[kind]+=1; jev.write_json(p,d)
   try: return curl_json(url,body,headers,25,method)
   except RuntimeError as e:
    if str(e)=='provider_http_429': self.stopped=True
    raise
 g=Google(); selected={}; queries=[]
 for qidx,(q,typ) in enumerate(QUERIES):
  for area,(w,s,e,n) in AREAS.items():
   area_count=sum(area in x['areas'] for x in selected.values())
   if area_count>=PER_REGION: continue
   index=f'{qidx:02d}-{list(AREAS).index(area)}'; path=D/'search'/(index+'.json')
   if path.exists(): row=base.load(path)
   else:
    body={'textQuery':q,'includedType':typ,'languageCode':'id','pageSize':20,'locationRestriction':{'rectangle':{'low':{'latitude':s,'longitude':w},'high':{'latitude':n,'longitude':e}}}}
    try:
     result=g.send('https://places.googleapis.com/v1/places:searchText',body,{'X-Goog-Api-Key':google,'X-Goog-FieldMask':'places.id,nextPageToken'},'search')
     row={'area':area,'query':q,'type':typ,'placeIDs':[x['id'] for x in result.get('places',[])], 'hasNextPage':bool(result.get('nextPageToken'))}
     jev.write_json(path,row)
    except RuntimeError as ex:
     print(json.dumps({'searchStopped':str(ex),'area':area,'query':q}),flush=True)
     if str(ex) in ('provider_http_429','search_cap'): break
     continue
   queries.append(row)
   for pid in row['placeIDs']:
    if pid in oldids: continue
    if pid not in selected: selected[pid]={'id':pid,'areas':[],'queries':[]}
    if area not in selected[pid]['areas']: selected[pid]['areas'].append(area)
    if q not in selected[pid]['queries']: selected[pid]['queries'].append(q)
    if len(selected)>=TARGET or sum(area in x['areas'] for x in selected.values())>=PER_REGION: break
   if len(selected)>=TARGET: break
  if len(selected)>=TARGET: break
 jev.write_json(D/'discovery.json',{'target':TARGET,'queries':queries,'candidates':list(selected.values()),'sampleWindowCounts':dict(Counter(a for x in selected.values() for a in x['areas']))})
 print(json.dumps({'discovered':len(selected),'windowCounts':dict(Counter(a for x in selected.values() for a in x['areas'])),'searchCalls':len(queries)}),flush=True)
 # Pacing details explicitly, and keep all out-of-bound results for diagnosis.
 rows=[]; failures={}; gate=threading.Semaphore(4)
 def detail(item):
  pid=item['id']; p=D/'google'/(pid+'.json')
  if p.exists(): return base.load(p)
  time.sleep(.21)
  place=g.send('https://places.googleapis.com/v1/places/'+pid+'?languageCode=id',{}, {'X-Goog-Api-Key':google,'X-Goog-FieldMask':','.join(fields)},'details','GET')
  if place.get('id')!=pid or not place.get('types'): raise ValueError('unexpected_place')
  result={'id':pid,'fetchedAtWIB':base.now(),'fieldMask':fields,'place':place,'withinJakarta':in_jakarta(place.get('location'),place.get('formattedAddress',''))}
  jev.write_json(p,result); return result
 def process(item):
  with gate:
   d=detail(item); place=d['place']; row={**item,'name':place.get('displayName',{}).get('text'),'withinJakarta':d['withinJakarta'],'scope':None,'labels':[]}
   if not d['withinJakarta']: row['outcome']='outside_or_unverified_boundary'; return row
   desc=base.description(place,True); decision=campaign.decide_scope(item['id'],place,desc,types); row['scope']=decision
   if decision['status']=='include':
    labels=campaign.label(item['id'],desc,defs,parents); row['labelling']=labels; row['labels']=labels['labels']; row['outcome']='labelled' if row['labels'] else 'included_no_labels'
   else: row['outcome']='not_processed_'+decision['status']
   return row
 with ThreadPoolExecutor(max_workers=4) as pool:
  fs={pool.submit(process,x):x['id'] for x in selected.values()}
  for f in as_completed(fs):
   try: rows.append(f.result())
   except Exception as e: failures[fs[f]]=str(e)
   if (len(rows)+len(failures))%50==0: print(json.dumps({'completed':len(rows),'failed':len(failures),'outcomes':dict(Counter(x['outcome'] for x in rows))}),flush=True)
 rows.sort(key=lambda x:list(selected).index(x['id']))
 jev.write_json(D/'catalogue.json',{'generatedAtWIB':base.now(),'scopePolicy':scope.POLICY,'gateThreshold':scope.GATE_CUTOFF,'labelThreshold':jev.THRESHOLD,'areasAreSearchWindows':True,'places':rows})
 jev.write_json(D/'failures.json',failures)
 metas=[x['scope']['meta'] for x in rows if x['scope']]+[x['labelling']['meta'] for x in rows if 'labelling' in x]
 report={'requestedTarget':TARGET,'discoveredNewIDs':len(selected),'completed':len(rows),'failed':len(failures),'scopeCounts':dict(Counter(x['scope']['status'] for x in rows if x['scope'])),'outcomes':dict(Counter(x['outcome'] for x in rows)),'labelAssignments':sum(len(x['labels']) for x in rows),'distinctLabels':len({v for x in rows for v in x['labels']}),'searchWindowCounts':dict(Counter(a for x in rows for a in x['areas'])),'googleCalls':base.load(D/'google-usage.json'),'jevCalls':base.load(D/'usage.json') if metas else {},'jevCostUSD':sum(m.get('costUSD') or 0 for m in metas),'previous500RetainedCount':len(oldcat['places']),'boundaryCaveat':'Mainland uses supplied simplified ADM1 polygon; islands use address and sampling rectangle, not a polygon. Search windows are not city boundaries.','notCensus':True,'completedAtWIB':base.now()}
 jev.write_json(D/'summary.json',report); print(json.dumps(report,indent=2),flush=True)
if __name__=='__main__': main()
