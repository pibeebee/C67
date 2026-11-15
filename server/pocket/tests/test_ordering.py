"""Ordering acceptance boundaries. Synthetic responses; no provider calls."""
import copy
import json
import os
import threading
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request, urlopen
from pathlib import Path
import sys
import tempfile
import time
import unittest
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from ordering import OrderingResolver, request_context
from server import Jobs, Handler, ThreadingHTTPServer


def body(count=5):
    places = [dict(id=str(uuid.uuid4()), name=f"Synthetic place {i}", location=dict(latitude=-6.2-i/1000, longitude=106.8), categories=[]) for i in range(count)]
    return dict(requestID=str(uuid.uuid4()), places=places, preferences="Synthetic reading/coffee wishes", origin=dict(latitude=-6.2, longitude=106.8),
                mainSpotID=places[0]["id"], candidateDate="2026-11-16", timeZone="Asia/Jakarta")


def answer(context):
    stops=[]
    for i,p in enumerate(context["places"]):
        sources=[s["id"] for s in context["weatherSources"] if s["placeID"]==p["id"]]
        stops.append(dict(placeID=p["id"], activity=dict(suggestion="Synthetic activity suggestion",basis="unknown"),
            role="main" if p["id"]==context["mainSpotID"] else "supporting",
            duration=None if i==1 else dict(minMinutes=30,maxMinutes=60,rationale="Synthetic estimate",basis="experience_estimate"),
            durationUnknownReason="Unknown activity" if i==1 else None, preferredDayPart="flexible", reason="Synthetic reason",
            weather=dict(sourceRefs=sources,status="available" if sources else "unavailable",advice="Unknown weather"),
            light=dict(windowRef=None,priority="unknown",advice="No guaranteed light"), uncertainties=["Unknown venue facts"]))
    return dict(status="proposed",orderedIDs=[p["id"] for p in context["places"]],tripRationale="Synthetic order",
                stops=stops,alternativeOrder=None,tradeoffs=[],uncertainties=["No arrival or availability guarantee"])


class NoWeather:
    def read(self,*args): return []


