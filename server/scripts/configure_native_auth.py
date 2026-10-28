"""Apply the user-authorized native Auth settings to the verified external Compose project."""
from pathlib import Path
import argparse,datetime,hashlib,json,os,re,shutil,subprocess,time,urllib.request
ROOT=Path('/home/giovan/apps/supabase')
CALLBACK='c67://auth/callback'
FILES=[ROOT/'docker-compose.yml',ROOT/'docker-compose.cf-tunnel.yml']
EXPECTED_KEYS={'GOTRUE_PASSWORD_MIN_LENGTH':'8','GOTRUE_SECURITY_REFRESH_TOKEN_ROTATION_ENABLED':'true','GOTRUE_SECURITY_REFRESH_TOKEN_REUSE_INTERVAL':'10'}
def command(*args):return subprocess.check_output(args,stderr=subprocess.PIPE)
def container(name):return json.loads(command('docker','inspect',name))[0]
def snapshot():
 ids=command('docker','ps','--filter','label=com.docker.compose.project=supabase','--format','{{.Names}}').decode().splitlines()
 return {name:{'id':container(name)['Id'],'started':container(name)['State']['StartedAt']} for name in ids}
def config():
 args=['docker','compose']
 for path in FILES:args+=['-f',str(path)]
 args+=['config','--format','json']
 return json.loads(command(*args))
def compose_auth():
 args=['docker','compose']
 for path in FILES:args+=['-f',str(path)]
 command(*args,'up','-d','--no-deps','--pull','never','auth')
def write_atomic(path,value):
 temporary=path.with_name(path.name+'.c67-auth-tmp')
 with temporary.open('x') as f:f.write(value)
 temporary.chmod(0o600);temporary.replace(path)
def set_env(text,key,value):
 pattern=r'(?m)^'+re.escape(key)+r'=.*$'
 line=key+'='+value
 return re.sub(pattern,lambda _:line,text) if re.search(pattern,text) else text.rstrip()+'\n'+line+'\n'
def apply():
 current=container('supabase-auth');labels=current['Config'].get('Labels') or {}
 assert labels.get('com.docker.compose.project')=='supabase'
 assert labels.get('com.docker.compose.project.working_dir')==str(ROOT)
 assert set(labels['com.docker.compose.project.config_files'].split(','))==set(map(str,FILES))
 assert not any('/data/compose' in str(p) for p in FILES)
 before=snapshot();base=config()
 envtext=(ROOT/'.env').read_text()
 oldenv={}
 for line in envtext.splitlines():
  if '=' in line and not line.lstrip().startswith('#'):
   k,v=line.split('=',1);oldenv[k.strip()]=v.strip().strip('"').strip("'")
 redirects=[v.strip() for v in oldenv.get('ADDITIONAL_REDIRECT_URLS','').split(',') if v.strip()]
 for value in [CALLBACK,CALLBACK+'?**']:
  if value not in redirects:redirects.append(value)
 updated=set_env(set_env(envtext,'SITE_URL',CALLBACK),'ADDITIONAL_REDIRECT_URLS',','.join(redirects))
 text=FILES[0].read_text();marker='      GOTRUE_URI_ALLOW_LIST: ${ADDITIONAL_REDIRECT_URLS}'
 assert text.count(marker)==1
 additions=[]
 for key,value in EXPECTED_KEYS.items():
  assert not re.search(r'(?m)^\s+'+key+r':',text),'Auth setting already exists; inspect drift before applying'
  additions.append('      '+key+': "'+value+'"')
 updated_compose=text.replace(marker,marker+'\n'+'\n'.join(additions))
 now=datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H%M%SZ')
 backup=Path('/home/giovan/backups/c67')/('before-native-auth-'+now)
 backup.mkdir(mode=0o700)
 for path in [ROOT/'.env',*FILES]:
  shutil.copyfile(path,backup/path.name);(backup/path.name).chmod(0o600)
 (backup/'baseline.json').write_text(json.dumps(before,indent=2));(backup/'baseline.json').chmod(0o600)
 hashes={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in backup.iterdir() if p.is_file()}
 (backup/'checksums.json').write_text(json.dumps(hashes,indent=2));(backup/'checksums.json').chmod(0o600)
 try:
  write_atomic(ROOT/'.env',updated);write_atomic(FILES[0],updated_compose)
  after_config=config()
  for name,service in base['services'].items():
   if name!='auth':assert after_config['services'][name]==service,'Unrelated service config drift'
  old=base['services']['auth'];new=after_config['services']['auth']
  for key,value in old.items():
   if key!='environment':assert new[key]==value,'Auth image/mount/port drift'
  changed={k for k in set(old['environment'])|set(new['environment']) if old['environment'].get(k)!=new['environment'].get(k)}
  assert changed<=set(EXPECTED_KEYS)|{'GOTRUE_SITE_URL','GOTRUE_URI_ALLOW_LIST'}
  compose_auth()
  for _ in range(30):
   obj=container('supabase-auth')
   if obj['State']['Status']=='running' and obj['State'].get('Health',{}).get('Status')=='healthy':break
   time.sleep(1)
  else:raise RuntimeError('Auth did not become healthy')
  after=snapshot()
  for name,state in before.items():
   if name!='supabase-auth':assert after[name]==state,'Unrelated service lifecycle changed'
  runtime=dict(v.split('=',1) for v in obj['Config']['Env'] if '=' in v)
  assert runtime['GOTRUE_SITE_URL']==CALLBACK
  assert all(runtime.get(k)==v for k,v in EXPECTED_KEYS.items())
  assert runtime.get('GOTRUE_MAILER_AUTOCONFIRM')=='false'
  report={'applied':True,'backup':str(backup),'changed_keys':sorted(changed),'auth_healthy':True,'other_services_unchanged':len(before)-1,'confirmation_required':True}
  (backup/'result.json').write_text(json.dumps(report,indent=2));(backup/'result.json').chmod(0o600)
  print(json.dumps(report,indent=2))
 except Exception:
  shutil.copyfile(backup/'.env',ROOT/'.env');(ROOT/'.env').chmod(0o600)
  shutil.copyfile(backup/FILES[0].name,FILES[0]);FILES[0].chmod(0o600)
  compose_auth()
  print('FAIL: native Auth settings rolled back; backup retained')
  raise SystemExit(1)
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--approved-auth-completion',action='store_true');a=p.parse_args()
 assert a.approved_auth_completion,'Exact authorized Auth scope required'
 try:apply()
 except Exception as e:print('FAIL:',type(e).__name__,'sensitive details suppressed');raise SystemExit(1)
