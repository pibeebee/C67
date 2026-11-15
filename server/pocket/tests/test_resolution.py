"""Synthetic behavior tests; live web/Luna evidence is recorded separately."""
import copy
import json
import os
from pathlib import Path
import socket
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request, urlopen
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from resolution import Resolver, public_url, WebReader, MODEL
from server import Handler, Jobs, ThreadingHTTPServer, stream_response, responses_stream

PLACE = dict(id=str(uuid.uuid4()), name='Synthetic branch', location=dict(latitude=-6.19, longitude=106.67))
TEXT = 'Synthetic branch at Example Street. Open Monday to Sunday 10:00-18:00. Walk-in visitors welcome. Reservation is required. Same-day visitor registration is available at the door.'
SOURCE = dict(id='source-test', url='https://example.com/visit', finalURL='https://example.com/visit', text=TEXT,
              retrievedAt='2026-11-14T00:00:00Z', contentHash='synthetic', state='retrieved')

def claims():
    def fact(value, quote): return dict(value=value, sourceID='source-test', quote=quote)
    return dict(identity=fact('Synthetic branch', 'Synthetic branch at Example Street.'),
                weekly=fact([dict(days=list(range(1,8)), intervals=[['10:00','18:00']])], 'Open Monday to Sunday 10:00-18:00.'),
                access=fact('walk_in', 'Walk-in visitors welcome.'))

class Reader:
    def read(self, url): return copy.deepcopy(SOURCE)
    def close(self): pass

