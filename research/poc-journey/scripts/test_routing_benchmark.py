import copy
import unittest
from audit_routing_benchmark import audit, percentile
from prepare_routing_osm import AREAS, select_venues


class RoutingAuditorTests(unittest.TestCase):
    def row(self):
        return dict(caseID="synthetic", backend="synthetic", policy="baseline", evidenceMode="SYNTHETIC",
                    outcome="candidate", wallSeconds=.1, calls=2, visited=1, requiredRetained=True,
                    orderRetained=True, deadlineMet=True, arithmeticValid=True, accessStatus="unverified", searchLimited=False)

    def test_valid_candidate_and_paired_report(self):
        a = self.row(); b = copy.deepcopy(a); b.update(policy="finalists", calls=1, wallSeconds=.05)
        issues, result = audit([a, b])
        self.assertEqual(issues, [])
        self.assertEqual(result["paired"][0]["callReduction"], 1)
        self.assertEqual(result["paired"][0]["runtimeReductionFraction"], .5)

    def test_missing_required_deadline_order_or_arithmetic_fails(self):
        for field in ["requiredRetained", "orderRetained", "deadlineMet", "arithmeticValid"]:
            row = self.row(); row[field] = False
            self.assertTrue(audit([row])[0])

    def test_forged_flag_and_empty_candidate_are_rejected(self):
        row = self.row(); row["requiredRetained"] = "false"
        self.assertTrue(audit([row])[0])
        row = self.row(); row["visited"] = 0
        self.assertTrue(audit([row])[0])

    def test_provider_payload_and_fake_live_accuracy_rejected(self):
        row = self.row(); row["polyline"] = "should-never-export"
        self.assertTrue(audit([row])[0])
        row = self.row(); row["accessStatus"] = "verified_front_door"
        self.assertTrue(audit([row])[0])

    def test_unavailable_timings_do_not_improve_success_percentiles(self):
        good = self.row(); unavailable = self.row(); unavailable.update(outcome="missing_configuration", wallSeconds=0, visited=0)
        issues, summary = audit([good, unavailable])
        self.assertFalse(issues)
        self.assertEqual(summary["groups"][0]["p50Seconds"], .1)
        self.assertEqual(summary["groups"][0]["completedN"], 1)
        self.assertEqual(percentile([1, 2, 3], .95), 3)

    def test_sample_has_two_distinct_cafes_per_area_without_entrance_inference(self):
        cafes = [dict(id=f"{index}-{j}", name="Sourced cafe", latitude=lat + j * .0001, longitude=lon,
                      sourceURL="https://www.openstreetmap.org/node/1")
                 for index, (_, lat, lon) in enumerate(AREAS) for j in range(2)]
        venues = select_venues(cafes)
        self.assertEqual(len(venues), 16)
        self.assertEqual(len(set(v["id"] for v in venues)), 16)
        self.assertTrue(all(not v["accesses"] for v in venues))


if __name__ == "__main__":
    unittest.main()
