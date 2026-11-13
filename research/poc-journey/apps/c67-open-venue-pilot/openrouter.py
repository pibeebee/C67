"""Single-model completion transport with paced attempts and strict validation."""

import json
import math
import os
import shlex
import subprocess
import tempfile
import time
from pathlib import Path


MODEL = "nvidia/nemotron-3.5-super-vl:free"
URL = "https://openrouter.ai/api/v1/chat/completions"


class AttemptError(Exception):
    def __init__(self, code, retry_after=0):
        super().__init__(code)
        self.retry_after = retry_after


def credentials(root):
    key = os.environ.get("OPENROUTER_API_KEY", "")
    for path in (
        root.parent / "c67-local-server-lab/.env.local",
        root.parent / "ai-trip-planner/.env",
    ):
        if key:
            break
        if not path.exists():
            continue
        for raw in path.read_text().splitlines():
            name, separator, value = raw.strip().removeprefix("export ").partition("=")
            if separator and name.strip() == "OPENROUTER_API_KEY":
                parts = shlex.split(value, comments=True)
                if len(parts) == 1:
                    key = parts[0]
                break
    if not key or any(character.isspace() for character in key):
        raise ValueError("OPENROUTER_API_KEY is unavailable")
    return key


class ExtractionClient:
    def __init__(self, key, model=MODEL, url=URL, openrouter=True):
        self.key = key
        self.model = model
        self.url = url
        self.openrouter = openrouter
        self.reported_models = {model} if openrouter else {model, model.removeprefix("cx/")}
        self.last_start = 0

    def send(self, payload):
        time.sleep(max(0, 3.2 - (time.monotonic() - self.last_start)))
        self.last_start = time.monotonic()
        with tempfile.TemporaryDirectory(prefix="c67-openrouter-") as directory:
            header_path = Path(directory) / "headers"
            config = {
                "url": self.url, "request": "POST", "connect-timeout": "15", "max-time": "90",
                "dump-header": str(header_path),
                "data-binary": json.dumps(payload, ensure_ascii=False),
            }
            lines = [name + " = " + json.dumps(value) for name, value in config.items()]
            lines.extend("header = " + json.dumps(value) for value in (
                "Authorization: Bearer " + self.key, "Content-Type: application/json",
            ))
            try:
                result = subprocess.run(
                    ["/usr/bin/curl", "--silent", "--show-error", "--config", "-",
                     "--max-filesize", "2000000", "--write-out", "\n%{http_code}"],
                    input="\n".join(lines) + "\n", capture_output=True, text=True, timeout=95,
                )
            except subprocess.TimeoutExpired:
                raise AttemptError("transport_timeout") from None
            if result.returncode:
                raise AttemptError("transport_" + str(result.returncode))
            raw, separator, status = result.stdout.rpartition("\n")
            if not separator or status != "200":
                wait = 0
                for line in header_path.read_text().splitlines():
                    if line.lower().startswith("retry-after:"):
                        try:
                            wait = max(0, float(line.split(":", 1)[1].strip()))
                        except ValueError:
                            pass
                raise AttemptError("http_" + status, wait)
        try:
            return json.loads(raw)
        except ValueError:
            raise AttemptError("response_json") from None

    def complete(self, body, validate, record):
        messages = list(body["messages"])
        if not self.openrouter:
            messages.insert(0, {"role": "system", "content": "Return ONLY valid JSON matching this schema. "
                             "No Markdown or explanation. " + json.dumps(
                                 body["response_format"]["json_schema"]["schema"])})
        payload = dict(body, model=self.model, messages=messages)
        if self.openrouter:
            payload.update(reasoning={"enabled": False}, provider={
                "allow_fallbacks": False, "require_parameters": True,
                "max_price": {"prompt": 0, "completion": 0, "request": 0},
            })
        else:
            payload.pop("temperature", None)
        failures = 0
        while True:
            began = time.monotonic()
            retry_after = 0
            try:
                answer = self.send(payload)
                reported_model = answer.get("model")
                if reported_model not in self.reported_models:
                    raise AttemptError("unexpected_model")
                choices = answer.get("choices")
                if not isinstance(choices, list) or len(choices) != 1:
                    raise AttemptError("response_choices")
                choice = choices[0]
                if choice.get("finish_reason") != "stop":
                    raise AttemptError("incomplete_output")
                claims = json.loads(choice["message"]["content"])
                validate(claims)
                usage = answer.get("usage", {})
                cost = usage.get("cost")
                if cost is not None and (
                    isinstance(cost, bool) or not isinstance(cost, (int, float))
                    or not math.isfinite(cost) or cost < 0
                ):
                    raise AttemptError("invalid_reported_cost")
                if self.openrouter and cost != 0:
                    raise AttemptError("unverified_zero_cost")
            except AttemptError as exc:
                error = str(exc)
                retry_after = exc.retry_after
            except (ValueError, TypeError, KeyError, IndexError, AttributeError):
                error = "invalid_schema_or_evidence"
            else:
                seconds = time.monotonic() - began
                record({"state": "accepted", "seconds": seconds, "model": reported_model,
                        "requested_model": self.model,
                        "provider": answer.get("provider"), "costUSD": cost})
                return claims, {
                    "model": reported_model, "requested_model": self.model,
                    "provider": answer.get("provider"),
                    "prompt_tokens": usage.get("prompt_tokens"),
                    "output_tokens": usage.get("completion_tokens"), "costUSD": cost,
                    "finish": "stop", "successful_attempt_seconds": seconds,
                }
            failures += 1
            wait = max(retry_after, min(60, 2 ** min(failures, 6)))
            record({"state": "retry", "error": error, "seconds": time.monotonic() - began,
                    "retry_delay_seconds": wait, "model": self.model})
            print(f"Retry {self.model}: {error}; waiting {wait:g}s", flush=True)
            time.sleep(wait)
            payload["messages"] = [
                *messages,
                {"role": "user", "content": "Return the complete JSON object only. Use exactly the "
                 "seven schema fields. Unknown facts must have an empty value and empty evidence array. "
                 "Every other fact needs one or two supplied evidence IDs. Do not add fields."},
            ]
