import copy
import unittest
from audit_matched_routing import audit


class MatchedAuditTests(unittest.TestCase):
    def fixture(self):
        a = dict(pairID="a", querySHA256="a" * 64, provider="apple", mode="walking", order=0, outcome="available", wallSeconds=.5, pacingSeconds=.2, serviceSeconds=.3, geometryPoints=2)
        b = dict(a, provider="valhalla", order=1, wallSeconds=.03, pacingSeconds=0, serviceSeconds=.03)
        c = dict(pairID="a", mode="walking", bothAvailable=True, valhallaToAppleServiceRatio=.1)
        return dict(plannedPairs=1, rows=[a, b], comparisons=[c])

    def test_valid_pair_excludes_pacing_from_service(self):
        errors, summary = audit(self.fixture())
        self.assertFalse(errors)
        self.assertEqual(summary["groups"][0]["serviceSeconds"]["p50"], .3)

    def test_identity_order_coverage_and_ratio_tampering_rejected(self):
        for field, value in [("querySHA256", "b" * 64), ("order", 0), ("mode", "automobile"), ("serviceSeconds", .4)]:
            data = self.fixture(); data["rows"][1][field] = value
            self.assertTrue(audit(data)[0])
        data = self.fixture(); data["comparisons"][0]["valhallaToAppleServiceRatio"] = .5
        self.assertTrue(audit(data)[0])

    def test_unavailable_pair_never_exports_accuracy_or_ratios(self):
        data = self.fixture(); data["rows"][0]["outcome"] = "invalidResponse"
        self.assertTrue(audit(data)[0])
        data["comparisons"][0] = dict(pairID="a", mode="walking", bothAvailable=False)
        errors, result = audit(data)
        self.assertFalse(errors); self.assertEqual(result["bothAvailable"], 0)
        data["rows"][0]["polyline"] = "raw"
        self.assertTrue(audit(data)[0])

    def test_incomplete_nonfinite_and_forged_flags_rejected(self):
        for mutation in [lambda d: d.update(plannedPairs=2), lambda d: d["rows"][0].update(wallSeconds=float("nan")), lambda d: d["comparisons"][0].update(bothAvailable="true")]:
            data = copy.deepcopy(self.fixture()); mutation(data)
            self.assertTrue(audit(data)[0])


if __name__ == "__main__":
    unittest.main()
