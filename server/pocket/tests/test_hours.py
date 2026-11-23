"""Synthetic tests only; no remote hours or user credentials."""
import json, sys, unittest
from datetime import datetime, timedelta, timezone
from tempfile import TemporaryDirectory
from pathlib import Path
from types import SimpleNamespace
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
from hours import HoursProvider, category_hint, validate_hours

class Response:
    def __init__(self, code, value=None):
        self.status_code=code;self.value=value or {};self.content=json.dumps(self.value).encode()
    def json(self):return self.value

def record():
    return {'placeId':'I123A','timezone':'Asia/Jakarta','weekly':[{'weekday':i,'intervals':[{'startSeconds':36000,'endSeconds':79200}]} for i in range(1,8)]}

class HoursTests(unittest.TestCase):
    def provider(self, responses, calls):
        def get(*args, **kwargs):
            calls.append(kwargs);return responses.pop(0)
        return HoursProvider('https://hours.example.test', 'synthetic-key', get=get, sleep=lambda _:None)
    def test_cinema_crosses_midnight_and_unrecognized_abstains(self):
        self.assertEqual(category_hint('MKPOICategoryMovieTheater')['endSecondsFromStartDay'],93600)
        self.assertEqual(category_hint('Museum')['startSeconds'],32400)
        self.assertIsNone(category_hint('restaurant'))
    def test_explicit_response_validates_identity_zone_and_seven_days(self):
        self.assertEqual(validate_hours(record(),'I123A')['timezone'],'Asia/Jakarta')
        for change in ('identity','timezone','weekday','boundary','hours_type'):
            v=record()
            if change=='identity':v['placeId']='I999'
            elif change=='timezone':v['timezone']='bad/timezone'
            elif change=='weekday':v['weekly'][0]['weekday']=2
            elif change=='boundary':v['weekly'][0]['intervals'][0]['endSeconds']=90000
            else:v['hoursType']='SPECIAL'
            with self.assertRaises(ValueError):validate_hours(v,'I123A')
    def test_404_is_unavailable_without_retry(self):
        calls=[];p=self.provider([Response(404)],calls)
        self.assertEqual(p.lookup('I123A'),{'status':'unavailable'});self.assertEqual(len(calls),1)
    def test_502_retry_once_and_no_token_in_result(self):
        calls=[];p=self.provider([Response(502),Response(200,record())],calls)
        r=p.lookup('I123A');self.assertEqual(r['status'],'available');self.assertEqual(len(calls),2)
        self.assertNotIn('synthetic-key',json.dumps(r));self.assertFalse(calls[0]['follow_redirects'])
    def test_auth_error_and_invalid_id_do_not_retry(self):
        calls=[];p=self.provider([Response(401)],calls)
        self.assertEqual(p.lookup('I123A')['status'],'configuration_error');self.assertEqual(len(calls),1)
        self.assertEqual(p.lookup('not-an-id')['status'],'invalid_place_id');self.assertEqual(len(calls),1)
    def test_200_error_body_does_not_invent_hours(self):
        calls=[];p=self.provider([Response(200,{'error':'no business hours found'})],calls)
        self.assertEqual(p.lookup('I123A')['status'],'unavailable')

if __name__=='__main__':unittest.main()

class HoursHTTPTests(unittest.TestCase):
    def test_authenticated_lookup_returns_only_current_entry_evidence_for_the_owner(self):
        import threading
        import uuid
        from unittest.mock import patch
        from urllib.request import Request, urlopen
        from urllib.error import HTTPError
        from server import Handler, Jobs, ThreadingHTTPServer

        with TemporaryDirectory() as directory:
            service = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
            service.jobs = Jobs(directory, None)
            thread = threading.Thread(target=service.serve_forever, daemon=True)
            thread.start()
            endpoint = f'http://127.0.0.1:{service.server_address[1]}/v1/hours/lookup'

            def post(place_id='I123A'):
                body = json.dumps({'placeId': place_id}).encode()
                with urlopen(Request(endpoint, data=body, headers={'Content-Type': 'application/json'})) as response:
                    return json.load(response)

            def save(place_id, *, expired=False, status='supported'):
                stop_id = str(uuid.uuid4())
                now = datetime.now(timezone.utc)
                checked = now - timedelta(days=2)
                expires = now + timedelta(days=-1 if expired else 1)
                request = {'places': [{'id': stop_id, 'sourceID': 'apple:' + place_id}]}
                result = {'resolvedAt': checked.isoformat(), 'records': [{
                    'placeID': stop_id.upper(), 'status': 'ready',
                    'venue': {'facts': [{
                        'field': 'publicAccess', 'status': status, 'value': 'walk_in_with_onsite_registration',
                        'checkedAt': checked.isoformat(), 'expiresAt': expires.isoformat(),
                        'sourceURL': 'https://venue.example.test/entry',
                    }]},
                }]}
                with service.jobs.connection() as db:
                    db.execute("INSERT INTO jobs (id,state,request,result,owner) VALUES (?,?,?,?,?)",
                               (str(uuid.uuid4()), 'succeeded', json.dumps(request), json.dumps(result), 'synthetic-owner'))

            try:
                save('I123A')
                save('I123B', expired=True)
                save('I123C', status='unsupported')
                with patch.object(Handler, 'authorized', return_value=None):
                    with self.assertRaises(HTTPError) as error:
                        post()
                    self.assertEqual(error.exception.code, 401)
                    error.exception.close()

                with patch('server.HoursProvider') as provider:
                    provider.return_value.lookup.return_value = {'status': 'unavailable'}
                    with patch.object(Handler, 'authorized', return_value='synthetic-owner'):
                        self.assertEqual(post(), {'status': 'unavailable', 'entryRule': {
                            'kind': 'walk_in_with_onsite_registration', 'sourceURL': 'https://venue.example.test/entry',
                        }})
                        self.assertEqual(post('I123B'), {'status': 'unavailable'})
                        self.assertEqual(post('I123C'), {'status': 'unavailable'})
                        self.assertEqual(post('I123D'), {'status': 'unavailable'})
                    for caller in ['synthetic-other', 'legacy']:
                        with patch.object(Handler, 'authorized', return_value=caller):
                            self.assertEqual(post(), {'status': 'unavailable'})
                    with patch.object(Handler, 'authorized', return_value='synthetic-owner'):
                        provider.return_value.lookup.return_value = {'status': 'available', 'hours': record()}
                        self.assertEqual(post()['hours'], record())
            finally:
                service.shutdown()
                service.server_close()
                thread.join()


if __name__ == '__main__':
    unittest.main()
