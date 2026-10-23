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
                self.expect(self.request("DELETE", path, admin=True), 204)
                require(self.expect(self.request("GET", path, admin=True), 200) == [],
                        "Temporary draft was not cleaned up")
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
