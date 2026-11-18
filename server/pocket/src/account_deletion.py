"""Authenticated account deletion with a private, retryable completion receipt."""
import base64
from contextlib import closing
import hashlib
import json
import logging
import os
from pathlib import Path
import sqlite3
import threading
import time
from urllib.parse import quote
import uuid

import httpx
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature


class DeletionRejection(Exception):
    def __init__(self, status, code):
        self.status = status
        self.code = code


def fingerprint(value):
    return hashlib.sha256(value.encode()).hexdigest()


def base64url(value):
    return base64.urlsafe_b64encode(value).decode().rstrip("=")


class AccountDeletionProviders:
    def __init__(self, base_url, service_key):
        self.base_url = base_url
        self.admin_headers = {"apikey": service_key, "Authorization": "Bearer " + service_key}

    def admin(self, method, path, **kwargs):
        return httpx.request(method, self.base_url + path, headers=self.admin_headers,
                             timeout=15, follow_redirects=False, **kwargs)

    def apple_subjects(self, user):
        identities = user.get("identities") or []
        apple = [entry for entry in identities if entry.get("provider") == "apple"]
        providers = user.get("app_metadata") or {}
        is_apple = apple or providers.get("provider") == "apple" or "apple" in (providers.get("providers") or [])
        if not is_apple:
            return set()
        subjects = {(entry.get("identity_data") or {}).get("sub") for entry in apple}
        if len(subjects) != 1 or not next(iter(subjects)):
            raise DeletionRejection(503, "DELETION_UNAVAILABLE")
        return subjects

    def apple_client(self):
        try:
            team = os.environ["APPLE_TEAM_ID"]
            client = os.environ["POCKET_APPLE_SIGN_IN_CLIENT_ID"]
            key_id = os.environ["POCKET_APPLE_SIGN_IN_KEY_ID"]
            private_key = os.environ["POCKET_APPLE_SIGN_IN_PRIVATE_KEY"].replace("\\n", "\n")
            key = serialization.load_pem_private_key(private_key.encode(), password=None)
            if not isinstance(key, ec.EllipticCurvePrivateKey) or not isinstance(key.curve, ec.SECP256R1):
                raise ValueError("Expected the Sign in with Apple P-256 key")
            now = int(time.time())
            header = {"alg": "ES256", "kid": key_id}
            claims = {"iss": team, "iat": now, "exp": now + 300, "aud": "https://appleid.apple.com", "sub": client}
            signing_input = ".".join(base64url(json.dumps(part).encode()) for part in (header, claims))
            r, s = decode_dss_signature(key.sign(signing_input.encode(), ec.ECDSA(hashes.SHA256())))
            signature = base64url(r.to_bytes(32, "big") + s.to_bytes(32, "big"))
            return {"client_id": client, "client_secret": signing_input + "." + signature}
        except (KeyError, ValueError, TypeError):
            raise DeletionRejection(503, "DELETION_UNAVAILABLE") from None

    def revoke_apple(self, user, code):
        subjects = self.apple_subjects(user)
        if not subjects:
            if code:
                raise DeletionRejection(409, "APPLE_ACCOUNT_MISMATCH")
            return
        apple = self.apple_client()
        if not code:
            raise DeletionRejection(409, "APPLE_VERIFICATION_REQUIRED")
        response = httpx.post("https://appleid.apple.com/auth/token",
                              data={**apple, "grant_type": "authorization_code", "code": code},
                              timeout=15, follow_redirects=False)
        if response.status_code == 400 and response.json().get("error") == "invalid_grant":
            raise DeletionRejection(409, "APPLE_VERIFICATION_REQUIRED")
        response.raise_for_status()
        tokens = response.json()
        # Apple issued this token in the authenticated HTTPS code exchange above.
        payload = tokens["id_token"].split(".")[1]
        identity = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
        if (identity.get("iss") != "https://appleid.apple.com" or identity.get("aud") != apple["client_id"]
                or identity.get("sub") not in subjects):
            raise DeletionRejection(409, "APPLE_ACCOUNT_MISMATCH")
        refresh = tokens.get("refresh_token")
        token = refresh or tokens.get("access_token")
        if not token:
            raise DeletionRejection(503, "DELETION_UNAVAILABLE")
        httpx.post("https://appleid.apple.com/auth/revoke",
                   data={**apple, "token": token, "token_type_hint": "refresh_token" if refresh else "access_token"},
                   timeout=15, follow_redirects=False).raise_for_status()

    def purge_storage(self, owner):
        manifest = self.admin("POST", "/rest/v1/rpc/account_deletion_objects", json={"p_owner": owner})
        manifest.raise_for_status()
        objects = manifest.json()
        if objects is None:
            return False  # A journal job is still using its current lease.
        if not objects:
            return True
        buckets = {}
        for item in objects:
            buckets.setdefault(item["bucket_id"], []).append(item["name"])
        for bucket, names in buckets.items():
            self.admin("DELETE", "/storage/v1/object/" + quote(bucket, safe=""), json={"prefixes": names}).raise_for_status()
        return False  # Verify the next batch or confirm the manifest is empty.

    def delete_auth_user(self, owner):
        path = "/auth/v1/admin/users/" + owner
        result = self.admin("DELETE", path, json={"should_soft_delete": False})
        if result.status_code == 404 and result.json().get("error_code") == "user_not_found":
            return
        result.raise_for_status()


