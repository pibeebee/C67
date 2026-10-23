"""Exercise the C67 starter through local Auth, gateway and Data API HTTP calls.

Only the repository's c67-starter stack on 127.0.0.1:54321 is accepted.
Temporary users are created through signup/password login and removed in finally.
Keys, passwords, sessions and HTTP response bodies are never printed or saved.
"""

from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
import json
from pathlib import Path
import secrets
import subprocess
import sys
import tomllib
from urllib.error import HTTPError, URLError
from urllib.request import HTTPRedirectHandler, ProxyHandler, Request, build_opener
from uuid import UUID, uuid4


SERVER = Path(__file__).resolve().parents[1]
ROOT = SERVER.parent
BASE_URL = "http://127.0.0.1:54321"


class CheckFailure(Exception):
    """An intentionally sanitized diagnostic that can safely reach CI logs."""


def require(condition, message):
    if not condition:
        raise CheckFailure(message)


class NoRedirects(HTTPRedirectHandler):
    def redirect_request(self, request, file, code, message, headers, new_url):
        return None


class LocalAPI:
    def __init__(self):
        config = tomllib.loads((SERVER / "supabase/config.toml").read_text())
        require(config["project_id"] == "c67-starter", "Unexpected local project ID")
        require(config["api"]["port"] == 54321, "Unexpected local API port")
        require(not config["auth"]["email"]["enable_confirmations"],
                "Local email confirmation must be disabled for synthetic signup tests")
        cli = SERVER / "node_modules/.bin/supabase"
        require(cli.exists(), "Install pinned tooling with npm ci inside server/")
        result = subprocess.run([str(cli), "status", "--output", "json"], cwd=SERVER,
                                capture_output=True, text=True, timeout=30)
        require(result.returncode == 0, "Local status failed; start C67 with npm run start")
        settings = json.loads(result.stdout)
        require(settings.get("API_URL") == BASE_URL, "Refusing a non-C67 or non-loopback API")
        self.client_key = settings["ANON_KEY"]
        self.server_key = settings["SERVICE_ROLE_KEY"]
        self.user_ids = []
        self.draft_id = None
        self.passed = 0

    def request(self, method, path, body=None, token=None, admin=False, key=True):
        require(path.startswith("/") and not path.startswith("//"), "Invalid local API path")
        headers = {"Content-Type": "application/json"}
        if key:
            headers["apikey"] = self.server_key if admin else self.client_key
        if admin:
            headers["Authorization"] = "Bearer " + self.server_key
        elif token:
            headers["Authorization"] = "Bearer " + token
        payload = None if body is None else json.dumps(body).encode()
        request = Request(BASE_URL + path, data=payload, headers=headers, method=method)
        # Ignore proxy environment variables and reject redirects to another origin.
        opener = build_opener(ProxyHandler({}), NoRedirects())
        try:
            with opener.open(request, timeout=20) as response:
                status, content = response.status, response.read()
        except HTTPError as error:
            status, content = error.code, error.read()
        except (URLError, TimeoutError):
            raise CheckFailure("Local HTTP connection failed or timed out") from None
        try:
            return status, json.loads(content) if content else None
        except (ValueError, UnicodeError):
            raise CheckFailure("Local API returned a non-JSON response") from None

    def expect(self, response, status):
        actual, body = response
        require(actual == status, f"Expected HTTP {status}, received HTTP {actual}")
        return body

    def error(self, response, status, code=None):
        body = self.expect(response, status)
        require(isinstance(body, dict), "Expected a structured error")
        if code is not None:
            require(body.get("code") == code, "Unexpected PostgREST error code")
            require({"code", "message", "details", "hint"} <= body.keys(),
                    "PostgREST error does not match the starter contract")

    def passed_check(self, name):
        self.passed += 1
        print(f"PASS {self.passed:02}: {name}", flush=True)

    def login(self, label):
        email = f"c67-local-{label}-{uuid4().hex}@example.invalid"
        password = secrets.token_urlsafe(32)
        response = self.request("POST", "/auth/v1/signup", {"email": email, "password": password})
        status, body = response
        user_id = body.get("user", {}).get("id") if isinstance(body, dict) else None
        if status == 200 and user_id:
            UUID(user_id)
            self.user_ids.append(user_id)
        self.expect(response, 200)
        require(bool(user_id), "Synthetic signup did not create a user")
        session = self.expect(self.request("POST", "/auth/v1/token?grant_type=password",
                                          {"email": email, "password": password}), 200)
        require(session.get("user", {}).get("id") == user_id, "Password login identity mismatch")
        require(bool(session.get("access_token")), "Password login did not create a session")
        self.passed_check(f"Account {label.upper()} signs up and obtains a real password session")
        return session

    def trip_rows(self, trip_id, token):
        return self.request("GET", f"/rest/v1/trips?id=eq.{trip_id}&select=*", token=token)

    def check_trip(self, trip, source, starts_at):
        require(set(trip) == {"id", "source_version_id", "title", "starts_at", "stops"},
                "Trip fields differ from the RPC contract")
        UUID(trip["id"])
        require(trip["source_version_id"] == source["id"], "Source version mismatch")
        require(trip["title"] == source["title"] and trip["stops"] == source["stops"],
                "Trip is not a copy of the selected source snapshot")
        require(datetime.fromisoformat(trip["starts_at"].replace("Z", "+00:00")) ==
                datetime.fromisoformat(starts_at.replace("Z", "+00:00")), "Trip instant changed")

    def run(self):
        fixture = json.loads((ROOT / "contracts/fixtures/rundowns.json").read_text())
        source = fixture[0]
        starts_at = "2026-11-01T09:00:00+07:00"
        command = {"p_version_id": source["id"], "p_starts_at": starts_at,
                   "p_request_id": str(uuid4())}
        create_path = "/rest/v1/rpc/create_trip"

        self.expect(self.request("GET", "/auth/v1/health"), 200)
        self.passed_check("Local Auth is healthy")
        self.error(self.request("POST", create_path, command, key=False), 401)
        self.passed_check("A private trip command without client credentials or session is rejected")
        catalog = self.expect(self.request("POST", "/rest/v1/rpc/list_rundowns", {}), 200)
        require(sorted(catalog, key=lambda item: item["id"]) ==
                sorted(fixture, key=lambda item: item["id"]), "Seed/catalog differs from fixture")
        self.passed_check("Anonymous catalog matches the authoritative synthetic seed")
        detail = self.expect(self.request("POST", "/rest/v1/rpc/get_rundown",
                                          {"p_version_id": source["id"]}), 200)
        require(detail == source, "Rundown detail differs from fixture")
        self.passed_check("Published detail matches the contract fixture")
        self.error(self.request("POST", "/rest/v1/rpc/get_rundown",
                                {"p_version_id": str(uuid4())}), 404, "PT404")
        self.passed_check("Unknown version returns the contracted 404")
        self.error(self.request("POST", create_path, command), 401, "42501")
        self.passed_check("Client key alone cannot create a private trip")
        self.error(self.request("POST", create_path, command, token="invalid-session"), 401)
        self.passed_check("A malformed traveller token is rejected")

        session_a, session_b = self.login("a"), self.login("b")
        token_a, token_b = session_a["access_token"], session_b["access_token"]
        require(self.user_ids[0] != self.user_ids[1], "Test accounts must be distinct")
        empty_page = self.expect(self.request("POST", "/rest/v1/rpc/list_my_trips", {}, token=token_b), 200)
        require(empty_page == {"items": [], "next_cursor": None}, "Empty owner list differs from contract")
        self.passed_check("An account without trips receives an empty final page")
        trip_a = self.expect(self.request("POST", create_path, command, token=token_a), 200)
        self.check_trip(trip_a, source, starts_at)
        self.passed_check("Account A creates a contract-compatible snapshot with its selected instant")
        retry = self.expect(self.request("POST", create_path, command, token=token_a), 200)
        require(retry == trip_a, "Identical retry did not return the original trip")
        self.passed_check("Identical retry returns the same trip")
        equivalent = {**command, "p_starts_at": "2026-11-01T02:00:00Z"}
        require(self.expect(self.request("POST", create_path, equivalent, token=token_a), 200) == trip_a,
                "Equivalent timestamp offset changed retry identity")
        self.passed_check("Equivalent UTC/offset timestamps preserve retry identity")
        changed = {**command, "p_starts_at": "2026-11-02T02:00:00Z"}
        self.error(self.request("POST", create_path, changed, token=token_a), 409, "PT409")
        self.passed_check("Reused request ID with changed input returns 409")
        invalid = {**command, "p_request_id": str(uuid4()), "p_starts_at": None}
        self.error(self.request("POST", create_path, invalid, token=token_a), 400, "PT400")
        self.passed_check("Missing business input returns the contracted 400")
        missing = {**command, "p_request_id": str(uuid4()), "p_version_id": str(uuid4())}
        self.error(self.request("POST", create_path, missing, token=token_a), 404, "PT404")
        self.passed_check("A missing source cannot create a trip")

        rows_a = self.expect(self.trip_rows(trip_a["id"], token_a), 200)
        require(len(rows_a) == 1 and rows_a[0]["owner_id"] == self.user_ids[0],
                "Trip ownership did not come from account A's verified session")
        self.passed_check("Direct Data API read returns the owner's persisted trip")
        require(self.expect(self.trip_rows(trip_a["id"], token_b), 200) == [],
                "Account B can read account A's trip")
        self.passed_check("RLS hides account A's trip from account B")
        self.error(self.request("GET", "/rest/v1/trips?select=id"), 401, "42501")
        self.passed_check("Anonymous direct trip reads are rejected")
        trip_b = self.expect(self.request("POST", create_path, command, token=token_b), 200)
        require(trip_b["id"] != trip_a["id"], "Request ID was not scoped to its owner")
        require(self.expect(self.trip_rows(trip_b["id"], token_a), 200) == [],
                "Account A can read account B's trip")
        self.passed_check("Request IDs are owner-scoped and isolation works in both directions")

        direct = {"owner_id": self.user_ids[1], "source_version_id": source["id"],
                  "title": source["title"], "starts_at": starts_at,
                  "stops": source["stops"], "request_id": str(uuid4())}
        self.error(self.request("POST", "/rest/v1/trips", direct, token=token_a), 403, "42501")
        self.passed_check("Direct insert cannot forge another owner")
        self.error(self.request("PATCH", f"/rest/v1/trips?id=eq.{trip_a['id']}",
                                {"title": "Forbidden"}, token=token_a), 403, "42501")
        self.error(self.request("DELETE", f"/rest/v1/trips?id=eq.{trip_a['id']}", token=token_a),
                   403, "42501")
        self.passed_check("Direct update/delete cannot bypass trip commands")
        self.error(self.request("PATCH", f"/rest/v1/rundown_versions?id=eq.{source['id']}",
                                {"title": "Forbidden"}, token=token_a), 403, "42501")
        self.passed_check("A traveller cannot mutate published creator content directly")

        draft_id = str(uuid4())
        self.draft_id = draft_id
        self.expect(self.request("POST", "/rest/v1/rundown_versions", {
            "id": draft_id, "title": "Synthetic hidden draft", "area": "Local test",
            "summary": "Temporary HTTP fixture", "stops": [], "published": False,
        }, admin=True), 201)
        for token in (None, token_a, token_b):
            self.error(self.request("POST", "/rest/v1/rpc/get_rundown",
                                    {"p_version_id": draft_id}, token=token), 404, "PT404")
            hidden = self.expect(self.request("GET", f"/rest/v1/rundown_versions?id=eq.{draft_id}",
                                              token=token), 200)
            require(hidden == [], "Unpublished content leaked through direct Data API")
        self.passed_check("Drafts stay hidden through RPC and direct Data API for guest/A/B")
        draft_command = {**command, "p_request_id": str(uuid4()), "p_version_id": draft_id}
        self.error(self.request("POST", create_path, draft_command, token=token_a), 404, "PT404")
        self.passed_check("A definer RPC rejects an unpublished source")

        concurrent = {**command, "p_request_id": str(uuid4())}
        with ThreadPoolExecutor(max_workers=4) as pool:
            replies = list(pool.map(lambda _: self.request("POST", create_path, concurrent,
                                                          token=token_a), range(4)))
        results = [self.expect(reply, 200) for reply in replies]
        require(len({item["id"] for item in results}) == 1, "Concurrent retries duplicated a trip")
        rows = self.expect(self.trip_rows(results[0]["id"], token_a), 200)
        require(len(rows) == 1, "Concurrent retries did not persist exactly one trip")
        self.passed_check("Four concurrent retries commit one trip and return one identity")

        refreshed = self.expect(self.request("POST", "/auth/v1/token?grant_type=refresh_token",
                                            {"refresh_token": session_a["refresh_token"]}), 200)
        require(refreshed.get("user", {}).get("id") == self.user_ids[0], "Refresh changed identity")
        require(len(self.expect(self.trip_rows(trip_a["id"], refreshed["access_token"]), 200)) == 1,
                "Refreshed session cannot read the persisted owner trip")
        self.passed_check("A real refreshed session retains owner-scoped access")
        self.verify_trip_reads(refreshed["access_token"], token_b, trip_a, trip_b, source)
        self.verify_trip_model(refreshed["access_token"], token_b, trip_a, source)

    def verify_trip_reads(self, token_a, token_b, trip_a, trip_b, source):
        list_path = "/rest/v1/rpc/list_my_trips"
        detail_path = "/rest/v1/rpc/get_trip_snapshot"
        for path, body in [(list_path, {}), (detail_path, {"p_trip_id": trip_a["id"]})]:
            self.error(self.request("POST", path, body), 401, "42501")
        self.passed_check("Private list/detail require a real traveller session")

        saved = self.expect(self.request("POST", detail_path, {"p_trip_id": trip_a["id"]},
                                         token=token_a), 200)
        require(saved == trip_a, "Reloaded snapshot differs from the confirmed create response")
        self.passed_check("A separate detail request reloads the persisted snapshot")
        foreign = self.request("POST", detail_path, {"p_trip_id": trip_a["id"]}, token=token_b)
        missing = self.request("POST", detail_path, {"p_trip_id": str(uuid4())}, token=token_b)
        self.error(foreign, 404, "PT404")
        self.error(missing, 404, "PT404")
        require(foreign == missing, "Foreign and missing trip errors reveal different information")
        self.passed_check("Foreign and missing trip details return the same 404")

        for start in [trip_a["starts_at"], "2026-11-03T02:00:00Z"]:
            self.expect(self.request("POST", "/rest/v1/rpc/create_trip", {
                "p_version_id": source["id"], "p_starts_at": start, "p_request_id": str(uuid4()),
            }, token=token_a), 200)
        full = self.expect(self.request("POST", list_path, {}, token=token_a), 200)
        require(set(full) == {"items", "next_cursor"} and full["next_cursor"] is None,
                "Default page shape/final cursor does not match contract")
        require(len(full["items"]) == 4 and trip_b["id"] not in {t["id"] for t in full["items"]},
                "Owner list leaks another account or loses a confirmed trip")
        for item in full["items"]:
            self.check_trip(item, source, item["starts_at"])
        self.passed_check("Owner list returns complete contract snapshots without other accounts")

        cursor, all_items, first_cursor = None, [], None
        for page_index in range(10):
            body = {"p_limit": 1, "p_cursor": cursor}
            page = self.expect(self.request("POST", list_path, body, token=token_a), 200)
            require(set(page) == {"items", "next_cursor"} and len(page["items"]) <= 1,
                    "Page size/shape differs from contract")
            all_items.extend(page["items"])
            if page_index == 0:
                first_cursor = page["next_cursor"]
                require(bool(first_cursor), "A non-final page lacks a cursor")
                require(self.expect(self.request("POST", list_path, body, token=token_a), 200) == page,
                        "Repeating an unchanged page is unstable")
            cursor = page["next_cursor"]
            if cursor is None:
                break
        require(cursor is None, "Pagination failed to terminate")
        require(all_items == full["items"] and len({t["id"] for t in all_items}) == 4,
                "Keyset traversal duplicates, skips or reorders a trip")
        def order_key(item):
            return (datetime.fromisoformat(item["starts_at"].replace("Z", "+00:00")), item["id"])
        require(all_items == sorted(all_items, key=order_key, reverse=True),
                "List does not use the documented start/UUID descending order")
        self.passed_check("Keyset pages are stable across equal start times without gaps/duplicates")

        self.error(self.request("POST", list_path, {"p_cursor": first_cursor}, token=token_b),
                   400, "PT400")
        self.passed_check("Continuation cannot be reused after switching accounts")
        for value in [0, 101, None]:
            self.error(self.request("POST", list_path, {"p_limit": value}, token=token_a), 400, "PT400")
        self.passed_check("Invalid/null limits return 400")
        for value in ["!!!", "e30=", "/w==", "x" * 513]:
            self.error(self.request("POST", list_path, {"p_cursor": value}, token=token_a), 400, "PT400")
        self.passed_check("Malformed, incomplete, invalid-UTF8 and oversized cursors return 400")
        self.error(self.request("POST", detail_path, {"p_trip_id": None}, token=token_a), 400, "PT400")
        self.passed_check("Null trip IDs return 400")
        own_b = self.expect(self.request("POST", list_path, {}, token=token_b), 200)
        require(own_b == {"items": [trip_b], "next_cursor": None}, "Account B list is not isolated")
        self.passed_check("Account B list contains only its own snapshot")
        self.error(self.request("POST", "/rest/v1/rpc/create_trip", {
            "p_version_id": source["id"], "p_starts_at": "infinity", "p_request_id": str(uuid4()),
        }, token=token_a), 400, "23514")
        self.passed_check("Non-finite dates cannot create snapshots that break pagination")


    def verify_trip_model(self, token_a, token_b, trip_a, source):
        create_path, detail_path = "/rest/v1/rpc/create_trip_v2", "/rest/v1/rpc/get_trip_snapshot_v2"
        command = {"p_version_id": source["id"], "p_starts_at": "2026-10-31T16:00:00Z",
                   "p_time_zone": "Asia/Tokyo", "p_request_id": str(uuid4())}
        self.error(self.request("POST", create_path, command), 401, "42501")
        self.error(self.request("POST", detail_path, {"p_trip_id": trip_a["id"]}), 401, "42501")
        self.passed_check("V2 creation/detail require a traveller session")
        legacy = self.expect(self.request("POST", detail_path, {"p_trip_id": trip_a["id"]}, token=token_a), 200)
        require({key: legacy[key] for key in trip_a} == trip_a and legacy["time_zone"] is None
                and legacy["local_start_date"] is None and legacy["revision"] == 1,
                "Legacy snapshot was changed or assigned an invented destination zone")
        self.passed_check("V2 reads legacy snapshots with explicit unknown zone/date")
        version = self.expect(self.request("GET", f"/rest/v1/rundown_versions?id=eq.{source['id']}&select=rundown_id,version_no"), 200)[0]
        UUID(version["rundown_id"])
        created = self.expect(self.request("POST", create_path, command, token=token_a), 200)
        fields = {"id", "source_version_id", "title", "starts_at", "stops", "schema_version",
                  "source", "time_zone", "local_start_date", "revision", "status"}
        require(set(created) == fields, "V2 snapshot fields differ from contract")
        self.check_trip({key: created[key] for key in trip_a}, source, command["p_starts_at"])
        require(created["source"] == {"rundown_id": version["rundown_id"], "version_id": source["id"],
                                      "version_no": version["version_no"]}, "V2 source attribution differs")
        require(created["schema_version"] == 2 and created["revision"] == 1 and created["status"] == "planned"
                and created["time_zone"] == "Asia/Tokyo" and created["local_start_date"] == "2026-11-01",
                "V2 destination date/revision/state differs")
        self.passed_check("V2 creation stores source identity and destination date across UTC midnight")
        require(self.expect(self.request("POST", detail_path, {"p_trip_id": created["id"]}, token=token_a), 200)
                == created, "V2 reload differs from committed snapshot")
        self.passed_check("V2 snapshot reload preserves the complete committed model")
        equivalent = {**command, "p_starts_at": "2026-11-01T01:00:00+09:00"}
        require(self.expect(self.request("POST", create_path, equivalent, token=token_a), 200) == created,
                "V2 equivalent-instant retry changed snapshot/revision")
        self.error(self.request("POST", create_path, {**command, "p_time_zone": "UTC"}, token=token_a), 409, "PT409")
        self.passed_check("V2 retries preserve revision and changed zone returns conflict")
        old_command = {key: value for key, value in command.items() if key != "p_time_zone"}
        self.error(self.request("POST", "/rest/v1/rpc/create_trip", old_command, token=token_a), 409, "PT409")
        v1_collision = {**command, "p_starts_at": trip_a["starts_at"]}
        # Read this test trip's request ID administratively; never expose it in output.
        original = self.expect(self.request("GET", f"/rest/v1/trips?id=eq.{trip_a['id']}&select=request_id", admin=True), 200)[0]
        v1_collision["p_request_id"] = original["request_id"]
        self.error(self.request("POST", create_path, v1_collision, token=token_a), 409, "PT409")
        self.passed_check("V1/V2 commands cannot adopt each other's request IDs")
        foreign = self.request("POST", detail_path, {"p_trip_id": created["id"]}, token=token_b)
        missing = self.request("POST", detail_path, {"p_trip_id": str(uuid4())}, token=token_b)
        self.error(foreign, 404, "PT404")
        self.error(missing, 404, "PT404")
        require(foreign == missing, "V2 detail exposes foreign identity")
        self.passed_check("V2 foreign/missing details are indistinguishable")
        for zone in ["Asia/Invalid", "+07:00", "posix/Asia/Jakarta", "", None]:
            self.error(self.request("POST", create_path, {**command, "p_time_zone": zone,
                       "p_request_id": str(uuid4())}, token=token_a), 400, "PT400")
        self.passed_check("Unknown, offset-only, internal and missing zones are rejected")
        for instant in ["infinity", None, "10000-01-01T00:00:00Z"]:
            self.error(self.request("POST", create_path, {**command, "p_starts_at": instant,
                       "p_request_id": str(uuid4())}, token=token_a), 400, "PT400")
        self.passed_check("V2 rejects non-finite, missing and unsupported-range trip dates")
        west = self.expect(self.request("POST", create_path, {**command, "p_time_zone": "America/Los_Angeles",
                           "p_starts_at": "2026-11-01T02:00:00Z", "p_request_id": str(uuid4())}, token=token_a), 200)
        require(west["local_start_date"] == "2026-10-31", "Negative-offset destination date is wrong")
        self.passed_check("Destination date can precede the UTC calendar date")
        for instant in ["2026-03-08T06:30:00Z", "2026-03-08T07:30:00Z"]:
            dst = self.expect(self.request("POST", create_path, {**command, "p_time_zone": "America/New_York",
                              "p_starts_at": instant, "p_request_id": str(uuid4())}, token=token_a), 200)
            require(dst["local_start_date"] == "2026-03-08", "DST boundary shifted the destination date")
        self.passed_check("Explicit instants remain valid on both sides of a DST transition")
        concurrent = {**command, "p_request_id": str(uuid4())}
        with ThreadPoolExecutor(max_workers=4) as pool:
            responses = list(pool.map(lambda _: self.request("POST", create_path, concurrent, token=token_a), range(4)))
        snapshots = [self.expect(reply, 200) for reply in responses]
        require(all(item == snapshots[0] and item["revision"] == 1 for item in snapshots),
                "Concurrent V2 retries changed identity/model/revision")
        self.passed_check("Four concurrent V2 retries return one identical revision")
        self.error(self.request("POST", "/rest/v1/rundowns", {"id": str(uuid4())}, token=token_a), 403, "42501")
        self.error(self.request("PATCH", f"/rest/v1/trips?id=eq.{created['id']}", {"revision": 99}, token=token_a), 403, "42501")
        self.passed_check("Travellers cannot write root identities or forge revisions directly")
        self.error(self.request("POST", create_path, {**command, "p_version_id": self.draft_id,
                   "p_request_id": str(uuid4())}, token=token_a), 404, "PT404")
        draft = self.expect(self.request("GET", f"/rest/v1/rundown_versions?id=eq.{self.draft_id}&select=rundown_id", admin=True), 200)[0]
        require(self.expect(self.request("GET", f"/rest/v1/rundowns?id=eq.{draft['rundown_id']}"), 200) == [],
                "Draft-only root leaked to anonymous reads")
        self.passed_check("V2 creation and root reads preserve unpublished catalog privacy")
        other = self.expect(self.request("POST", create_path, command, token=token_b), 200)
        require(other["id"] != created["id"], "V2 request identity is not owner-scoped")
        self.passed_check("V2 request identity remains scoped to each account")

    def cleanup(self):
        errors = 0
        for user_id in reversed(self.user_ids):
            try:
                self.expect(self.request("DELETE", f"/auth/v1/admin/users/{user_id}", admin=True), 200)
                body = self.expect(self.request("GET", f"/auth/v1/admin/users/{user_id}", admin=True), 404)
                require(isinstance(body, dict), "Account cleanup could not be verified")
                rows = self.expect(self.request("GET", f"/rest/v1/trips?owner_id=eq.{user_id}",
                                                admin=True), 200)
                require(rows == [], "Temporary account trips were not cleaned up")
            except Exception:
                errors += 1
        if self.draft_id:
            try:
                path = f"/rest/v1/rundown_versions?id=eq.{self.draft_id}"
                draft_rows = self.expect(self.request("GET", path + "&select=rundown_id", admin=True), 200)
                require(len(draft_rows) == 1, "Temporary draft identity unavailable for cleanup")
                root_id = draft_rows[0]["rundown_id"]
                UUID(root_id)
                self.expect(self.request("DELETE", path, admin=True), 204)
                require(self.expect(self.request("GET", path, admin=True), 200) == [],
                        "Temporary draft was not cleaned up")
                require(self.expect(self.request("GET", f"/rest/v1/rundown_versions?rundown_id=eq.{root_id}&select=id", admin=True), 200) == [],
                        "Temporary root has unexpected additional versions; preserve it")
                root_path = f"/rest/v1/rundowns?id=eq.{root_id}"
                self.expect(self.request("DELETE", root_path, admin=True), 204)
                require(self.expect(self.request("GET", root_path, admin=True), 200) == [],
                        "Temporary root was not cleaned up")
            except Exception:
                errors += 1
        require(errors == 0, "Cleanup failed; inspect only this local stack's synthetic test records")
        self.passed_check("Temporary accounts, their trips and the draft are removed")


def main():
    api = None
    failed = False
    try:
        api = LocalAPI()
        api.run()
    except CheckFailure as error:
        print(f"FAIL: {error}", file=sys.stderr)
        failed = True
    except Exception as error:
        print(f"FAIL: local test runner encountered {type(error).__name__}; sensitive details suppressed",
              file=sys.stderr)
        failed = True
    finally:
        if api is not None:
            try:
                api.cleanup()
            except CheckFailure as error:
                print(f"FAIL: {error}", file=sys.stderr)
                failed = True
    if not failed:
        print(f"PASS: {api.passed} local HTTP checks; synthetic data only; no homelab requests")
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
