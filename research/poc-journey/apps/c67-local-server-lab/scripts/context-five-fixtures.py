#!/usr/bin/env python3
"""Extend the independently generated synthetic model to five stops; no provider calls."""
import argparse,copy,importlib.util,json,random,tempfile
from pathlib import Path
spec=importlib.util.spec_from_file_location('independent_context',Path(__file__).with_name('context-pilot-fixtures.py'))
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
def generate(directory,seed):
 with tempfile.TemporaryDirectory(prefix='c67-five-fixtures-') as temp:
  m.generate(Path(temp),seed);source=json.loads((Path(temp)/'fixtures.json').read_text())
 cases=[]
 for index,c in enumerate(source['cases']):
  rep=int(c['id'].rsplit('-',1)[1])
  if rep>1:continue
  c=copy.deepcopy(c);rng=random.Random(seed*100+index)
  c['id']='five-'+c['id'];c['nodeIDs']=['origin','museum','gallery','mandiri','history','park']
  c['matrix']=[[0 if a==b else rng.choice([240,360,480,600,720,900,1200]) for b in range(6)] for a in range(6)]
  starts=540+rep*15;deadline=810 if c['family']=='tight' else 1140
  existing={s['request']['placeID']:s for s in c['input']['stops']};existing['mandiri']=copy.deepcopy(existing['museum']);existing['history']=copy.deepcopy(existing['museum'])
  stops=[];windows={}
  for key in c['nodeIDs'][1:]:
   stop=existing[key];r=stop['request'];r['placeID']=key;r['availableStart']=starts;r['availableEnd']=deadline;r['durationMinutes']=90 if key=='museum' else 60
   if key in ['mandiri','history']:r.pop('preferredTime',None)
   bounds=[[360,1200]] if key=='park' else [[540,1080]]
   if key=='gallery' and c['family']=='split_hours':bounds=[[480,720],[780,930]]
   windows[key]=bounds
   stop['snapshot']['place']['id']=key;stop['snapshot']['place']['displayName']['text']='SYNTHETIC '+key
   stop['snapshot']['place']['regularOpeningHours']['periods']=[{'open':{'day':d,'hour':a//60,'minute':a%60},'close':{'day':d,'hour':b//60,'minute':b%60}} for d in range(7) for a,b in bounds]
   stops.append(stop)
  c['oracleWindows']=windows;c['input']['stops']=stops;c['input']['departure']=m.BASE+starts*60;c['input']['deadline']=m.BASE+deadline*60
  cases.append(c)
 directory.mkdir(parents=True,exist_ok=True);m.dump(directory/'fixtures.json',{'seed':seed,'scope':'SYNTHETIC five-stop independent controlled reference; not representative Jakarta','cases':cases})
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('directory',type=Path);p.add_argument('--seed',type=int,default=671109);a=p.parse_args();generate(a.directory,a.seed)
