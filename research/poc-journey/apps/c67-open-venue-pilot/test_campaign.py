"""Protect frozen campaigns and keep unreviewed proposals outside application data."""

import contextlib
import io
import json
import tempfile
import types
import unittest
from pathlib import Path
from unittest.mock import patch

import pilot
from openrouter import ExtractionClient
from summarize_campaign import summarize


class CampaignTests(unittest.TestCase):
    def test_review_export_resolves_second_page_and_never_treats_support_as_approval(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with patch.multiple(pilot, ROOT=root, LOCAL=root/".local", OUT=root/"results"), \
                    contextlib.redirect_stdout(io.StringIO()):
                campaign = pilot.configure_campaign("citations")
                sources = [{"url": f"https://example.org/{i}", "checked_at": "2026-11-10",
                            "sha256": str(i), "state": "fetched"} for i in (1, 2)]
                target = {"id": "a", "name": "Venue A", "branch": "Branch", "places": [],
                          "sources": sources, "evidence": [{"id": "e1", "source": 2, "text": "Venue A"}]}
                pilot.save(pilot.LOCAL/"evidence.json", {"targets": [target], "network_attempts": 2, "seconds": 1})
                claims = {key: {"status": "unknown", "value": "", "evidence": []} for key in pilot.FIELDS}
                claims["identity"] = {"status": "supported", "value": "Venue A", "evidence": ["e1"]}
                pilot.save(pilot.OUT/"giovanc/extraction.json", {
                    "model": "test-model", "evidence_sha256": pilot.digest((pilot.LOCAL/"evidence.json").read_bytes()),
                    "rows": [{"id": "a", "state": "extracted", "claims": claims, "seconds": 1, "model": "test-model"}],
                    "attempts": [{"state": "accepted", "costUSD": None}],
                })
                pilot.save(campaign/"discovery.json", {"rows": [
                    {"id": "a", "category": "library", "urls": [sources[0]["url"]], "risks": []}
                ]})
                summary = summarize("citations")
                row = json.loads((pilot.OUT/"review-queue.json").read_text())["rows"][0]
                self.assertEqual(row["claim_evidence"]["identity"][0]["url"], "https://example.org/2")
                self.assertEqual(row["claim_evidence"]["identity"][0]["page_sha256"], "2")
                self.assertEqual(row["decision"], "pending_review")
                self.assertFalse(row["app_eligible"])
                self.assertIsNone(summary["accepted_response_cost_usd"])

    def test_thirty_unsourced_rows_are_isolated_and_never_call_model_or_become_eligible(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            frozen = root / "results/extraction.json"
            frozen.parent.mkdir()
            frozen.write_text('existing benchmark\n')
            settings = types.SimpleNamespace(read_settings=lambda: {
                "CATALOG_LLM_BASE_URL": "https://luna-provider.example/v1",
                "CATALOG_LLM_MODEL": "cx/gpt-6-luna(max)", "CATALOG_LLM_API_KEY": "test",
            })
            with patch.multiple(pilot, ROOT=root, LOCAL=root/".local", OUT=root/"results"), \
                    patch.dict("sys.modules", {"catalog_llm": settings}), \
                    patch.object(ExtractionClient, "send", side_effect=AssertionError("Unexpected API request")), \
                    contextlib.redirect_stdout(io.StringIO()):
                campaign = pilot.configure_campaign("expansion")
                targets = [{"id": str(i), "name": f"Venue {i}", "branch": "Branch", "places": [],
                            "sources": [], "evidence": []} for i in range(30)]
                pilot.save(pilot.LOCAL/"evidence.json", {"targets": targets, "network_attempts": 0, "seconds": 0})
                pilot.save(campaign/"discovery.json", {"rows": [
                    {"id": t["id"], "category": "library", "urls": [], "risks": []} for t in targets
                ]})
                pilot.infer("", 0, None, "giovanc")
                pilot.infer("", 0, None, "giovanc")
                with self.assertRaisesRegex(ValueError, "already has extraction"):
                    pilot.collect(campaign/"targets.json")
                summary = summarize("expansion")
                self.assertEqual(summary["new_candidates"], 30)
                self.assertEqual(summary["inference_states"], {"no_source": 30})
                self.assertEqual(summary["generation_attempts"], 0)
                self.assertEqual(summary["new_app_eligible"], 0)
                self.assertEqual(summary["review_decisions"], {"needs_source": 30})
                queue = json.loads((pilot.OUT/"review-queue.json").read_text())
                self.assertTrue(all(not row["app_eligible"] for row in queue["rows"]))
                self.assertEqual(frozen.read_text(), 'existing benchmark\n')
                for invalid in ("../results", "/tmp/batch", "batch/name"):
                    with self.assertRaises(ValueError):
                        pilot.configure_campaign(invalid)


if __name__ == "__main__":
    unittest.main()
