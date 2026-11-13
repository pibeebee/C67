#!/usr/bin/env python3
"""Contract smoke via the real local server. CLI deliberately does not claim device E5."""
import argparse,json,time,urllib.request,urllib.error
from pathlib import Path
from datetime import datetime,timedelta
from zoneinfo import ZoneInfo

LAB=Path(__file__).resolve().parents[1]
def api(path,body=None):
    cfg=json.loads((LAB/'.local/dynamic-context-simulator/client-config.json').read_text())
    req=urllib.request.Request(cfg['baseURL']+'/v1/lab/'+path,
        data=json.dumps(body).encode() if body is not None else None,
        headers={'Authorization':'Bearer '+cfg['token'],'Content-Type':'application/json'})
    try:
        with urllib.request.urlopen(req,timeout=23) as response:return response.status,json.load(response)
    except urllib.error.HTTPError as e:
        value=json.load(e);return e.code,{'reason':value.get('reason','HTTP error')}
    except Exception as e:return 0,{'reason':type(e).__name__}
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--live',action='store_true');p.add_argument('--scenario',default='balanced');p.add_argument('--label',default='smoke');args=p.parse_args()
    tomorrow=(datetime.now(ZoneInfo('Asia/Jakarta'))+timedelta(days=2)).strftime('%Y-%m-%d')
    request={'profile':{'schemaVersion':1,'revision':1,'interests':['coffee','culture','outdoors'],'pace':'balanced','facetAffinity':{}},
       'context':{'area':'Gambir Jakarta','day':tomorrow,'departureMinute':540,'deadlineMinute':1140}}
    began=time.monotonic()
    status,prepared=api('recommendation/start',request) if args.live else api('recommendation/fixture',{'input':request,'scenario':args.scenario})
    result={'label':args.label,'mode':'live-no-device-E5' if args.live else 'synthetic-input-real-LLM-no-device-E5','input':request,'startHTTP':status}
    if status==200:
        scores=[{'id':c['id'],'semanticScore':None} for c in prepared['candidates']]
        status,value=api('recommendation/complete',{'id':prepared['id'],'profileRevision':prepared['profileRevision'],'scores':scores,
            'embeddingStatus':'not_run_cli_contract_probe','embeddingSeconds':0})
        result.update(completeHTTP=status,response=value,
          candidateFacts=[{'id':c['id'],'categories':c['categories'],'hoursState':c['hoursState'],'evidenceIDs':[e['id'] for e in c['evidence']]} for c in prepared['candidates']])
    else:result['response']=prepared
    result['clientSeconds']=time.monotonic()-began
    out=LAB/'artifacts/personal-recommendation-2026-11-08';out.mkdir(parents=True,exist_ok=True)
    (out/(args.label+'.json')).write_text(json.dumps(result,indent=2))
    print(json.dumps({'label':args.label,'startHTTP':result['startHTTP'],'completeHTTP':result.get('completeHTTP'),'seconds':result['clientSeconds'],
        'model':result['response'].get('metrics',{}).get('llmModel'),'cost':result['response'].get('metrics',{}).get('costUSD'),
        'reason':result['response'].get('reason'),'candidateCount':len(result['response'].get('places',[]))}))
