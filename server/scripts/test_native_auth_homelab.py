"""Provision/clean an exact synthetic cohort for opt-in native Auth tests. No emails are sent."""
import argparse,base64,datetime,json,os,secrets,ssl,sys,time
from pathlib import Path
from urllib.request import Request,build_opener,HTTPSHandler,HTTPRedirectHandler
from urllib.error import HTTPError
from uuid import uuid4
ORIGIN='https://supabase.mrt.qzz.io'
class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self,*args,**kwargs):return None
class SharedAuth:
    def __init__(self,path):
        assert path.stat().st_mode&0o777==0o600,'Private server env must be mode 600'
        values={}
        for line in path.read_text().splitlines():
            if '=' in line and not line.lstrip().startswith('#'):
                k,v=line.split('=',1);values[k.strip()]=v.strip().strip('"').strip("'")
        assert values['SUPABASE_URL'].rstrip('/')==ORIGIN
        self.key=values['SUPABASE_SERVICE_ROLE_KEY'];self.client=values['SUPABASE_ANON_KEY']
        for key,role in [(self.key,'service_role'),(self.client,'anon')]:
            part=key.split('.')[1];claims=json.loads(base64.urlsafe_b64decode(part+'='*(-len(part)%4)))
            assert claims['role']==role and claims['exp']>time.time()
        self.opener=build_opener(NoRedirect(),HTTPSHandler(context=ssl.create_default_context(cafile='/etc/ssl/cert.pem')))
    def request(self,method,path,body=None):
        assert path.startswith('/') and not path.startswith('//')
        headers={'apikey':self.key,'Authorization':'Bearer '+self.key,'Content-Type':'application/json','User-Agent':'C67-Native-Auth-Verification/1.0'}
        r=Request(ORIGIN+path,headers=headers,method=method,data=None if body is None else json.dumps(body).encode())
        try:
            with self.opener.open(r,timeout=20) as f:status,data=f.status,f.read()
        except HTTPError as e:status,data=e.code,e.read()
        assert 200<=status<300,'Shared Auth request failed (HTTP '+str(status)+')'
        return json.loads(data) if data else None
    def users(self):
        users=self.request('GET','/auth/v1/admin/users?page=1&per_page=100')['users']
        assert len(users)<100,'Review account pagination before testing'
        return {u['id']:u for u in users}
def write(path,value):
    tmp=path.with_name(path.name+'.tmp')
    with tmp.open('x') as f:json.dump(value,f,indent=2)
    tmp.chmod(0o600);tmp.replace(path)
def prepare(api,root):
    assert not root.exists(),'Existing cohort must be inspected/cleaned first'
    root.mkdir(mode=0o700)
    original=api.users()
    cohort={'origin':ORIGIN,'clientKey':api.client,'accounts':[]}
    state={'baseline_ids':list(original),'created':[],'prefix':'c67-native-auth-check-'+uuid4().hex}
    write(root/'state.json',state)
    for label in ['a','b']:
        email=state['prefix']+'-'+label+'@example.invalid';password=secrets.token_urlsafe(32)
        user=api.request('POST','/auth/v1/admin/users',{'email':email,'password':password,'email_confirm':True})
        assert user['id'] not in original
        state['created'].append({'id':user['id'],'email':email});write(root/'state.json',state)
        cohort['accounts'].append({'id':user['id'],'email':email,'password':password})
    write(root/'cohort.json',cohort)
    print('PASS: two exact synthetic confirmed accounts prepared without email; existing accounts preserved')
def cleanup(api,root):
    state=json.loads((root/'state.json').read_text())
    existing=api.users()
    for user in state['created']:
        current=existing.get(user['id'])
        if current is None:continue
        assert user['id'] not in state['baseline_ids'] and current['email']==user['email']
        assert current['email'].startswith(state['prefix'])
        api.request('DELETE','/auth/v1/admin/users/'+user['id'])
    final=api.users()
    assert set(state['baseline_ids'])<=set(final)
    assert not set(u['id'] for u in state['created'])&set(final)
    owned=','.join(u['id'] for u in state['created'])
    rows=api.request('GET','/rest/v1/trips?select=id&owner_id=in.('+owned+')')
    assert rows==[],'Synthetic owned trips remain after account deletion'
    # Credentials and identity journal are private, temporary and removed after exact cleanup succeeds.
    for name in ['cohort.json','state.json']:
        p=root/name
        if p.exists():p.unlink()
    root.rmdir()
    print('PASS: exact synthetic Auth accounts and cascade-owned trips removed; all baseline accounts remain')
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('action',choices=['prepare','cleanup']);p.add_argument('--env-file',type=Path,required=True)
    p.add_argument('--fixture-dir',type=Path,default=Path('/private/tmp/c67-native-auth-shared'))
    p.add_argument('--approved-auth-verification',action='store_true');a=p.parse_args()
    assert a.approved_auth_verification,'Explicit shared synthetic verification scope required'
    try:
        api=SharedAuth(a.env_file)
        prepare(api,a.fixture_dir) if a.action=='prepare' else cleanup(api,a.fixture_dir)
    except Exception as e:
        print('FAIL:',type(e).__name__,'sensitive details suppressed; inspect private state before retrying',file=sys.stderr)
        sys.exit(1)
