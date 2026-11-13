"""Exercise relocated Pocket entry points with temporary state and no providers."""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import unittest
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


SERVER = Path(__file__).resolve().parents[1] / "src/server.py"
REPO = Path(__file__).resolve().parents[3]
READ_TOKEN = "synthetic-read-token-for-local-tests"
WRITE_TOKEN = "synthetic-write-token-for-local-tests"


class PocketServerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory()
        cls.data = Path(cls.directory.name) / "data"
        cls.env = {key: value for key, value in os.environ.items()
                   if not key.startswith(("POCKET_", "TOMTOM_"))}
        cls.env.update(POCKET_READ_TOKEN=READ_TOKEN, POCKET_WRITE_TOKEN=WRITE_TOKEN,
                       POCKET_HOST="127.0.0.1", POCKET_LUNA_DAILY_CAP="0")
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            cls.env["POCKET_PORT"] = str(listener.getsockname()[1])
        cls.base = "http://127.0.0.1:" + cls.env["POCKET_PORT"]
        cls.process = subprocess.Popen(
            [sys.executable, str(SERVER), "--data-dir", str(cls.data)],
            cwd=cls.directory.name, env=cls.env,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if cls.process.poll() is not None:
                cls.directory.cleanup()
                raise RuntimeError("Pocket failed to start from an unrelated working directory")
            try:
                with urlopen(cls.base + "/health", timeout=1) as response:
                    if response.status == 200:
                        return
            except (URLError, TimeoutError):
                time.sleep(0.05)
        cls.process.terminate()
        cls.process.wait(timeout=5)
        cls.directory.cleanup()
        raise RuntimeError("Pocket startup deadline exceeded")

    @classmethod
    def tearDownClass(cls):
        cls.process.terminate()
        cls.process.wait(timeout=5)
        cls.directory.cleanup()

    def request(self, path, token=None, body=None):
        headers = {"Authorization": "Bearer " + token} if token else {}
        if body is not None:
            headers["Content-Type"] = "application/json"
        request = Request(self.base + path, headers=headers,
                          data=json.dumps(body).encode() if body is not None else None)
        try:
            with urlopen(request, timeout=3) as response:
                return response.status, json.load(response)
        except HTTPError as error:
            with error:
                return error.code, json.load(error)

    def test_catalog_uses_canonical_resources_from_arbitrary_cwd(self):
        expected = json.loads((REPO / "packages/PocketEngine/Sources/PocketEngine/Resources/catalog.json").read_text())
        status, catalog = self.request("/v1/catalog", READ_TOKEN)
        self.assertEqual(status, 200)
        self.assertEqual({v["id"] for v in catalog["venues"]},
                         {v["id"] for v in expected["venues"]})
        self.assertEqual(catalog["schemaVersion"], expected["schemaVersion"])

    def test_catalog_requires_read_credential(self):
        for token in (None, "wrong-local-token", WRITE_TOKEN):
            with self.subTest(token=token):
                self.assertEqual(self.request("/v1/catalog", token)[0], 401)

    def test_import_does_not_accept_read_credential(self):
        self.assertEqual(self.request("/v1/evidence/import", READ_TOKEN, {})[0], 401)
        self.assertEqual(self.request("/v1/evidence/import", WRITE_TOKEN, {})[0], 422)

    def test_reopening_data_keeps_existing_catalog(self):
        before = self.request("/v1/catalog", READ_TOKEN)[1]
        seed = json.loads((REPO / "packages/PocketEngine/Sources/PocketEngine/Resources/catalog.json").read_text())
        for venue in seed["venues"]:
            venue["facts"] = []
            venue["hours"] = None
        identities = Path(self.directory.name) / "identities.json"
        identities.write_text(json.dumps(seed))
        result = subprocess.run(
            [sys.executable, str(SERVER), "--data-dir", str(self.data),
             "--import-identities", str(identities)],
            cwd=self.directory.name, env=self.env, capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, "Local catalog import failed")
        after = self.request("/v1/catalog", READ_TOKEN)[1]
        self.assertEqual(before["venues"], after["venues"])


if __name__ == "__main__":
    unittest.main()
