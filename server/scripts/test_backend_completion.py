"""Full private backend acceptance on local CI; shared execution needs separate approval."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess
import sys
from urllib.error import HTTPError
from urllib.request import Request, ProxyHandler, HTTPSHandler, build_opener
from uuid import uuid4
from test_local_api import LocalAPI, NoRedirects, CheckFailure, ROOT, SERVER, require, BASE_URL


def run(api, shared=False):
    origin = 'https://supabase.mrt.qzz.io' if shared else BASE_URL
    def rpc(name, body, token=None, status=200, admin=False):
        return api.expect(api.request('POST', '/rest/v1/rpc/'+name, body, token=token, admin=admin), status)
    def binary(path, method='GET', data=None, token=None, admin=False, content_type='image/png'):
        headers={'apikey':api.server_key if admin else api.client_key,'Content-Type':content_type,
                 'User-Agent':'C67-Approved-Verification/1.0'}
        if admin or token:headers['Authorization']='Bearer '+(api.server_key if admin else token)
        handlers=[ProxyHandler({}),NoRedirects()]
        if shared:handlers.append(HTTPSHandler(context=api.context))
        try:
            with build_opener(*handlers).open(Request(origin+path,data=data,headers=headers,method=method),timeout=30) as r:return r.status,r.read()
        except HTTPError as e:return e.code,e.read()
    api.completion_upload_ids=[]
    def worker(upload_id):
        env=os.environ.copy();env.update(SUPABASE_URL=origin,SUPABASE_SERVICE_ROLE_KEY=api.server_key)
        code="import {Worker} from './worker.mjs';const w=new Worker(process.env.SUPABASE_URL,process.env.SUPABASE_SERVICE_ROLE_KEY);await w.once("+json.dumps(upload_id)+");"
        p=subprocess.run(['node','--input-type=module','-e',code],cwd=SERVER/'workers/media',env=env,capture_output=True,text=True,timeout=90)
        require(p.returncode==0,'Media worker failed; sensitive diagnostics suppressed')
    a,b=api.login('a'),api.login('b');ta,tb=a['access_token'],b['access_token']
    fixture=json.loads((ROOT/'contracts/fixtures/rundowns.json').read_text())[0]
    versions=[]
    for index in range(2):
        vid=str(uuid4());route=json.loads((ROOT/'contracts/fixtures/route-template-first-stop.json').read_text())
        body={'id':vid,'title':f'Synthetic Completion {index}','area':'CompletionTest','summary':'Synthetic backend acceptance fixture','stops':fixture['stops'],'published':True,'route_template':route}
        api.expect(api.request('POST','/rest/v1/rundown_versions',body,admin=True),201);api.extra_version_ids.append(vid);versions.append(vid)
    page=rpc('search_rundowns',{'p_query':'completion','p_area':'completiontest','p_limit':1})
    require(len(page['items'])==1 and page['next_cursor'],'Discovery did not paginate temporary fixtures')
    second=rpc('search_rundowns',{'p_query':'completion','p_area':'completiontest','p_limit':1,'p_cursor':page['next_cursor']})
    require(len(second['items'])==1 and second['items'][0]['id']!=page['items'][0]['id'] and second['next_cursor'] is None,'Discovery duplicate/gap')
    rpc('search_rundowns',{'p_query':'different','p_cursor':page['next_cursor']},status=400)
    require(rpc('search_rundowns',{'p_query':'no_such_completion_term'})=={'items':[],'next_cursor':None},'Discovery empty page differs')
    api.passed_check('Text/area discovery pages are bounded, query-bound and stable')
    command={'p_version_id':versions[0],'p_starts_at':'2026-11-01T02:00:00Z','p_time_zone':'UTC','p_start_time_basis':'start_at_landing','p_request_id':str(uuid4())}
    original=rpc('create_trip_v3',command,ta);trip=original['id']
    preview=rpc('preview_trip_change',{'p_trip_id':trip,'p_expected_revision':1,'p_patch':{'title':'Edited private trip'}},ta)
    other=rpc('preview_trip_change',{'p_trip_id':trip,'p_expected_revision':1,'p_patch':{'title':'Other edit'}},ta)
    apply={'p_preview_id':preview['preview_id'],'p_request_id':str(uuid4())}
    changed=rpc('apply_trip_change',apply,ta)
    require(changed['revision']==2 and changed['title']=='Edited private trip','Accepted edit did not increment exactly once')
    require(rpc('apply_trip_change',apply,ta)==changed and rpc('create_trip_v3',command,ta)==original,'Creation/edit receipt changed after mutation')
    rpc('apply_trip_change',{'p_preview_id':other['preview_id'],'p_request_id':str(uuid4())},ta,status=409)
    rpc('preview_trip_change',{'p_trip_id':trip,'p_expected_revision':2,'p_patch':{'title':'Forbidden'}},tb,status=404)
    api.passed_check('Edits use owner/revision checks and immutable creation/apply receipts')
    # Competing writes from the same revision: exactly one commits.
    choices=[rpc('preview_trip_change',{'p_trip_id':trip,'p_expected_revision':2,'p_patch':{'title':f'Concurrent {i}'}},ta) for i in range(2)]
    with ThreadPoolExecutor(max_workers=2) as pool:
        replies=list(pool.map(lambda p:api.request('POST','/rest/v1/rpc/apply_trip_change',{'p_preview_id':p['preview_id'],'p_request_id':str(uuid4())},token=ta),choices))
    require(sorted(r[0] for r in replies)==[200,409],'Concurrent revisions were not serialized')
    api.passed_check('Two edits with the same revision accept exactly one command')
    graph=rpc('get_trip_graph',{'p_trip_id':trip},ta)
    schedule=rpc('preview_trip_change',{'p_trip_id':trip,'p_expected_revision':graph['revision'],'p_patch':{'starts_at':'2026-11-02T16:00:00Z','time_zone':'Asia/Tokyo'}},ta)
    graph=rpc('apply_trip_change',{'p_preview_id':schedule['preview_id'],'p_request_id':str(uuid4())},ta)
    require(graph['days'][0]['local_date']=='2026-11-03' and graph['days'][0]['starts_at']==graph['starts_at'],'Root/day reschedule is inconsistent')
    require(rpc('create_trip_v3',command,ta)==original,'Reschedule changed creation receipt')
    api.passed_check('Reschedule changes root/day/date atomically and preserves the creation receipt')
    merge=rpc('preview_trip_change',{'p_trip_id':trip,'p_expected_revision':graph['revision'],'p_patch':{'append_version_id':versions[1]}},ta)
    merged=rpc('apply_trip_change',{'p_preview_id':merge['preview_id'],'p_request_id':str(uuid4())},ta)
    require(len(merged['sources'])==2 and len(merged['stops'])==4 and len({s['id'] for s in merged['stops']})==4,'Explicit append lost occurrences/provenance')
    require(all(l['duration_seconds'] is None for l in merged['legs']),'Merged adjacency kept stale route durations')
    require(merged['stops'][0]['id']==original['stops'][0]['id'],'Existing occurrence identity changed')
    api.passed_check('Explicit source append keeps both occurrences/credits and invalidates old estimates')
    # Choose which repeated occurrences to retain explicitly; never name-deduplicate automatically.
    selected=[merged['stops'][0]['id'],merged['stops'][3]['id']]
    choose=rpc('preview_trip_change',{'p_trip_id':trip,'p_expected_revision':merged['revision'],'p_patch':{'stop_order':selected}},ta)
    merged=rpc('apply_trip_change',{'p_preview_id':choose['preview_id'],'p_request_id':str(uuid4())},ta)
    require([s['id'] for s in merged['stops']]==selected and len(merged['sources'])==2,'Explicit overlap resolution lost retained IDs or attribution')
    api.passed_check('User-selected retained occurrence order resolves overlaps without automatic name deduplication')
    # Use the original located stop. Source appends keep unknown geometry until a resolver supplies it.
    stop=merged['stops'][0]
    location={**stop['location'],'accuracy_m':5,'sampled_at':datetime.now(timezone.utc).isoformat()}
    begin={'p_trip_id':trip,'p_stop_id':stop['id'],'p_request_id':str(uuid4()),'p_content_type':'image/png','p_location':location}
    far={**begin,'p_request_id':str(uuid4()),'p_location':{**location,'latitude':50}}
    rpc('begin_journal_upload',far,ta,status=403)
    rpc('begin_journal_upload',begin,tb,status=404)
    session=rpc('begin_journal_upload',begin,ta)
    api.completion_upload_ids.append(session['upload_id'])
    require(rpc('begin_journal_upload',begin,ta)==session,'Upload session retry changed identity')
    rpc('claim_journal_job',{},ta,status=403)
    rpc('finish_journal_job',{'p_upload_id':session['upload_id'],'p_lease_id':str(uuid4()),'p_result':{}},ta,status=403)
    api.passed_check('Upload sessions bind recent reported location and worker RPCs deny travellers')
    # Pending upload also protects the plan before any worker accepts a journal.
    order=[s['id'] for s in reversed(merged['stops'])]
    p=rpc('preview_trip_change',{'p_trip_id':trip,'p_expected_revision':merged['revision'],'p_patch':{'stop_order':order}},ta)
    rpc('apply_trip_change',{'p_preview_id':p['preview_id'],'p_request_id':str(uuid4())},ta,status=409)
    api.passed_check('Pending uploads protect topology under the shared trip lock')
    code="import sharp from 'sharp';process.stdout.write(await sharp({create:{width:16,height:12,channels:3,background:'red'}}).withMetadata().png().toBuffer());"
    png=subprocess.run(['node','--input-type=module','-e',code],cwd=SERVER/'workers/media',capture_output=True,check=True).stdout
    path='/storage/v1/object/c67-journal-raw/'+session['path']
    require(binary(path,'POST',png,tb)[0] in (400,401,403),'Other user uploaded into session')
    require(binary(path,'POST',png,ta)[0] in (200,201),'Valid image upload failed')
    require(binary('/storage/v1/object/authenticated/c67-journal-raw/'+session['path'],token=ta)[0] in (400,401,403,404),'Raw metadata-bearing input is readable by client')
    rpc('submit_journal_upload',{'p_upload_id':session['upload_id']},ta)
    stalled=rpc('claim_journal_job',{'p_upload_id':session['upload_id']},admin=True)
    require(stalled and stalled['upload_id']==session['upload_id'],'Worker did not claim queued upload')
    api.expect(api.request('PATCH','/rest/v1/journal_uploads?id=eq.'+session['upload_id'],
                          {'lease_until':'2000-01-01T00:00:00Z','expires_at':'2000-01-01T00:00:00Z'},admin=True),204)
    worker(session['upload_id'])
    rpc('finish_journal_job',{'p_upload_id':session['upload_id'],'p_lease_id':stalled['lease_id'],'p_result':{}},admin=True,status=409)
    worker(session['upload_id'])
    api.passed_check('Expired worker lease recovers; delayed validation needs no second presence check or duplicate journal')
    album=rpc('list_trip_album',{'p_trip_id':trip},ta)
    require(len(album)==1 and album[0]['width']==16 and album[0]['height']==12,'Accepted journal/album projection missing')
    rpc('list_trip_album',{'p_trip_id':trip},tb,status=404)
    ready='/storage/v1/object/authenticated/c67-journal-ready/'+album[0]['object_path']
    require(binary(ready,token=tb)[0] in (400,401,403,404),'Processed private image leaked to other account')
    require(binary(ready)[0] in (400,401,403,404),'Private image leaked without session')
    status,photo=binary(ready,token=ta);require(status==200 and photo[:2]==b'\xff\xd8','Owner cannot download processed JPEG')
    api.passed_check('Real Storage→worker→accepted journal→private album path succeeds and blocks other accounts')
    require(rpc('begin_journal_upload',begin,ta)['upload_id']==session['upload_id'],'Session retry changed after finalization')
    graph=rpc('get_trip_graph',{'p_trip_id':trip},ta)
    p=rpc('preview_trip_change',{'p_trip_id':trip,'p_expected_revision':graph['revision'],'p_patch':{'stop_order':order}},ta)
    rpc('apply_trip_change',{'p_preview_id':p['preview_id'],'p_request_id':str(uuid4())},ta,status=409)
    require(rpc('list_trip_album',{'p_trip_id':trip},ta)==album,'Rejected replan damaged accepted journal')
    require(rpc('create_trip_v3',command,ta)==original,'Create receipt changed after journal revision')
    title_preview=rpc('preview_trip_change',{'p_trip_id':trip,'p_expected_revision':graph['revision'],'p_patch':{'title':'Private album title'}},ta)
    renamed=rpc('apply_trip_change',{'p_preview_id':title_preview['preview_id'],'p_request_id':str(uuid4())},ta)
    require(renamed['title']=='Private album title' and rpc('list_trip_album',{'p_trip_id':trip},ta)==album,'Title-only edit changed documented topology')
    api.passed_check('Accepted journals remain protected; receipt retries survive later plan/journal revisions')
    location['sampled_at']=datetime.now(timezone.utc).isoformat()
    invalid=rpc('begin_journal_upload',{**begin,'p_request_id':str(uuid4()),'p_location':location},ta)
    require(binary('/storage/v1/object/c67-journal-raw/'+invalid['path'],'POST',b'fake png',ta)[0] in (200,201),'Could not provision invalid media bytes')
    api.completion_upload_ids.append(invalid['upload_id'])
    rpc('submit_journal_upload',{'p_upload_id':invalid['upload_id']},ta);worker(invalid['upload_id'])
    status=rpc('submit_journal_upload',{'p_upload_id':invalid['upload_id']},ta)
    require(status['state']=='rejected' and status['failure_code']=='invalid_image','Fake media was not rejected by decode')
    require(rpc('list_trip_album',{'p_trip_id':trip},ta)==album,'Invalid bytes entered album')
    api.passed_check('Undecodable upload is rejected without a journal or album change')
    return None


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--approved-shared-test',action='store_true');args=parser.parse_args()
    api=None;cleaner=None;failed=False
    try:
        if args.approved_shared_test:
            from test_homelab_api import HomelabAPI
            api=HomelabAPI()
        else:api=LocalAPI()
        cleaner=run(api,args.approved_shared_test)
    except Exception as e:
        print('FAIL: '+(str(e) if isinstance(e,CheckFailure) else type(e).__name__)+'; sensitive diagnostics suppressed',file=sys.stderr);failed=True
    finally:
        if api is not None:
            try:
                api.cleanup()
                # Cleanup bytes through Storage API after accounts/journals are gone, never SQL-delete objects.
                origin='https://supabase.mrt.qzz.io' if args.approved_shared_test else BASE_URL
                env=os.environ.copy();env.update(SUPABASE_URL=origin,SUPABASE_SERVICE_ROLE_KEY=api.server_key)
                code="import {Worker} from './worker.mjs';await new Worker(process.env.SUPABASE_URL,process.env.SUPABASE_SERVICE_ROLE_KEY).cleanup("+json.dumps(getattr(api,'completion_upload_ids',[]))+");"
                p=subprocess.run(['node','--input-type=module','-e',code],cwd=SERVER/'workers/media',env=env,capture_output=True,timeout=90)
                require(p.returncode==0,'Media cleanup failed')
                for table in ['journal_entries','journal_uploads']:
                    require(api.expect(api.request('GET','/rest/v1/'+table+'?select=id',admin=True),200)==[],'Temporary journal rows remain')
                api.passed_check('Temporary accounts/graphs/fixtures and private Storage bytes are cleaned up')
            except Exception:print('FAIL: backend cleanup incomplete; inspect only this run records',file=sys.stderr);failed=True
    if not failed:print(f'PASS: {api.passed} backend completion checks')
    return int(failed)
if __name__=='__main__':raise SystemExit(main())
