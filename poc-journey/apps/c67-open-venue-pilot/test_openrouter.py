"""Regressions for same-model retries and the output acceptance boundary."""

import copy
import json
import unittest
from unittest.mock import patch

from openrouter import MODEL, AttemptError, ExtractionClient
from pilot import FIELDS, validate


def empty_claims():
    return {key: {"status": "unknown", "value": "", "evidence": []} for key in FIELDS}


def answer(claims):
    return {"model": MODEL, "choices": [{"finish_reason": "stop",
            "message": {"content": json.dumps(claims)}}], "usage": {"cost": 0}}


def strict(claims):
    if validate(claims, {"e1"}):
        raise ValueError("invalid_evidence")


class RetryTests(unittest.TestCase):
    @patch("openrouter.time.sleep")
    def test_errors_and_invalid_output_retry_only_requested_model(self, sleep):
        bad = empty_claims()
        bad["identity"] = {"status": "supported", "value": "Place", "evidence": ["not-supplied"]}
        responses = [AttemptError("http_429", 9), answer(bad), answer(empty_claims())]
        client = ExtractionClient("test")
        events = []
        with patch.object(client, "send", side_effect=responses) as send:
            claims, result = client.complete({"messages": [], "max_tokens": 1600}, strict, events.append)
        self.assertEqual(claims, empty_claims())
        self.assertEqual(result["model"], MODEL)
        self.assertEqual([event["state"] for event in events], ["retry", "retry", "accepted"])
        self.assertEqual(events[0]["retry_delay_seconds"], 9)
        for call in send.call_args_list:
            payload = call.args[0]
            self.assertEqual(payload["model"], MODEL)
            self.assertNotIn("models", payload)
            self.assertFalse(payload["provider"]["allow_fallbacks"])
            self.assertEqual(payload["provider"]["max_price"]["prompt"], 0)
        self.assertEqual(sleep.call_count, 2)

    @patch("openrouter.time.sleep")
    def test_unexpected_model_truncation_and_nonzero_cost_are_retried(self, sleep):
        wrong = answer(empty_claims())
        wrong["model"] = "another-model"
        partial = answer(empty_claims())
        partial["choices"][0]["finish_reason"] = "length"
        charged = answer(empty_claims())
        charged["usage"]["cost"] = 0.01
        events = []
        client = ExtractionClient("test")
        with patch.object(client, "send", side_effect=[wrong, partial, charged, answer(empty_claims())]):
            client.complete({"messages": []}, strict, events.append)
        self.assertEqual([row.get("error") for row in events[:-1]], [
            "unexpected_model", "incomplete_output", "unverified_zero_cost",
        ])

    def test_malformed_fact_shapes_cannot_be_accepted(self):
        for value in (None, [], {}, {"identity": None}):
            with self.subTest(value=value), self.assertRaises(ValueError):
                strict(value)
        for evidence in (["e1", "e1"], [["e1"]], ["unknown-id"]):
            claims = empty_claims()
            claims["identity"] = {"status": "supported", "value": "Place", "evidence": evidence}
            with self.subTest(evidence=evidence), self.assertRaises(ValueError):
                strict(copy.deepcopy(claims))

    def test_configured_endpoint_accepts_known_alias_and_unknown_cost(self):
        requested = "cx/gpt-6-luna(max)"
        client = ExtractionClient("test", requested, "https://luna-provider.example/v1/chat/completions", False)
        response = answer(empty_claims())
        response["model"] = requested.removeprefix("cx/")
        response["usage"] = {"prompt_tokens": 10, "completion_tokens": 30}
        body = {"messages": [], "response_format": {"json_schema": {"schema": {}}}, "temperature": 0}
        events = []
        with patch.object(client, "send", return_value=response) as send:
            _, result = client.complete(body, strict, events.append)
        payload = send.call_args.args[0]
        self.assertEqual(payload["model"], requested)
        self.assertNotIn("provider", payload)
        self.assertNotIn("reasoning", payload)
        self.assertNotIn("temperature", payload)
        self.assertIsNone(result["costUSD"])
        self.assertEqual(result["model"], "gpt-6-luna(max)")
        self.assertNotIn("models", payload)


if __name__ == "__main__":
    unittest.main()