class ResolutionTests(unittest.TestCase):
    def setUp(self):
        self.patcher = patch.dict(os.environ, C67_DISABLE_RESEARCH_RETRY="1")
        self.patcher.start(); self.addCleanup(self.patcher.stop)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)

    def one(self, extracted, accepted=None):
        results = iter([extracted, extracted, dict(accepted=accepted if accepted is not None else list(extracted))])
        def request(_):
            return dict(model='gpt-6-luna(max)', choices=[dict(finish_reason='stop', message=dict(content=json.dumps(next(results))))])
        resolver = Resolver(self.temp.name, request)
        with patch('resolution.WebReader', Reader), patch('resolution.search_place', return_value=[dict(url=SOURCE['url'])]):
            return resolver.one(PLACE, ['2026-11-17'])

    def test_real_source_url_and_weekday_mapping_survive_extraction(self):
        record = self.one(claims())
        self.assertEqual(record['status'], 'ready')
        self.assertEqual(record['venue']['hours']['sourceURL'], SOURCE['finalURL'])
        self.assertEqual(record['venue']['hours']['intervals'][0]['weekday'], 2)
        self.assertTrue((Path(self.temp.name) / (record['snapshotID']+'.json')).is_file())

    def test_invented_quote_cannot_supply_hours(self):
        value = claims(); value['weekly']['quote'] = 'Open daily from 06:00 until midnight.'
        record = self.one(value)
        self.assertEqual(record['status'], 'unresolved')
        self.assertNotIn('venue', record)

    def test_second_pass_can_reject_exact_but_wrong_scope_quote(self):
        record = self.one(claims(), accepted=['identity', 'access'])
        self.assertEqual(record['status'], 'unresolved')
        self.assertNotIn('venue', record)

    def test_missing_branch_identity_is_not_filled_from_model_memory(self):
        value = claims(); value.pop('identity')
        record = self.one(value)
        self.assertEqual(record['status'], 'unresolved')
        self.assertIn('branch', record['reason'])

    def test_absence_of_closure_dates_is_not_promoted_to_known_no_closures(self):
        value=claims();value['closures']=dict(value=[],sourceID='source-test',quote='Open Monday to Sunday 10:00-18:00.')
        result=self.one(value)
        self.assertNotIn('closedDates',result['venue']['hours'])
        snapshot=json.loads((Path(self.temp.name)/(result['snapshotID']+'.json')).read_text())
        self.assertIn('closures',snapshot['rejected'])

    def test_reservation_is_conditional_not_a_confirmed_booking(self):
        value = claims(); value['reservation'] = dict(value='required', sourceID='source-test', quote='Reservation is required.')
        record = self.one(value)
        self.assertEqual(record['status'], 'conditional')
        self.assertTrue(record['venue']['hours']['reservationRequired'])

    def test_explicit_onsite_registration_does_not_require_a_preexisting_membership(self):
        value=claims();value['access']=dict(value='walk_in_with_onsite_registration',sourceID='source-test',quote='Same-day visitor registration is available at the door.')
        result=self.one(value)
        self.assertEqual(result['status'],'ready')
        self.assertFalse(result['venue']['hours']['reservationRequired'])

    def test_malformed_operating_minutes_are_rejected(self):
        value=claims(); value['weekly']['value'][0]['intervals']=[['10:99','18:00']]
        record=self.one(value)
        self.assertEqual(record['status'],'unresolved')
        self.assertNotIn('venue',record)

    def test_source_batches_cover_all_text_with_bounded_model_input(self):
        text=''.join(chr(65+i%26) for i in range(50000))
        source=dict(SOURCE,text=text)
        batches=list(Resolver.source_batches([source],limit=18000))
        self.assertGreater(len(batches),2)
        self.assertTrue(all(sum(len(x['text']) for x in batch)<=18000 for batch in batches))
        self.assertEqual(batches[-1][-1]['text'][-100:],text[-100:])
        self.assertEqual(sum(len(batch[0]['text']) for batch in batches)-400*(len(batches)-1),len(text))

    def test_missing_luna_duration_cannot_be_replaced_by_a_default(self):
        calls = iter([dict(places=[dict(placeID=PLACE['id'], queries=['test hours', 'test access'])]), dict(visits=[])])
        resolver = Resolver(self.temp.name, lambda _:dict(model='gpt-6-luna(max)', choices=[dict(finish_reason='stop', message=dict(content=json.dumps(next(calls))))]))
        for status in ['ready', 'conditional']:
            calls = iter([dict(places=[]),dict(visits=[])])
            with patch.object(resolver, 'one', return_value=dict(placeID=PLACE['id'],status=status,venue=dict(id=PLACE['id']))):
                result=resolver.resolve(dict(places=[PLACE],dates=['2026-11-15']))
            self.assertEqual(result['records'][0]['status'],'unresolved')
            self.assertNotIn('venue',result['records'][0])

    def test_luna_model_and_truncation_cannot_silently_fallback(self):
        for model,finish in [('other-model','stop'),('gpt-6-luna(max)','length')]:
            resolver=Resolver(self.temp.name, lambda _:dict(model=model,choices=[dict(finish_reason=finish,message=dict(content='{}'))]))
            with self.assertRaises(ValueError): resolver.model('test',{})

    def test_sources_include_closure_notices_and_structured_data(self):
        text=WebReader.text('<script type="application/ld+json">{"openingHours":"Mo 10:00-18:00"}</script><aside>Temporarily closed</aside><main>Branch</main>')
        self.assertIn('Temporarily closed',text)
        self.assertIn('openingHours',text)

    def test_staff_authentication_pages_are_not_visitor_hours_evidence(self):
        for url in ['https://absen.example.com/', 'https://pos.example.com/login','https://example.com/forgot-password']:
            self.assertTrue(WebReader.account_page(url))
        self.assertFalse(WebReader.account_page('https://example.com/reservation'))
        reader=WebReader()
        try:
            self.assertEqual(reader.read('https://example.com/login')['state'],'authentication_page_not_visit_evidence')
        finally:reader.close()

    def test_source_dns_cannot_point_to_loopback_or_lan(self):
        for address in ['127.0.0.1','192.168.1.2','::1','169.254.169.254']:
            with patch('resolution.socket.getaddrinfo',return_value=[(socket.AF_INET,socket.SOCK_STREAM,6,'',(address,443))]):
                with self.assertRaises(ValueError): public_url('https://example.com/page')


class StreamTests(unittest.TestCase):
    def test_stream_concatenates_only_real_content_and_keeps_completion_metadata(self):
        events = [dict(model='gpt-6-luna(max)', choices=[dict(index=0,delta=dict(content='{"ok":'))]),
                  dict(model='gpt-6-luna(max)', choices=[dict(index=0,delta=dict(content='true}'),finish_reason='stop')])]
        response = stream_response('\n'.join('data: '+json.dumps(x) for x in events))
        self.assertEqual(response['choices'][0]['message']['content'],'{"ok":true}')
        self.assertEqual(response['choices'][0]['finish_reason'],'stop')
        self.assertEqual(response['model'],'gpt-6-luna(max)')

    def test_missing_completion_is_not_patched(self):
        response=stream_response('data: '+json.dumps(dict(model='gpt-6-luna(max)',choices=[dict(delta=dict(content='{}'))])))
        self.assertIsNone(response['choices'][0]['finish_reason'])

    def test_another_stream_model_is_not_accepted(self):
        with self.assertRaises(ValueError):stream_response('data: '+json.dumps(dict(model='other',choices=[])))

