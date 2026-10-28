"""Disposable Auth/SMTP fixture. Uses only existing images and exact owned resources."""
import argparse,json,os,secrets,subprocess,time,shutil
from pathlib import Path
ROOT=Path('/home/giovan/apps/c67-auth-verification')
NAME='c67-auth-verification'
def run(*args,**kw):return subprocess.check_output(list(args),stderr=subprocess.PIPE,**kw)
def write(path,value):
 path.write_text(value);path.chmod(0o600)
def provision():
 assert not ROOT.exists(), 'Fixture already exists; inspect before retrying'
 run('docker','image','inspect','c67-media:e32e283')
 for port in [18081]:
  import socket
  with socket.socket() as s:s.bind(('127.0.0.1',port))
 images={n:json.loads(run('docker','inspect',n))[0]['Image'] for n in ['supabase-db','supabase-auth']}
 ROOT.mkdir(mode=0o700)
 password=secrets.token_urlsafe(32);jwt=secrets.token_urlsafe(48)
 write(ROOT/'db.env','POSTGRES_PASSWORD='+password+'\nPOSTGRES_DB=postgres\n')
 write(ROOT/'auth.env','\n'.join([
  'GOTRUE_API_HOST=0.0.0.0','GOTRUE_API_PORT=9999','API_EXTERNAL_URL=http://127.0.0.1:18081/auth/v1',
  'GOTRUE_DB_DRIVER=postgres','GOTRUE_DB_DATABASE_URL=postgres://supabase_auth_admin:'+password+'@'+NAME+'-db:5432/postgres?search_path=auth',
  'GOTRUE_SITE_URL=c67://auth/callback','GOTRUE_URI_ALLOW_LIST=c67://auth/callback,c67://auth/callback?**',
  'GOTRUE_JWT_SECRET='+jwt,'GOTRUE_JWT_EXP=3600','GOTRUE_JWT_AUD=authenticated','GOTRUE_JWT_DEFAULT_GROUP_NAME=authenticated',
  'GOTRUE_JWT_ADMIN_ROLES=service_role','GOTRUE_DISABLE_SIGNUP=false','GOTRUE_EXTERNAL_EMAIL_ENABLED=true',
  'GOTRUE_MAILER_AUTOCONFIRM=false','GOTRUE_SMTP_HOST='+NAME+'-mail','GOTRUE_SMTP_PORT=1025',
  'GOTRUE_SMTP_ADMIN_EMAIL=auth@example.test','GOTRUE_SMTP_SENDER_NAME=C67 Isolated Auth',
  'GOTRUE_SMTP_MAX_FREQUENCY=1s','GOTRUE_RATE_LIMIT_EMAIL_SENT=1000','GOTRUE_PASSWORD_MIN_LENGTH=8',
  'GOTRUE_MAILER_URLPATHS_CONFIRMATION=/auth/v1/verify','GOTRUE_MAILER_URLPATHS_RECOVERY=/auth/v1/verify',
  'GOTRUE_SECURITY_REFRESH_TOKEN_ROTATION_ENABLED=true','GOTRUE_SECURITY_REFRESH_TOKEN_REUSE_INTERVAL=10','LOG_LEVEL=error'])+'\n')
 js=r'''
const net=require('node:net'),http=require('node:http');
const messages=[];
net.createServer(socket=>{
 socket.setEncoding('utf8');socket.write('220 c67-isolated SMTP ready\r\n');let buffer='',body=[],recipient='',data=false;
 socket.on('data',chunk=>{buffer+=chunk;let pos;while((pos=buffer.indexOf('\r\n'))>=0){let line=buffer.slice(0,pos);buffer=buffer.slice(pos+2);
  if(data){if(line==='.') {messages.push({recipient,raw:body.join('\r\n')});if(messages.length>100)messages.shift();body=[];data=false;socket.write('250 accepted locally\r\n');}else body.push(line);continue;}
  if(/^EHLO|^HELO/i.test(line))socket.write('250-c67-isolated\r\n250 8BITMIME\r\n');
  else if(/^MAIL FROM/i.test(line))socket.write('250 sender accepted\r\n');
  else if(/^RCPT TO/i.test(line)){recipient=line.replace(/^RCPT TO:\s*/i,'').replace(/[<>]/g,'');socket.write('250 recipient accepted\r\n');}
  else if(/^DATA$/i.test(line)){data=true;socket.write('354 send message\r\n');}
  else if(/^QUIT$/i.test(line)){socket.end('221 bye\r\n');}
  else socket.write('250 ok\r\n');
 }});socket.on('error',()=>{});
}).listen(1025,'0.0.0.0');
http.createServer((req,res)=>{
 const url=new URL(req.url,'http://fixture');
 if(url.pathname==='/__test/health'){res.end(JSON.stringify({ready:true,messages:messages.length}));return;}
 if(url.pathname==='/__test/mail'){
  const email=url.searchParams.get('recipient');
  const found=messages.filter(m=>m.recipient.toLowerCase()===email?.toLowerCase());
  const links=found.flatMap(m=>{
   let raw=m.raw.replace(/=\r?\n/g,'').replace(/=([A-Fa-f0-9]{2})/g,(_,v)=>String.fromCharCode(parseInt(v,16)));
   return [...raw.matchAll(/href=["']([^"']+)["']/gi)].map(x=>x[1].replace(/&amp;/g,'&'));
  }).filter(v=>v.startsWith('http://127.0.0.1:18081/auth/v1/verify'));
  res.setHeader('Content-Type','application/json');res.end(JSON.stringify({count:found.length,links}));return;
 }
 if(!url.pathname.startsWith('/auth/v1/')){res.writeHead(404);res.end();return;}
 const upstream=http.request({hostname:'c67-auth-verification-auth',port:9999,method:req.method,
  path:req.url.slice('/auth/v1'.length),headers:{...req.headers,host:'127.0.0.1:18081'}},r=>{res.writeHead(r.statusCode,r.headers);r.pipe(res);});
 upstream.on('error',()=>{res.writeHead(503);res.end('{}');});req.pipe(upstream);
}).listen(8000,'0.0.0.0');
'''
 write(ROOT/'mail.js',js)
 run('docker','network','create','--internal','--label','c67.auth-fixture=true',NAME)
 run('docker','network','create','--label','c67.auth-fixture=true',NAME+'-access')
 common=['--detach','--label','c67.auth-fixture=true','--network',NAME,'--log-opt','max-size=2m','--log-opt','max-file=2','--security-opt','no-new-privileges:true']
 run('docker','run',*common,'--name',NAME+'-db','--env-file',str(ROOT/'db.env'),'--memory','512m',images['supabase-db'])
 for _ in range(60):
  p=subprocess.run(['docker','exec',NAME+'-db','pg_isready','-U','postgres'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
  if p.returncode==0:break
  time.sleep(1)
 else:raise RuntimeError('Fixture PostgreSQL did not start')
 run('docker','exec',NAME+'-db','psql','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-c','CREATE SCHEMA IF NOT EXISTS auth;')
 mail_common=common.copy();mail_common[mail_common.index(NAME)]=NAME+'-access'
 run('docker','run',*mail_common,'--name',NAME+'-mail','--read-only','--tmpfs','/tmp:rw,noexec,nosuid,size=16m',
  '--cap-drop','ALL','--memory','128m','--user','1000:1000','--mount','type=bind,src='+str(ROOT)+',dst=/fixture,readonly',
  '--publish','127.0.0.1:18081:8000','--entrypoint','node','c67-media:e32e283','/fixture/mail.js')
 run('docker','network','connect',NAME,NAME+'-mail')
 for _ in range(60):
  tcp=subprocess.run(['docker','exec',NAME+'-mail','node','-e',"const s=require('net').connect(5432,'c67-auth-verification-db',()=>{s.end();process.exit(0)});s.on('error',()=>process.exit(1))"],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
  if tcp.returncode==0:break
  time.sleep(1)
 else:raise RuntimeError('Fixture PostgreSQL network not ready')
 sql="ALTER ROLE supabase_auth_admin WITH PASSWORD '"+password+"';"
 run('docker','exec','-i',NAME+'-db','psql','-U','supabase_admin','-d','postgres','-v','ON_ERROR_STOP=1',input=sql.encode())
 run('docker','run',*common,'--name',NAME+'-auth','--env-file',str(ROOT/'auth.env'),'--memory','256m',images['supabase-auth'])
 write(ROOT/'state.json',json.dumps({'containers':[NAME+'-db',NAME+'-mail',NAME+'-auth'],'network':NAME,'port':18081,'images':images},indent=2))
 import urllib.request
 for _ in range(30):
  try:
   with urllib.request.urlopen('http://127.0.0.1:18081/auth/v1/health',timeout=3) as response:
    if response.status==200:break
  except Exception:time.sleep(1)
 else:raise RuntimeError('Fixture Auth did not become ready')
 print('PASS: isolated Auth/PostgreSQL/local SMTP fixture created, no shared service changed')
def cleanup():
 state=json.loads((ROOT/'state.json').read_text())
 for name in reversed(state['containers']):
  obj=json.loads(run('docker','inspect',name))[0]
  assert obj['Config']['Labels'].get('c67.auth-fixture')=='true'
  run('docker','rm','-f','-v',name)
 run('docker','network','rm',NAME)
 run('docker','network','rm',NAME+'-access')
 shutil.rmtree(ROOT)
 print('PASS: exact isolated Auth fixture containers, volumes, network and private files removed')
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('action',choices=['provision','cleanup']);p.add_argument('--approved-auth-verification',action='store_true');a=p.parse_args()
 assert a.approved_auth_verification,'Explicit authorization required'
 try:provision() if a.action=='provision' else cleanup()
 except Exception as e:print('FAIL:',type(e).__name__,'sensitive details suppressed');raise SystemExit(1)