class OrderingTests(unittest.TestCase):
    def resolver(self, mutate=None, environment=None):
        def model(prompt, context):
            value=answer(context)
            if mutate:mutate(value,context)
            return value,"gpt-6-luna"
        return OrderingResolver(model,environment or NoWeather())

    def test_all_places_are_kept_without_hours_eta_or_duration(self):
        value=body(); result=self.resolver().resolve(value)
        self.assertEqual(result["orderedIDs"],[p["id"] for p in value["places"]])
        self.assertIsNone(result["stops"][1]["duration"])
        self.assertEqual(result["weatherSources"],[])
        self.assertNotIn("arrivalAt",result)

    def test_more_than_six_and_foreign_pins_have_no_catalog_or_area_gate(self):
        value=body(8);value["places"][0]["location"]=dict(latitude=35.6,longitude=139.7)
        self.assertEqual(len(self.resolver().resolve(value)["orderedIDs"]),8)

    def test_weather_failure_is_nonblocking_and_explicit(self):
        class Broken:
            def read(self,*args):raise OSError("Synthetic failure")
        result=self.resolver(environment=Broken()).resolve(body())
        self.assertEqual(len(result["orderedIDs"]),5)
        self.assertTrue(result["contextWarnings"])

    def test_duplicate_selection_is_rejected_before_model(self):
        value=body();value["places"].append(value["places"][0])
        with self.assertRaises(ValueError):request_context(value)

    def test_unknown_main_spot_is_rejected(self):
        value=body();value["mainSpotID"]=str(uuid.uuid4())
        with self.assertRaises(ValueError):request_context(value)

    def test_lost_or_new_model_destination_is_rejected(self):
        for mutate in [lambda a,c:a["orderedIDs"].pop(),lambda a,c:a["orderedIDs"].__setitem__(0,str(uuid.uuid4()))]:
            with self.subTest(mutate=mutate),self.assertRaises(ValueError):self.resolver(mutate).resolve(body())

    def test_invalid_duration_and_false_operator_rule_are_rejected(self):
        for update in [dict(minMinutes=0),dict(maxMinutes=1),dict(basis="operator_rule")]:
            with self.subTest(update=update),self.assertRaises(ValueError):
                self.resolver(lambda a,c:a["stops"][0]["duration"].update(update)).resolve(body())

    def test_cross_place_or_invented_source_reference_is_rejected(self):
        with self.assertRaises(ValueError):
            self.resolver(lambda a,c:a["stops"][0]["weather"].update(sourceRefs=["fake"])).resolve(body())

    def test_numeric_weather_prose_is_rejected_not_repaired(self):
        with self.assertRaises(ValueError):
            self.resolver(lambda a,c:a.update(tripRationale="Pasti hujan 85% pada 17:00")).resolve(body())

    def test_manual_order_must_remain_exact(self):
        value=body();value["preservesPlaceOrder"]=True
        with self.assertRaises(ValueError):
            self.resolver(lambda a,c:a["orderedIDs"].reverse()).resolve(value)
        self.assertEqual(self.resolver().resolve(value)["orderedIDs"],[p["id"] for p in value["places"]])

    def test_first_place_constraint_is_not_silently_lost(self):
        value=body();value["firstPlaceID"]=value["places"][-1]["id"]
        with self.assertRaises(ValueError):self.resolver().resolve(value)

    def test_completed_job_reads_and_duplicates_do_not_regenerate(self):
        calls=[]
        class Resolver:
            def resolve(self,b):calls.append(b);return dict(orderedIDs=[p["id"] for p in b["places"]])
        with tempfile.TemporaryDirectory() as directory:
            jobs=Jobs(directory,Resolver(),retry_failed=False);value=body();jobs.submit(value)
            result=self.wait(jobs,value["requestID"])
            self.assertEqual(result["status"],"succeeded")
            jobs.submit(value);jobs.get(value["requestID"])
            self.assertEqual(len(calls),1)
            changed=copy.deepcopy(value);changed["preferences"]+=" changed"
            with self.assertRaises(ValueError):jobs.submit(changed)

    def test_failed_generation_never_automatically_retries_same_id(self):
        calls=[]
        class Broken:
            def resolve(self,b):calls.append(b);raise OSError("Synthetic transport failure")
        with tempfile.TemporaryDirectory() as directory:
            jobs=Jobs(directory,Broken(),retry_failed=False);value=body();jobs.submit(value)
            self.assertEqual(self.wait(jobs,value["requestID"])["status"],"failed")
            self.assertEqual(jobs.submit(value)["status"],"failed")
            self.assertEqual(len(calls),1)

    def test_interrupted_job_after_server_restart_requires_explicit_new_request(self):
        class Resolver:
            def resolve(self,b):return dict(ok=True)
        with tempfile.TemporaryDirectory() as directory:
            jobs=Jobs(directory,Resolver(),retry_failed=False);value=body();jobs.submit(value);self.wait(jobs,value["requestID"])
            with jobs.connection() as db:db.execute("UPDATE jobs SET state='running',result=NULL")
            restarted=Jobs(directory,Resolver(),retry_failed=False)
            self.assertEqual(restarted.submit(value)["status"],"interrupted")

    def test_authenticated_order_http_polls_cached_answer_and_rejects_changed_input(self):
        calls=[]
        class Resolver:
            def resolve(self,b):calls.append(b);return dict(orderedIDs=[p["id"] for p in b["places"]])
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ,POCKET_READ_TOKEN="synthetic-private-test-token"):
            jobs=Jobs(directory,Resolver(),retry_failed=False)
            server=ThreadingHTTPServer(("127.0.0.1",0),Handler);server.order_jobs=jobs
            thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
            try:
                base="http://127.0.0.1:"+str(server.server_port); value=body()
                headers={"Authorization":"Bearer synthetic-private-test-token","Content-Type":"application/json"}
                with self.assertRaises(HTTPError) as error:
                    urlopen(Request(base+"/v1/order",data=json.dumps(value).encode(),headers={"Content-Type":"application/json"}))
                self.assertEqual(error.exception.code,401)
                def post(v):return urlopen(Request(base+"/v1/order",data=json.dumps(v).encode(),headers=headers))
                with post(value) as response:self.assertEqual(response.status,202)
                self.wait(jobs,value["requestID"])
                with urlopen(Request(base+"/v1/order/jobs/"+value["requestID"],headers=headers)) as response:
                    self.assertEqual(json.load(response)["status"],"succeeded")
                with post(value) as response:self.assertEqual(json.load(response)["status"],"succeeded")
                self.assertEqual(len(calls),1)
                value["preferences"]+=" changed"
                with self.assertRaises(HTTPError) as error:post(value)
                self.assertEqual(error.exception.code,422)
            finally:server.shutdown();server.server_close();thread.join()

    def wait(self,jobs,ident):
        for _ in range(300):
            value=jobs.get(ident)
            if value["status"] not in {"running","queued"}:return value
            time.sleep(0.01)
        self.fail("Synthetic job did not finish")


if __name__=="__main__":unittest.main()