class NativeResponsesTests(unittest.TestCase):
    def response(self, status='completed', model='gpt-6-luna', effort='max'):
        final=dict(status=status,model=model,reasoning=dict(effort=effort),output=[dict(type='message',content=[dict(type='output_text',text='{"ok":true}')])])
        events=[dict(type='response.created',response=dict(model='gpt-6-luna')),dict(type='response.output_text.delta',delta='{"ok":true}'),dict(type='response.completed',response=final)]
        return '\n'.join('data: '+json.dumps(x) for x in events)

    def test_native_response_preserves_the_actual_model_and_max_effort(self):
        result=responses_stream(self.response())
        self.assertEqual(result['model'],'gpt-6-luna')
        self.assertEqual(result['reasoning']['effort'],'max')
        self.assertEqual(result['completionStatus'],'completed')
        with tempfile.TemporaryDirectory() as directory:
            value,model=Resolver(directory,lambda _:result).model('test',{})
        self.assertEqual(value,dict(ok=True));self.assertEqual(model,'gpt-6-luna')

    def test_native_response_cannot_invent_completion_or_change_model(self):
        for status,model in [('incomplete','gpt-6-luna'),('completed','another-model')]:
            with self.assertRaises(ValueError):responses_stream(self.response(status,model))
        with self.assertRaises(ValueError):responses_stream('data: {}')

    def test_native_base_name_without_verified_max_effort_is_rejected(self):
        for effort in [None,'low','high']:
            result=responses_stream(self.response(effort=effort))
            with tempfile.TemporaryDirectory() as directory:
                with self.assertRaises(ValueError):Resolver(directory,lambda _:result).model('test',{})

    def test_native_text_must_match_the_completed_message(self):
        with self.assertRaises(ValueError):responses_stream(self.response().replace('"delta": "{\\"ok\\":true}"','"delta": "different"'))

class JobTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.started=threading.Event();self.release=threading.Event();self.calls=0
        outer=self
        class FakeResolver:
            def resolve(self,body):
                outer.calls+=1;outer.started.set();outer.release.wait(3)
                return dict(records=[dict(placeID=p['id'],status='unresolved') for p in body['places']],requestedModel=MODEL,reportedModel='gpt-6-luna(max)')
        self.jobs=Jobs(self.temp.name,FakeResolver())
        self.body=dict(requestID=str(uuid.uuid4()),places=[PLACE])
        self.addCleanup(self.release.set)

    def test_async_retry_preserves_original_selections_and_runs_once(self):
        first=self.jobs.submit(self.body)
        self.assertTrue(self.started.wait(1));self.assertEqual(first['status'],'running')
        self.jobs.submit(self.body);self.assertEqual(self.calls,1)
        with self.jobs.connection() as db:
            stored=json.loads(db.execute('SELECT request FROM jobs').fetchone()[0])
        self.assertEqual(stored['places'],[PLACE])
        self.release.set()
        for _ in range(100):
            result=self.jobs.get(first['id'])
            if result['status']=='succeeded': break
            time.sleep(.01)
        self.assertEqual(result['status'],'succeeded')
        self.jobs.submit(self.body);self.assertEqual(self.calls,1)

    def test_changed_selection_cannot_reuse_a_request_id(self):
        self.jobs.submit(self.body)
        changed=copy.deepcopy(self.body);changed['places'][0]['name']='Different branch'
        with self.assertRaises(ValueError):self.jobs.submit(changed)
        self.release.set()

    def test_http_requires_auth_and_has_no_catalog_route(self):
        server=ThreadingHTTPServer(('127.0.0.1',0),Handler);server.jobs=self.jobs
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        def close():server.shutdown();server.server_close();thread.join()
        self.addCleanup(close)
        with patch.dict(os.environ,POCKET_READ_TOKEN='synthetic-private-test-token'):
            base='http://127.0.0.1:'+str(server.server_port)
            with self.assertRaises(HTTPError) as error:urlopen(base+'/v1/visits/jobs/'+self.body['requestID'])
            self.assertEqual(error.exception.code,401)
            request=Request(base+'/v1/catalog',headers={'Authorization':'Bearer synthetic-private-test-token'})
            with self.assertRaises(HTTPError) as error:urlopen(request)
            self.assertEqual(error.exception.code,404)
            request=Request(base+'/v1/visits/resolve',data=json.dumps(self.body).encode(),headers={'Authorization':'Bearer synthetic-private-test-token','Content-Type':'application/json'})
            with urlopen(request) as response:self.assertEqual(response.status,202)
            self.release.set()

if __name__=='__main__':unittest.main()
