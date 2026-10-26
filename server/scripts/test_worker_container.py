"""Build/run the production worker image on disposable Linux CI only."""
import os
import subprocess
from test_local_api import LocalAPI, SERVER, require
api=LocalAPI()
p=subprocess.run(['docker','build','--tag','c67-media-ci',str(SERVER/'workers/media')],capture_output=True)
require(p.returncode==0,'Media image build failed; diagnostics suppressed')
env=os.environ.copy();env.update(SUPABASE_URL='http://127.0.0.1:54321',SUPABASE_SERVICE_ROLE_KEY=api.server_key)
p=subprocess.run(['docker','run','--rm','--network','host','--read-only','--tmpfs','/tmp:rw,noexec,nosuid,size=64m,mode=1777','--security-opt','no-new-privileges:true','--cap-drop','ALL','--memory','512m','--cpus','1','--pids-limit','128','-e','SUPABASE_URL','-e','SUPABASE_SERVICE_ROLE_KEY','c67-media-ci','node','worker.mjs','--once'],env=env,capture_output=True,timeout=120)
require(p.returncode==0,'Production media container smoke test failed; diagnostics suppressed')
print('PASS: production media Docker image runs with restricted filesystem/capabilities/resources against disposable CI')
