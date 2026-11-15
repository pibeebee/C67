#!/usr/bin/env python3
import argparse,copy,json,time,urllib.error,urllib.request,uuid
from pathlib import Path
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--config',type=Path,default=root/'.local/client-config.json');p.add_argument('--matrix',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
c=json.loads(a.config.read_text());checks=[]
def call(path,method='GET',body=None,auth=True,raw=None):
 data=raw if raw is not None else None if body is None else json.dumps(body).encode()
 headers={'Content-Type':'application/json'}
 if auth:headers['Authorization']='Bearer '+c['token']
 req=urllib.request.Request(c['baseURL']+'/'+path,method=method,data=data,headers=headers)
 try:
  with urllib.request.urlopen(req,timeout=30) as r:return r.status,json.loads(r.read())
 except urllib.error.HTTPError as e:return e.code,json.loads(e.read())
def expect(name,result,status):
 checks.append({'name':name,'status':result[0],'expected':status,'passed':result[0]==status})
 if result[0]!=status:raise AssertionError((name,result))
expect('liveness',call('health',auth=False),200)
expect('unauthorized',call('v1/lab/capabilities',auth=False),401)
_,caps=call('v1/lab/capabilities');assert caps['providerMode']=='replay'
expect('malformed',call('v1/lab/jobs','POST',raw=b'{'),400)
expect('payload_limit',call('v1/lab/jobs','POST',raw=b'x'*70000),413)
request=json.loads(a.matrix.read_text())[0]['request']
input={'schemaVersion':1,'clientID':str(uuid.uuid4()),'operationID':'one','runID':'http-contract','variant':'B','snapshotHash':caps['snapshotHash'],'request':request,'baseRevision':0}
result=call('v1/lab/jobs','POST',input);expect('create',result,202);job=result[1]
result=call('v1/lab/jobs','POST',input);expect('duplicate',result,202);assert result[1]['id']==job['id']
changed=copy.deepcopy(input);changed['request']['defaultDuration']=90
expect('idempotency_conflict',call('v1/lab/jobs','POST',changed),409)
for _ in range(2400):
 _,state=call('v1/lab/jobs/'+job['id'])
 if state['state'] in ['completed','failed','cancelled','timed_out']:break
 time.sleep(.1)
assert state['state']=='completed',state
result=call('v1/lab/jobs/'+job['id']+'/result');expect('complete_result',result,200)
assert result[1]['outcome']=='ready'
plan=result[1]['plan']
# Hash normalization matches the published contract (set ordering is irrelevant).
import hashlib
def normalize(v,k=''):
 if isinstance(v,dict):return {key:normalize(value,key) for key,value in v.items()}
 if isinstance(v,list):return sorted(v) if k in ['must','prefer','avoid','excludedIDs'] else [normalize(x) for x in v]
 return v
# Swift canonical JSON may serialize integral doubles without .0. Use the hash recorded by SQLite
# via an invalid-hash check here; successful/idempotent apply is exercised by the native CLI and Swift tests.
expect('apply_wrong_hash',call('v1/lab/proposals/'+plan['id']+'/apply','POST',{'clientID':input['clientID'],'baseRevision':0,'requestHash':'wrong'}),409)
other=copy.deepcopy(input);other['clientID']=str(uuid.uuid4());other['operationID']='cancel'
_,job=call('v1/lab/jobs','POST',other)
result=call('v1/lab/jobs/'+job['id']+'/cancel','POST');expect('cancel',result,200)
time.sleep(.2);_,state=call('v1/lab/jobs/'+job['id']);assert state['state']=='cancelled' and 'result' not in state
expect('cancelled_no_result',call('v1/lab/jobs/'+job['id']+'/result'),409)
expect('missing_job',call('v1/lab/jobs/'+str(uuid.uuid4())),404)
a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps({'checks':checks,'passed':all(x['passed'] for x in checks)},indent=2)+'\n')
print('HTTP contract:',len(checks),'checks passed')