class AccountDeletions:
    def __init__(self, path, providers, job_stores):
        self.path = path
        self.providers = providers
        self.job_stores = job_stores
        self.submission_lock = threading.Lock()
        self.wake = threading.Event()
        self.stop = threading.Event()
        with self.connect() as db, db:
            db.execute("""CREATE TABLE IF NOT EXISTS deletions (
                receipt TEXT PRIMARY KEY, owner TEXT, owner_hash TEXT UNIQUE,
                updated INTEGER NOT NULL)""")

    def connect(self):
        return closing(sqlite3.connect(self.path, timeout=10))

    def state(self, receipt):
        with self.connect() as db:
            row = db.execute("SELECT owner FROM deletions WHERE receipt=?", (receipt,)).fetchone()
        return None if row is None else ("pending" if row[0] else "deleted")

    def blocks_jobs(self, owner):
        if owner == "legacy":
            return False
        with self.connect() as db:
            return db.execute("SELECT 1 FROM deletions WHERE owner_hash=?", (fingerprint(owner),)).fetchone() is not None

    def submit(self, body, authenticate):
        if not isinstance(body, dict) or not set(body) <= {"requestID", "appleAuthorizationCode"}:
            raise ValueError("Invalid deletion request")
        request = uuid.UUID(body["requestID"])
        code = body.get("appleAuthorizationCode")
        if request.version != 4 or (code is not None and (not isinstance(code, str) or not 1 <= len(code) <= 2048)):
            raise ValueError("Invalid deletion request")
        receipt = fingerprint(str(request))
        state = self.state(receipt)
        if state:
            self.wake.set()
            return state
        with self.submission_lock:
            if (state := self.state(receipt)) is not None:
                return state
            user = authenticate()
            if not user:
                raise DeletionRejection(401, "AUTHENTICATION_REQUIRED")
            owner = str(uuid.UUID(user["id"]))
            if self.blocks_jobs(owner):
                raise DeletionRejection(409, "DELETION_IN_PROGRESS")
            self.providers.revoke_apple(user, code)
            with self.connect() as db, db:
                db.execute("INSERT INTO deletions VALUES (?,?,?,?)",
                           (receipt, owner, fingerprint(owner), int(time.time())))
            self.wake.set()
            return "pending"

    def process(self):
        with self.connect() as db, db:
            # Retain only the anonymous receipt hash after the grace window for in-flight submissions.
            db.execute("UPDATE deletions SET owner_hash=NULL WHERE owner IS NULL AND owner_hash IS NOT NULL AND updated < ?",
                       (int(time.time()) - 86400,))
            active = db.execute("SELECT receipt, owner FROM deletions WHERE owner IS NOT NULL").fetchall()
        for receipt, owner in active:
            try:
                if not all(jobs.purge_owner(owner) for jobs in self.job_stores):
                    continue
                if not self.providers.purge_storage(owner):
                    continue
                self.providers.delete_auth_user(owner)
                with self.connect() as db, db:
                    db.execute("UPDATE deletions SET owner=NULL,updated=? WHERE receipt=?", (int(time.time()), receipt))
            except (OSError, sqlite3.Error, httpx.HTTPError, ValueError, KeyError, TypeError) as error:
                # Never emit identities, storage paths or upstream errors carrying credentials.
                logging.warning("account_deletion_retry kind=%s", type(error).__name__)

    def run(self):
        while not self.stop.is_set():
            self.wake.clear()
            try:
                self.process()
            except sqlite3.Error:
                logging.warning("account_deletion_storage_unavailable")
            self.wake.wait(timeout=15)
