"""Ordering acceptance boundaries. Synthetic responses; no provider calls."""
import copy
import json
import os
import sqlite3
import threading
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request, urlopen
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import time
import unittest
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
from ordering import Environment, OrderingResolver, request_context, candidate_orders
from server import AuthenticationUnavailable, Jobs, Handler, ThreadingHTTPServer


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
    def test_v4_preserves_unrestricted_luna_semantic_enrichment(self):
        request = body()
        request["orderingMethod"] = "hybrid_v4"
        observed = {}

        def model(prompt, context):
            observed.update(context)
            return answer(context), "gpt-6-luna"

        result = OrderingResolver(model, environment=NoWeather()).resolve(request)
        self.assertEqual(result["orderingMethod"], "hybrid_v4")
        self.assertNotIn("candidateOrders", observed)
        self.assertEqual(set(result["orderedIDs"]), {place["id"] for place in request["places"]})

    def test_user_token_is_verified_with_auth_service(self):
        user = str(uuid.uuid4())
        handler = SimpleNamespace(headers={"Authorization": "Bearer synthetic-user-token"})
        config = {"POCKET_AUTH_MODE": "authenticated", "SUPABASE_URL": "https://auth.example.test", "SUPABASE_CLIENT_KEY": "synthetic-publishable"}
        response = SimpleNamespace(status_code=200, json=lambda: {"id": user})
        with patch.dict(os.environ, config, clear=True), patch("server.httpx.get", return_value=response) as request:
            self.assertEqual(Handler.authorized(handler), user)
            self.assertEqual(request.call_args.kwargs["headers"]["Authorization"], "Bearer synthetic-user-token")
            response.status_code = 401
            self.assertIsNone(Handler.authorized(handler))
            response.status_code = 503
            with self.assertRaises(AuthenticationUnavailable): Handler.authorized(handler)

    def test_jobs_are_private_to_the_authenticated_owner(self):
        class Resolver:
            def resolve(self, value): return {"synthetic": True}
        with tempfile.TemporaryDirectory() as directory:
            jobs = Jobs(directory, Resolver(), retry_failed=False)
            value = body()
            jobs.submit(value, "user-a")
            with self.assertRaises(KeyError): jobs.get(value["requestID"], "user-b")
            with self.assertRaises(KeyError): jobs.submit(value, "user-b")
            self.assertEqual(jobs.get(value["requestID"], "user-a")["id"], value["requestID"])

    def test_legacy_job_migration_preserves_record_without_exposing_it_to_new_users(self):
        class Resolver:
            def resolve(self, value): return {"synthetic": True}
        with tempfile.TemporaryDirectory() as directory:
            value = body()
            with sqlite3.connect(str(Path(directory) / "resolution.sqlite")) as db:
                db.execute("CREATE TABLE jobs (id TEXT PRIMARY KEY, fingerprint TEXT, state TEXT, request TEXT, result TEXT)")
                db.execute("INSERT INTO jobs VALUES (?,?,?,?,?)", (value["requestID"], "old", "succeeded", "{}", '{"synthetic":true}'))
            jobs = Jobs(directory, Resolver(), retry_failed=False)
            self.assertEqual(jobs.get(value["requestID"])["status"], "succeeded")
            with self.assertRaises(KeyError): jobs.get(value["requestID"], "user-a")

    def test_authenticated_http_does_not_expose_other_users_job(self):
        class Resolver:
            def resolve(self, value): return {"synthetic": True}
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, POCKET_AUTH_MODE="authenticated"), \
             patch.object(Handler, "authorized", lambda handler: handler.headers.get("Authorization", "").removeprefix("Bearer ") or None):
            jobs = Jobs(directory, Resolver(), retry_failed=False)
            server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
            server.order_jobs = jobs
            thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
            try:
                base = f"http://127.0.0.1:{server.server_address[1]}"
                value = body()
                a = {"Authorization": "Bearer user-a", "Content-Type": "application/json"}
                b = {"Authorization": "Bearer user-b", "Content-Type": "application/json"}
                with urlopen(Request(base + "/v1/order", data=json.dumps(value).encode(), headers=a)) as response:
                    self.assertEqual(response.status, 202)
                with self.assertRaises(HTTPError) as error:
                    urlopen(Request(base + "/v1/order/jobs/" + value["requestID"], headers=b))
                self.assertEqual(error.exception.code, 404)
                with self.assertRaises(HTTPError):
                    urlopen(Request(base + "/v1/order", data=json.dumps(value).encode(), headers=b))
            finally:
                server.shutdown(); server.server_close(); thread.join()

    def test_weather_prefers_apple_and_falls_back_on_failure(self):
        environment = Environment()
        with patch.object(environment, "_apple", return_value=[{"source": "Apple Weather"}]) as apple, \
             patch.object(environment, "_open_meteo") as fallback:
            self.assertEqual(environment.read([], "2026-11-15", "Asia/Jakarta")[0]["source"], "Apple Weather")
            apple.assert_called_once()
            fallback.assert_not_called()
        with patch.object(environment, "_apple", side_effect=ValueError("unavailable")), \
             patch.object(environment, "_open_meteo", return_value=[{"source": "Open-Meteo"}]) as fallback:
            self.assertEqual(environment.read([], "2026-11-15", "Asia/Jakarta")[0]["source"], "Open-Meteo")
            fallback.assert_called_once()

    def test_apple_weather_binds_hours_and_attribution_to_the_selected_place(self):
        import base64
        from cryptography.hazmat.primitives import hashes
        from cryptography.hazmat.primitives import serialization
        from cryptography.hazmat.primitives.asymmetric import ec
        from cryptography.hazmat.primitives.asymmetric.utils import encode_dss_signature
        signing_key = ec.generate_private_key(ec.SECP256R1())
        key = signing_key.private_bytes(
            serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()).decode()
        env = dict(APPLE_TEAM_ID="TEAMTEST01", APPLE_WEATHER_SERVICE_ID="example.weather",
                   APPLE_WEATHER_KEY_ID="KEYTEST001", APPLE_WEATHER_PRIVATE_KEY=key)
        class Response:
            def __init__(self, value): self.value = value
            def raise_for_status(self): pass
            def json(self): return self.value
        class Client:
            def __init__(self, **kwargs):
                token = kwargs["headers"]["Authorization"].removeprefix("Bearer ")
                header, payload, signature = token.split(".")
                def decode(value): return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))
                self.claims = json.loads(decode(payload))
                raw = decode(signature)
                signing_key.public_key().verify(encode_dss_signature(int.from_bytes(raw[:32], "big"), int.from_bytes(raw[32:], "big")),
                                                f"{header}.{payload}".encode(), ec.ECDSA(hashes.SHA256()))
                assert self.claims["sub"] == "example.weather"
            def __enter__(self): return self
            def __exit__(self, *args): pass
            def get(self, url, **kwargs):
                if "/attribution/" in url: return Response({"logoLight@2x": "/assets/mark.png"})
                return Response({"forecastHourly": {"hours": [{"forecastStart": "2026-11-15T01:00:00Z",
                    "precipitationChance": 0.4, "precipitationAmount": 1.0, "precipitationType": "rain", "cloudCover": 0.5}]}})
        place = dict(id=str(uuid.uuid4()), coordinates=dict(latitude=-6.2, longitude=106.8))
        with patch.dict(os.environ, env, clear=True), patch("ordering.httpx.Client", Client):
            source = Environment().read([place], "2026-11-15", "Asia/Jakarta")[0]
        self.assertEqual(source["placeID"], place["id"])
        self.assertEqual(source["source"], "Apple Weather")
        self.assertEqual(source["attributionLogoURL"], "https://weatherkit.apple.com/assets/mark.png")
        self.assertEqual(source["hourlySamples"][0]["precipitationChance"], 0.4)
        self.assertEqual(source["hourlySamples"][0]["cloudCoverValidAt"], source["hourlySamples"][0]["start"])

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

    def test_hybrid_methods_select_only_offered_candidates_and_preserve_all_places(self):
        for method in ("hybrid_legacy", "hybrid_weather"):
            value = body(8); value["orderingMethod"] = method
            def model(prompt, context):
                self.assertIn("candidateOrders", context)
                if method == "hybrid_weather":
                    self.assertEqual(context["systemAssessment"]["activityExposure"], "unknown")
                    self.assertEqual(context["systemAssessment"]["arrivalTimes"], "unknown")
                result = answer(context)
                result["orderedIDs"] = context["candidateOrders"][-1]["orderedIDs"]
                return result, "gpt-6-luna"
            result = OrderingResolver(model, NoWeather()).resolve(value)
            self.assertEqual(result["orderingMethod"], method)
            self.assertEqual(set(result["orderedIDs"]), {p["id"] for p in value["places"]})
            if method == "hybrid_weather": self.assertTrue(any("unknown" in x for x in result["contextWarnings"]))

    def test_category_hints_are_unknown_only_for_weather_hybrid(self):
        value = body(); value['places'][0]['categories'] = ['MKPOICategoryMovieTheater']
        for method in ('luna', 'hybrid_legacy', 'hybrid_weather'):
            value['orderingMethod'] = method
            def model(prompt, context):
                hints = context.get('categoryHoursHints')
                if method == 'hybrid_weather':
                    self.assertEqual(hints[0]['endSecondsFromStartDay'], 93600)
                    self.assertEqual(hints[0]['venueHoursStatus'], 'unknown')
                    self.assertIn('never claim a venue is open or closed', prompt)
                else:
                    self.assertIsNone(hints)
                result = answer(context)
                if 'candidateOrders' in context:
                    result['orderedIDs'] = context['candidateOrders'][0]['orderedIDs']
                return result, 'gpt-6-luna'
            result = OrderingResolver(model, NoWeather()).resolve(value)
            self.assertEqual(set(result['orderedIDs']), {p['id'] for p in value['places']})

    def test_hybrid_rejects_unoffered_permutation(self):
        value = body(); value["orderingMethod"] = "hybrid_legacy"
        def model(prompt, context):
            result = answer(context)
            offered = [c["orderedIDs"] for c in context["candidateOrders"]]
            from itertools import permutations
            result["orderedIDs"] = next(list(x) for x in permutations(result["orderedIDs"]) if list(x) not in offered)
            return result, "gpt-6-luna"
        with self.assertRaisesRegex(ValueError, "offered candidate"):
            OrderingResolver(model, NoWeather()).resolve(value)

    def test_hybrid_candidates_preserve_locks_and_unknown_method_rejected(self):
        value = body(8); value["firstPlaceID"] = value["places"][-1]["id"]
        for candidate in candidate_orders(request_context(value)):
            self.assertEqual(candidate[0], value["firstPlaceID"])
            self.assertEqual(len(set(candidate)), 8)
        value["preservesPlaceOrder"] = True
        self.assertEqual(candidate_orders(request_context(value)), [[p["id"] for p in value["places"]]])
        value["orderingMethod"] = "invented"
        with self.assertRaises(ValueError): request_context(value)

    def test_all_methods_complete_through_local_http_job_with_synthetic_model(self):
        calls = []
        def model(prompt, context):
            calls.append(context)
            value = answer(context)
            if "candidateOrders" in context:
                value["orderedIDs"] = context["candidateOrders"][-1]["orderedIDs"]
            return value, "gpt-6-luna"
        with tempfile.TemporaryDirectory() as directory, patch.object(Handler, "authorized", return_value="synthetic-user"):
            jobs = Jobs(directory, OrderingResolver(model, NoWeather()), retry_failed=False)
            server = ThreadingHTTPServer(("127.0.0.1", 0), Handler); server.order_jobs = jobs
            thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
            try:
                base = f"http://127.0.0.1:{server.server_address[1]}"
                headers = {"Authorization": "Bearer synthetic", "Content-Type": "application/json"}
                for method in ("luna", "hybrid_legacy", "hybrid_weather", "hybrid_v4"):
                    value = body(); value["orderingMethod"] = method
                    with urlopen(Request(base + "/v1/order", data=json.dumps(value).encode(), headers=headers)) as response:
                        self.assertEqual(response.status, 202)
                    deadline = time.monotonic() + 5
                    result = jobs.get(value["requestID"], "synthetic-user")
                    while result["status"] in ("queued", "running") and time.monotonic() < deadline:
                        time.sleep(0.01)
                        result = jobs.get(value["requestID"], "synthetic-user")
                    self.assertEqual(result["status"], "succeeded", result)
                    self.assertEqual(result["result"]["orderingMethod"], method)
                    self.assertEqual(set(result["result"]["orderedIDs"]), {p["id"] for p in value["places"]})
                self.assertEqual(len(calls), 4)
            finally:
                server.shutdown(); server.server_close(); thread.join()

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
