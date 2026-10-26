"""Explicitly approved, private, same-host backup only. Never resets/restores shared data."""
import argparse
from datetime import datetime, timezone
import re
import subprocess


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--approved-backup',action='store_true');p.add_argument('--name',required=True)
    a=p.parse_args()
    if not a.approved_backup:p.error('Review and explicitly approve the exact target/backup before execution')
    if not re.fullmatch(r'[a-z0-9][a-z0-9-]{0,70}',a.name):p.error('Invalid backup name')
    script=r'''
import hashlib,json,os,pathlib,subprocess
os.umask(0o077)
root=pathlib.Path('/home/giovan/backups/c67')
x=json.loads(subprocess.check_output(['docker','inspect','supabase-db']))[0]
assert x['Config']['Labels']['com.docker.compose.project']=='supabase'
assert x['Config']['Labels']['com.docker.compose.project.working_dir']=='/home/giovan/apps/supabase'
assert x['State']['Health']['Status']=='healthy' and not x['HostConfig']['PortBindings']
b=root/NAME
b.mkdir(mode=0o700) # Exclusively new: never overwrite an existing recovery point.
def save(name,args):
 p=subprocess.run(args,capture_output=True)
 if p.returncode:raise SystemExit('Backup step failed; sensitive diagnostics suppressed')
 (b/name).write_bytes(p.stdout)
for db,name in [('postgres','postgres.dump'),('_supabase','platform-metadata.dump')]:
 save(name,['docker','exec','supabase-db','pg_dump','-U','postgres','-d',db,'--format=custom'])
save('roles.sql',['docker','exec','supabase-db','pg_dumpall','-U','postgres','--roles-only','--no-role-passwords'])
save('supabase-config.tar.gz',['tar','-czf','-','-C','/home/giovan/apps/supabase','.env','docker-compose.yml','docker-compose.cf-tunnel.yml','volumes/api/envoy'])
save('supabase-storage.tar.gz',['tar','-czf','-','-C','/hdd/supabase','storage'])
files=sorted(p for p in b.iterdir() if p.is_file())
(b/'SHA256SUMS').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name+'\n' for p in files))
for name in ['postgres.dump','platform-metadata.dump']:
 p=subprocess.run(['docker','exec','-i','supabase-db','pg_restore','--list'],input=(b/name).read_bytes(),capture_output=True);assert p.returncode==0
for name in ['supabase-config.tar.gz','supabase-storage.tar.gz']:
 assert subprocess.run(['tar','-tzf',str(b/name)],capture_output=True).returncode==0
assert all(p.stat().st_mode&0o777==0o600 for p in b.iterdir())
print('PASS: private backup and archives verified; restore drill remains a separate gate')
'''
    return subprocess.run(['ssh','-o','BatchMode=yes','-o','ConnectTimeout=10','homelab','python3','-'],input='NAME='+repr(a.name)+'\n'+script,text=True).returncode
if __name__=='__main__':raise SystemExit(main())
