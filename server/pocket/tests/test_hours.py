"""Synthetic tests only; no remote hours or user credentials."""
import json, sys, unittest
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
    def test_authenticated_lookup_is_transient(self):
        import threading
        from unittest.mock import patch
        from urllib.request import Request, urlopen
        from urllib.error import HTTPError
        from server import Handler, ThreadingHTTPServer
        service=ThreadingHTTPServer(('127.0.0.1',0),Handler)
        thread=threading.Thread(target=service.serve_forever,daemon=True);thread.start()
        endpoint=f'http://127.0.0.1:{service.server_address[1]}/v1/hours/lookup'
        try:
            def post():
                return urlopen(Request(endpoint,data=b'{"placeId":"I123A"}',headers={'Content-Type':'application/json'}))
            with patch.object(Handler,'authorized',return_value=None):
                with self.assertRaises(HTTPError) as error:post()
                self.assertEqual(error.exception.code,401)
            with patch.object(Handler,'authorized',return_value='synthetic-user'), patch('server.HoursProvider') as provider:
                provider.return_value.lookup.return_value={'status':'unavailable'}
                with post() as response:self.assertEqual(json.load(response),{'status':'unavailable'})
                provider.return_value.lookup.assert_called_once_with('I123A')
        finally:
            service.shutdown();service.server_close();thread.join()
