import base64
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import uuid

import httpx

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
from account_deletion import AccountDeletions, AccountDeletionProviders, DeletionRejection
from ordering import OrderingResolver
from resolution import Resolver
from server import Jobs


class Providers:
    def __init__(self):
        self.ready = False
        self.deleted = []
        self.revocations = []

    def revoke_apple(self, user, code):
        self.revocations.append((user["id"], code))

    def purge_storage(self, owner):
        return self.ready

    def delete_auth_user(self, owner):
        self.deleted.append(owner)


class AccountDeletionTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.providers = Providers()
        self.alice, self.bob = str(uuid.uuid4()), str(uuid.uuid4())

    def auth(self):
        return {"id": self.alice}

    def test_receipt_requires_authenticated_owner_to_start_and_survives_restart(self):
        path = self.root / "accounts.sqlite"
        service = AccountDeletions(path, self.providers, ())
        body = {"requestID": str(uuid.uuid4())}
        with self.assertRaises(DeletionRejection) as error:
            service.submit(body, lambda: None)
        self.assertEqual(error.exception.status, 401)
        with self.assertRaises(ValueError):
            service.submit({**body, "owner": self.bob}, self.auth)
        self.assertEqual(service.submit({**body, "appleAuthorizationCode": "synthetic-apple-code"}, self.auth), "pending")
        self.assertEqual(service.submit(body, lambda: None), "pending")
        with self.assertRaises(DeletionRejection) as error:
            service.submit({"requestID": str(uuid.uuid4())}, self.auth)
        self.assertEqual(error.exception.code, "DELETION_IN_PROGRESS")
        service.process()
        self.assertEqual(self.providers.deleted, [])

        self.providers.ready = True
        relaunched = AccountDeletions(path, self.providers, ())
        relaunched.process()
        relaunched.process()
        self.assertEqual(relaunched.submit(body, lambda: None), "deleted")
        self.assertEqual(self.providers.deleted, [self.alice])
        self.assertEqual(self.providers.revocations, [(self.alice, "synthetic-apple-code")])
        self.assertNotIn(b"synthetic-apple-code", path.read_bytes())

    def test_waits_for_running_job_and_removes_only_the_correct_owners_data(self):
        research = Resolver(self.root / "sources", None)
        ordering = OrderingResolver(None, snapshot_directory=self.root / "ordering-snapshots")
        ordering.snapshot_directory.mkdir()
        stores = [Jobs(self.root, research), Jobs(self.root / "orders", ordering)]
        service = AccountDeletions(self.root / "accounts.sqlite", self.providers, stores)
        order_ids = {}
        for owner in (self.alice, self.bob):
            research_directory = research.directory / owner
            research_directory.mkdir()
            (research_directory / "research.json").write_text("synthetic research")
            for store in stores:
                store.blocks_owner = service.blocks_jobs
                ident = str(uuid.uuid4())
                result = {}
                if store is stores[1]:
                    order_ids[owner] = ident
                    (ordering.snapshot_directory / (ident + ".json")).write_text("synthetic order")
                else:
                    snapshot = "a" * 64 if owner == self.alice else "b" * 64
                    (research.directory / (snapshot + ".json")).write_text("synthetic historic research")
                    result = {"records": [{"snapshotID": snapshot}]}
                with store.connection() as db:
                    db.execute("INSERT INTO jobs (id, fingerprint, state, request, result, owner) VALUES (?,?,?,?,?,?)",
                               (ident, "synthetic", "succeeded", "{}", json.dumps(result), owner))

        job_id = order_ids[self.alice]
        stores[1].active.add(job_id)
        body = {"requestID": str(uuid.uuid4())}
        self.providers.ready = True
        service.submit(body, self.auth)
        with self.assertRaises(DeletionRejection):
            stores[1].submit({"requestID": str(uuid.uuid4())}, self.alice)
        service.process()
        self.assertEqual(service.submit(body, lambda: None), "pending")
        self.assertTrue((ordering.snapshot_directory / (job_id + ".json")).exists())

        stores[1].active.remove(job_id)
        service.process()
        self.assertEqual(service.submit(body, lambda: None), "deleted")
        self.assertFalse((research.directory / self.alice).exists())
        self.assertTrue((research.directory / self.bob).exists())
        self.assertFalse((research.directory / ("a" * 64 + ".json")).exists())
        self.assertTrue((research.directory / ("b" * 64 + ".json")).exists())
        self.assertFalse((ordering.snapshot_directory / (job_id + ".json")).exists())
        self.assertTrue((ordering.snapshot_directory / (order_ids[self.bob] + ".json")).exists())
        with self.assertRaises(KeyError):
            stores[1].get(job_id, self.alice)
        self.assertEqual(stores[1].get(order_ids[self.bob], self.bob)["status"], "succeeded")

    def test_rejects_authorization_code_from_other_apple_identity_before_revoking(self):
        providers = AccountDeletionProviders("https://auth.example.test", "synthetic-service-key")
        user = {"identities": [{"provider": "apple", "identity_data": {"sub": "linked-apple-subject"}}]}
        client = {"client_id": "io.example.travelant", "client_secret": "synthetic-client-secret"}
        for sub, allowed in [("other-apple-subject", False), ("linked-apple-subject", True)]:
            payload = base64.urlsafe_b64encode(json.dumps({
                "iss": "https://appleid.apple.com", "aud": client["client_id"], "sub": sub
            }).encode()).decode().rstrip("=")
            token = httpx.Response(200, json={"id_token": f"header.{payload}.signature", "refresh_token": "synthetic-refresh"},
                                   request=httpx.Request("POST", "https://appleid.apple.com/auth/token"))
            revoke = httpx.Response(200, request=httpx.Request("POST", "https://appleid.apple.com/auth/revoke"))
            with patch.object(providers, "apple_client", return_value=client), patch(
                "account_deletion.httpx.post", side_effect=[token, revoke]
            ) as post:
                if allowed:
                    providers.revoke_apple(user, "synthetic-code")
                    self.assertEqual(post.call_count, 2)
                    self.assertEqual(post.call_args.kwargs["data"]["token"], "synthetic-refresh")
                else:
                    with self.assertRaises(DeletionRejection) as error:
                        providers.revoke_apple(user, "synthetic-code")
                    self.assertEqual(error.exception.code, "APPLE_ACCOUNT_MISMATCH")
                    self.assertEqual(post.call_count, 1)


if __name__ == "__main__":
    unittest.main()
