"""Approved shared-homelab acceptance checks; never run automatically in CI."""

import argparse
import base64
import json
from pathlib import Path
import secrets
import ssl
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.request import HTTPSHandler, ProxyHandler, Request, build_opener
from uuid import UUID, uuid4

from dotenv import dotenv_values
from pip._vendor import certifi

from test_local_api import CheckFailure, LocalAPI, NoRedirects, ROOT, require


ORIGIN = "https://supabase.mrt.qzz.io"


class HomelabAPI(LocalAPI):
    def __init__(self):
        path = ROOT / "server/.env.local"
        require(path.stat().st_mode & 0o777 == 0o600, "Shared env file must have permission 600")
        values = dotenv_values(path, interpolate=False)
        require(values.get("SUPABASE_URL", "").rstrip("/") == ORIGIN,
                "Refusing an unexpected shared origin")
        self.client_key = values.get("SUPABASE_ANON_KEY", "")
        self.server_key = values.get("SUPABASE_SERVICE_ROLE_KEY", "")
        for key, role in [(self.client_key, "anon"), (self.server_key, "service_role")]:
            try:
                part = key.split(".")[1]
                payload = json.loads(base64.urlsafe_b64decode(part + "=" * (-len(part) % 4)))
                require(payload.get("role") == role and payload.get("exp", 0) > time.time(),
                        "Unexpected or expired legacy key")
            except (IndexError, ValueError, UnicodeError):
                raise CheckFailure("Invalid shared legacy key structure") from None
        self.user_ids, self.draft_id, self.passed = [], None, 0
        self.context = ssl.create_default_context(cafile=certifi.where())
        self.baseline_ids = self.account_ids()
        require(len(self.baseline_ids) == 1, "Auth baseline changed; re-review the shared preflight")
        spec = self.expect(self.request("GET", "/rest/v1/", admin=True), 200)
        require(all("/rpc/" + name in spec.get("paths", {})
                    for name in ["list_rundowns", "get_rundown", "create_trip"]),
                "Required shared RPCs are not available")

    def request(self, method, path, body=None, token=None, admin=False, key=True):
        require(path.startswith("/") and not path.startswith("//"), "Invalid API path")
        headers = {"Content-Type": "application/json", "User-Agent": "C67-Approved-Verification/1.0"}
        if key:
            headers["apikey"] = self.server_key if admin else self.client_key
        if admin:
            headers["Authorization"] = "Bearer " + self.server_key
        elif token:
            headers["Authorization"] = "Bearer " + token
        elif key:
            headers["Authorization"] = "Bearer " + self.client_key
        request = Request(ORIGIN + path, headers=headers, method=method,
                          data=None if body is None else json.dumps(body).encode())
        try:
            opener = build_opener(ProxyHandler({}), NoRedirects(), HTTPSHandler(context=self.context))
            with opener.open(request, timeout=25) as response:
                status, content = response.status, response.read()
        except HTTPError as error:
            status, content = error.code, error.read()
        except (URLError, TimeoutError):
            raise CheckFailure("Homelab connection/TLS failed; sensitive details suppressed") from None
        try:
            return status, json.loads(content) if content else None
        except (ValueError, UnicodeError):
            if status >= 400:
                return status, None
            raise CheckFailure(f"Homelab returned non-JSON HTTP {status}") from None

    def error(self, response, status, code=None):
        if code is None:
            # Envoy may reject missing/invalid credentials before PostgREST,
            # using a plain-text body. Verify the HTTP status at this boundary.
            self.expect(response, status)
        else:
            super().error(response, status, code)

    def account_ids(self):
        body = self.expect(self.request("GET", "/auth/v1/admin/users?page=1&per_page=50", admin=True), 200)
        users = body.get("users")
        require(isinstance(users, list) and len(users) < 50,
                "Unexpected account-list size; re-review the shared preflight")
        return {user["id"] for user in users}

    def login(self, label):
        email = f"c67-homelab-check-{label}-{uuid4().hex}@example.invalid"
        password = secrets.token_urlsafe(32)
        status, user = self.request("POST", "/auth/v1/admin/users", {
            "email": email, "password": password, "email_confirm": True,
        }, admin=True)
        require(status in [200, 201] and isinstance(user, dict), "Temporary Auth provisioning failed")
        user_id = user.get("id")
        require(bool(user_id), "Temporary Auth response lacks an identity")
        UUID(user_id)
        require(user_id not in self.baseline_ids, "Refusing to touch a baseline Auth identity")
        self.user_ids.append(user_id)
        session = self.expect(self.request("POST", "/auth/v1/token?grant_type=password", {
            "email": email, "password": password,
        }), 200)
        require(session.get("user", {}).get("id") == user_id and session.get("access_token"),
                "Temporary password session identity mismatch")
        self.passed_check(f"Account {label.upper()} is provisioned without email and obtains a password session")
        return session

    def passed_check(self, name):
        super().passed_check(name.replace("Local Auth", "Homelab Auth"))

    def cleanup(self):
        super().cleanup()
        require(self.account_ids() == self.baseline_ids, "Existing Auth account set changed")
        self.passed_check("Existing Auth account is preserved and no extra account remains")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--approved-shared-test", action="store_true",
                        help="Run only after the human approves the concrete homelab execution plan")
    args = parser.parse_args()
    if not args.approved_shared_test:
        parser.error("Explicit --approved-shared-test is required; this creates temporary shared data")
    api, failed = None, False
    try:
        api = HomelabAPI()
        api.run()
    except CheckFailure as error:
        print(f"FAIL: {error}", file=sys.stderr)
        failed = True
    except Exception as error:
        print(f"FAIL: {type(error).__name__}; sensitive details suppressed", file=sys.stderr)
        failed = True
    finally:
        if api is not None:
            try:
                api.cleanup()
            except Exception:
                print("FAIL: shared cleanup/preservation could not be verified", file=sys.stderr)
                failed = True
    if not failed:
        print(f"PASS: {api.passed} shared HTTP checks; temporary records removed; existing account preserved")
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
