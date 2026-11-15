"""Regression checks for honest classification and complete evaluator evidence."""

import copy
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

import evaluate_transjakarta_capabilities as evaluation


class CapabilityEvaluatorTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.manifest = evaluation.load_manifest()

    def evidence(self):
        for case in self.manifest["cases"]:
            observation = {"id": case["id"], "outcome": case["expectedOutcome"],
                           "layer": case["blockingLayer"], "detail": "Synthetic evaluator unit-test fixture",
                           "generatedJourney": case["expectedOutcome"] == "supported_feasible"}
            (self.directory / f'{case["id"]}.json').write_text(json.dumps(observation))
        sweep = []
        for pair in range(10):
            for hour in range(10):
                for delay in [0, 1, 5, 15, 30]:
                    for duration in [120, 1201]:
                        sweep.append({"id": f"S{len(sweep) + 1:04}", "from": f"from-{pair}", "to": f"to-{pair}",
                                      "departure": hour, "accessDelayMinutes": delay,
                                      "walkingComponentSeconds": duration, "outcome": "supported_conflict",
                                      "detail": "Synthetic collector fixture"})
        (self.directory / "sweep.json").write_text(json.dumps(sweep))
        return sweep

    def test_manifest_covers_64_cases_and_only_tj_service_categories(self):
        capabilities = {case["requiredCapability"] for case in self.manifest["cases"]}
        self.assertTrue({"brt_transfer", "non_brt", "mikrotrans", "royaltrans", "transjabodetabek", "rusun", "bus_wisata"} <= capabilities)
        self.assertEqual(len(self.manifest["cases"]), 64)

    def test_non_tj_case_is_rejected(self):
        invalid = copy.deepcopy(self.manifest)
        invalid["cases"][0]["operators"] = ["another-operator"]
        path = self.directory / "wrong-scope.json"
        path.write_text(json.dumps(invalid))
        with self.assertRaisesRegex(ValueError, "TJ services only"):
            evaluation.load_manifest(path)

    def test_duplicate_manifest_ids_are_rejected(self):
        invalid = copy.deepcopy(self.manifest)
        invalid["cases"][1]["id"] = "T01"
        path = self.directory / "invalid.json"
        path.write_text(json.dumps(invalid))
        with self.assertRaisesRegex(ValueError, "duplicate"):
            evaluation.load_manifest(path)

    def test_complete_evidence_is_collected_without_converting_gaps_to_routes(self):
        self.evidence()
        core, sweep, errors = evaluation.collect(self.manifest, self.directory, 0)
        self.assertEqual(errors, [])
        self.assertEqual((len(core), len(sweep)), (64, 1000))
        unsupported = [row for row in core if row["observation"]["outcome"] == "unsupported_capability"]
        self.assertGreater(len(unsupported), 0)
        self.assertTrue(all(not row["observation"]["generatedJourney"] for row in unsupported))

    def test_missing_core_result_is_not_a_pass(self):
        self.evidence()
        (self.directory / "T17.json").unlink()
        _, _, errors = evaluation.collect(self.manifest, self.directory, 0)
        self.assertIn("Missing runtime evidence: T17", errors)

    def test_gap_cannot_claim_a_generated_multi_service_tj_journey(self):
        self.evidence()
        path = self.directory / "T17.json"
        observation = json.loads(path.read_text())
        observation["generatedJourney"] = True
        path.write_text(json.dumps(observation))
        _, _, errors = evaluation.collect(self.manifest, self.directory, 0)
        self.assertTrue(any("incorrectly claims" in error for error in errors))

    def test_feasible_result_requires_a_generated_journey(self):
        self.evidence()
        path = self.directory / "T01.json"
        observation = json.loads(path.read_text())
        observation["generatedJourney"] = False
        path.write_text(json.dumps(observation))
        _, _, errors = evaluation.collect(self.manifest, self.directory, 0)
        self.assertTrue(any("no generated journey" in error for error in errors))

    def test_unique_but_wrong_sweep_dimensions_fail(self):
        sweep = self.evidence()
        for row in sweep:
            if row["accessDelayMinutes"] == 30:
                row["accessDelayMinutes"] = 60
        (self.directory / "sweep.json").write_text(json.dumps(sweep))
        _, _, errors = evaluation.collect(self.manifest, self.directory, 0)
        self.assertTrue(any("Cartesian product" in error for error in errors))

    def test_duplicate_sweep_combinations_and_missing_ride_proof_fail(self):
        sweep = self.evidence()
        sweep[1] = dict(sweep[0], id="S0002", outcome="supported_feasible")
        (self.directory / "sweep.json").write_text(json.dumps(sweep))
        _, _, errors = evaluation.collect(self.manifest, self.directory, 0)
        self.assertTrue(any("Cartesian product" in error for error in errors))
        self.assertTrue(any("ride proof" in error for error in errors))

    def test_swift_failure_is_preserved_even_with_complete_json(self):
        self.evidence()
        _, _, errors = evaluation.collect(self.manifest, self.directory, 1)
        self.assertIn("Swift tests failed with exit 1", errors)

    def zip_fixture(self):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            for name, text in {
                "agency.txt": "agency_id,agency_name\nTije,PT Transportasi Jakarta\n",
                "routes.txt": "route_id,route_long_name,route_desc\n1,Test,BRT\n1B,Feeder,Angkutan Umum Integrasi\n",
                "transfers.txt": "from_stop_id,to_stop_id,transfer_type,min_transfer_time\na,b,0,\n",
                "stops.txt": "stop_id\na\nb\n",
                "trips.txt": "route_id,service_id,trip_id\n1,day,t1\n",
                "frequencies.txt": "trip_id,exact_times\nt1,0\n",
                "stop_times.txt": "trip_id,stop_id,pickup_type,drop_off_type\nt1,a,0,0\nt1,b,0,0\n",
                "calendar.txt": "service_id\nday\n",
            }.items():
                archive.writestr(name, text)
        path = self.directory / "synthetic.zip"
        path.write_bytes(buffer.getvalue())
        return path

    def test_full_feed_inspection_preserves_tj_identity_and_missing_transfer_duration(self):
        path = self.zip_fixture()
        evidence = evaluation.inspect_gtfs(path, hashlib.sha256(path.read_bytes()).hexdigest())
        self.assertEqual(evidence["routeCount"], 2)
        self.assertEqual(evidence["transfersWithMinimumSeconds"], 0)
        self.assertFalse(evidence["calendarDatesPresent"])
        self.assertEqual(evidence["invalidReferenceCount"], 0)
        self.assertEqual([agency["id"] for agency in evidence["agencies"]], ["Tije"])

    def test_mismatched_full_snapshot_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "SHA256"):
            evaluation.inspect_gtfs(self.zip_fixture(), "0" * 64)


if __name__ == "__main__":
    unittest.main()
