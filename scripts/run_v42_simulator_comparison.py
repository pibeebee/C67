#!/usr/bin/env python3
"""Run only the matched v4.2 Simulator benchmark, with a temporary Luna relay."""
import argparse
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
from threading import Thread
from time import monotonic
from uuid import UUID

ROOT = Path(__file__).resolve().parents[1]
SUITE = "C67AppTests/V42LiveExperienceComparisonTests"
MODEL = "cx/gpt-6-luna(max)"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator", type=UUID, required=True, help="iPhone Simulator UUID")
    parser.add_argument("--result-bundle", type=Path, required=True, help="Unused .xcresult path")
    parser.add_argument("--derived-data", type=Path, required=True)
    parser.add_argument("--repetitions", type=int, choices=range(1, 6), default=2)
    parser.add_argument("--env-file", type=Path, help="Private Luna environment file")
    args = parser.parse_args()
    result = args.result_bundle.resolve()
    if result.suffix != ".xcresult" or result.exists():
        parser.error("--result-bundle must be an unused .xcresult path")

    # Reuse the Pocket Responses transport, including completion/model metadata.
    sys.path.insert(0, str(ROOT / "server/pocket/src"))
    from server import load_env, request_luna
    import visit_advice

    runner_env = os.environ.copy()
    for key in ("POCKET_LLM_API_KEY", "AI_GIOVANC_API_KEY", "GIOVANC_API_KEY", "CATALOG_LLM_API_KEY"):
        runner_env.pop(key, None)
    load_env(args.env_file)
    os.environ.setdefault("POCKET_LLM_BASE_URL", os.environ.get("AI_GIOVANC_BASE_URL", "https://ai.giovanc.com/v1"))
    if os.environ.get("AI_GIOVANC_API_KEY"):
        if os.environ.get("AI_GIOVANC_BASE_URL", "").rstrip("/") == os.environ["POCKET_LLM_BASE_URL"].rstrip("/"):
            os.environ.setdefault("POCKET_LLM_API_KEY", os.environ["AI_GIOVANC_API_KEY"])
    os.environ["POCKET_LLM_PROTOCOL"] = "responses"
    visit_advice.provider_base()
    visit_advice.credentials()

    token = secrets.token_urlsafe(32)

    class Relay(BaseHTTPRequestHandler):
        def log_message(self, *_):
            # Avoid logging request data or credentials.
            pass

        def reply(self, status, **value):
            data = json.dumps(value).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            try:
                self.wfile.write(data)
            except (BrokenPipeError, ConnectionResetError):
                pass  # The test deadline may have cancelled the client.

        def do_POST(self):
            if self.path != "/generate" or not hmac.compare_digest(
                self.headers.get("Authorization", "").encode(), f"Bearer {token}".encode()
            ):
                self.reply(404, code="UNKNOWN_ROUTE")
                return
            try:
                size = int(self.headers.get("Content-Length", "0"))
                if not 0 < size < 16_384:
                    raise ValueError
                payload = json.loads(self.rfile.read(size))
                instructions, context = payload["instructions"], payload["context"]
                if not all(isinstance(field, str) and field.strip() for field in (instructions, context)):
                    raise ValueError
            except (ValueError, KeyError, TypeError):
                self.reply(400, code="INVALID_COMPARISON_PROMPT")
                return

            started = monotonic()
            try:
                response = request_luna(visit_advice, {
                    "model": MODEL,
                    "max_tokens": 5000,
                    "messages": [{"role": "system", "content": instructions}, {"role": "user", "content": context}],
                }, attempts=1)
                model = response["model"]
                choice = response["choices"][0]
                if (model not in {MODEL, "gpt-6-luna(max)", "gpt-6-luna"}
                    or response["providerProtocol"] != "responses" or response["completionStatus"] != "completed"
                    or (response["reasoning"] or {}).get("effort") != "max" or choice["finish_reason"] != "stop"):
                    raise ValueError("Unexpected Luna response metadata")
                text = choice["message"]["content"]
                if not isinstance(text, str):
                    raise ValueError("Invalid Luna response text")
            except (OSError, subprocess.TimeoutExpired, ValueError, TypeError, KeyError, IndexError, AttributeError) as error:
                elapsed = monotonic() - started
                print(f"V42_LUNA_RELAY outcome=failed upstream_seconds={elapsed:.3f} error_type={type(error).__name__}", flush=True)
                self.reply(502, code="LUNA_REQUEST_FAILED", upstreamSeconds=elapsed)
            else:
                self.reply(200, text=text, reportedModel=model, upstreamSeconds=monotonic() - started)

    with ThreadingHTTPServer(("127.0.0.1", 0), Relay) as relay:
        thread = Thread(target=relay.serve_forever, daemon=True)
        thread.start()
        runner_env.update(
            TEST_RUNNER_C67_V42_MATCHED_COMPARE="1",
            TEST_RUNNER_C67_V42_RELAY_PORT=str(relay.server_port),
            TEST_RUNNER_C67_V42_RELAY_TOKEN=token,
            TEST_RUNNER_C67_V42_REPETITIONS=str(args.repetitions),
        )
        command = [
            "xcodebuild", "test", "-project", "apps/ios/C67.xcodeproj", "-scheme", "C67",
            "-configuration", "Debug", "-destination", f"platform=iOS Simulator,id={str(args.simulator).upper()}",
            "-derivedDataPath", str(args.derived_data.resolve()), "-resultBundlePath", str(result),
            "-parallel-testing-enabled", "NO", f"-only-testing:{SUITE}", "C67_DATA_MODE=mock",
        ]
        try:
            return subprocess.run(command, cwd=ROOT, env=runner_env, check=False).returncode
        finally:
            relay.shutdown()
            thread.join()


if __name__ == "__main__":
    sys.exit(main())
