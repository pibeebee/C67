"""Synthetic regression tests for the offline scorer, never participant judgments."""

import copy
import unittest

from evaluate_blok_m import evaluate, metrics, review_labels


class BlokMScoringTests(unittest.TestCase):
    def series(self):
        catalog = {"id": "synthetic", "candidates": [
            {"id": value, "venueID": value, "sourceIDs": ["source"]}
            for value in ["a", "b", "c"]
        ]}
        runs = []
        for persona in ["P0", "P1"]:
            for method in ["general", "category"]:
                runs.append({
                    "persona": {"id": persona}, "window": "day", "method": method,
                    "displayedIDs": ["a", "b", "c"], "eligibleIDs": ["a", "b", "c"],
                    "factSupportedIDs": ["a"],
                    "review": {"quality": {"catalog": catalog, "status": "category_only", "elapsedSeconds": 0.01}},
                })
        return {"catalogID": "synthetic", "clockMode": "frozen_source_snapshot", "runs": runs}

    def reviews(self):
        first = {"reviewerID": "Synthetic regression reviewer A", "judgments": [
            {"personaID": "P1", "candidateID": value, "grade": 1,
             "reason": "Authored scorer regression", "sourceIDs": ["source"]}
            for value in ["a", "b", "c"]
        ]}
        second = copy.deepcopy(first)
        second["reviewerID"] = "Synthetic regression reviewer B"
        return [first, second]

    def test_unrated_series_never_claims_personalization_pass(self):
        report = evaluate(self.series())
        self.assertEqual(report["personalizationOutcome"], "insufficient_evidence")
        self.assertEqual(report["humanJudgments"], "pending_two_independent_reviewers")
        self.assertNotIn("metrics", report["runs"][-1])

    def test_disagreement_requires_adjudication(self):
        reviewers = self.reviews()
        reviewers[1]["judgments"][0]["grade"] = 0
        report = evaluate(self.series(), reviewers)
        self.assertEqual(report["humanJudgments"], "pending_adjudication")
        self.assertNotIn("metrics", report["runs"][-1])

    def test_null_boolean_missing_and_unrelated_source_grades_rejected(self):
        for field, value in [("grade", None), ("grade", True), ("sourceIDs", ["invented"])]:
            reviewers = self.reviews()
            reviewers[0]["judgments"][0][field] = value
            with self.assertRaises(ValueError):
                evaluate(self.series(), reviewers)
        review = self.reviews()[0]
        with self.assertRaises(ValueError):
            review_labels(review, {("P1", "a")}, {"a": {"source"}})

    def test_short_catalog_remains_insufficient(self):
        reviewers = self.reviews()
        for review in reviewers:
            review["judgments"][0]["grade"] = 0
        report = evaluate(self.series(), reviewers)
        self.assertEqual(report["runs"][-1]["relevanceStatus"], "insufficient_catalog_coverage")
        self.assertEqual(report["personalizationOutcome"], "insufficient_evidence")

    def test_missing_recommendations_count_against_precision(self):
        result = metrics(["a"], {"a": 2, "b": 1, "c": 0}, ["a", "b", "c"])
        self.assertAlmostEqual(result["precisionAt3"], 1 / 3)
        self.assertLess(result["ndcgAt3"], 1)

    def test_forged_or_duplicate_displayed_ids_rejected(self):
        for ids in [["a", "invented"], ["a", "a"]]:
            series = self.series()
            series["runs"][0]["displayedIDs"] = ids
            with self.assertRaises(ValueError):
                evaluate(series)

    def test_two_reviews_with_same_identity_rejected(self):
        reviewers = self.reviews()
        reviewers[1]["reviewerID"] = reviewers[0]["reviewerID"]
        with self.assertRaises(ValueError):
            evaluate(self.series(), reviewers)

    def test_missing_afternoon_window_cannot_complete_acceptance(self):
        series = self.series()
        baseline = copy.deepcopy(series["runs"][:2])
        series["runs"] = []
        for index in range(6):
            for template in baseline:
                row = copy.deepcopy(template)
                row["persona"]["id"] = f"P{index}"
                series["runs"].append(row)
        reviewers = self.reviews()
        for reviewer in reviewers:
            original = reviewer["judgments"]
            reviewer["judgments"] = []
            for index in range(1, 6):
                for template in original:
                    judgment = copy.deepcopy(template)
                    judgment["personaID"] = f"P{index}"
                    reviewer["judgments"].append(judgment)
        report = evaluate(series, reviewers)
        self.assertEqual(report["humanJudgments"], "complete")
        self.assertEqual(report["personalizationOutcome"], "insufficient_evidence")


if __name__ == "__main__":
    unittest.main()
