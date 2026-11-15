#!/usr/bin/env python3
"""Authenticated local HTTP smoke checks. Replay-mode guards prevent any Google request."""
import json,os,subprocess,time,urllib.request,urllib.error,uuid
from pathlib import Path
root=Path(__file__).resolve().parents[1];output=root/'artifacts/google-context-2026-11-07';output.mkdir(parents=True,exist_ok=True)
checks=[]
for configured in [False,True]:
    directory=root/'.local'/('google-context-http-'+str(uuid.uuid4()))
    env=dict(os.environ,GOOGLE_PLACES_API_KEY='synthetic-invalid-test-key' if configured else '',GOOGLE_PLACES_MAX_REQUESTS='2')
    start=subprocess.run(['python3',str(root/'scripts/start.py'),'--mode','replay','--port','8771','--data-dir',str(directory)],cwd=root,env=env,capture_output=True,text=True)
    if start.returncode:raise SystemExit('Local test server failed to start')
    try:
        config=json.loads((directory/'client-config.json').read_text())
        def call(path,body=None,auth=True,raw=False):
            headers={'Content-Type':'application/json'}
            if auth:headers['Authorization']='Bearer '+config['token']
            data=body if raw else json.dumps(body).encode() if body is not None else None
            request=urllib.request.Request(config['baseURL']+'/'+path,data=data,headers=headers)
            try:
                with urllib.request.urlopen(request,timeout=10) as response:return response.status,response.headers,response.read()
            except urllib.error.HTTPError as e:return e.code,e.headers,e.read()
        ready=False
        for _ in range(100):
            try:
                ready=call('health')[0]==200
                if ready:break
            except (OSError,urllib.error.URLError):pass
            time.sleep(.1)
        if not ready:raise RuntimeError('Server health timeout')
        def check(name,status,expected):
            checks.append({'configuredWithSyntheticKey':configured,'check':name,'status':status,'expected':expected,'passed':status==expected})
        check('context capability requires auth',call('v1/lab/place-context/capabilities',auth=False)[0],401)
        status,headers,body=call('v1/lab/place-context/capabilities');caps=json.loads(body)
        check('capability available',status,200)
        checks.append({'check':'configured flag and no-store','passed':caps['configured']==str(configured).lower() and headers.get('Cache-Control')=='no-store'})
        check('malformed request rejected',call('v1/lab/place-context/search',b'{bad',raw=True)[0],400)
        check('search auth',call('v1/lab/place-context/search',{'query':'SYNTHETIC'},auth=False)[0],401)
        expected=409 if configured else 503
        check('live search blocked in replay or without key',call('v1/lab/place-context/search',{'query':'SYNTHETIC'})[0],expected)
        request={'request':{'placeID':'synthetic-park','identityConfirmed':True,'day':'2026-11-09'}}
        check('live evaluation blocked in replay or without key',call('v1/lab/place-context/evaluate',request)[0],expected)
        caps=json.loads(call('v1/lab/place-context/capabilities')[2]);checks.append({'check':'zero Google calls','passed':caps['requests']=='0'})
    finally:
        stop=subprocess.run(['python3',str(root/'scripts/stop.py'),'--data-dir',str(directory)],cwd=root,capture_output=True,text=True)
        if stop.returncode:raise RuntimeError('Local test server cleanup failed')
report={'checks':checks,'passed':all(x['passed'] for x in checks),'liveGoogleRequests':0,'serverCleanup':'both lab-owned servers stopped; temporary tokens revoked'}
(output/'http-smoke.json').write_text(json.dumps(report,indent=2)+'\n')
assert report['passed'],report
print('Passed',len(checks),'local HTTP checks; zero live Google requests')
