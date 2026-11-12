import copy
import unittest

from check_integration_policy import validate_promotion


class PromotionPolicyTests(unittest.TestCase):
    def setUp(self):
        self.event = {"pull_request": {
            "head": {"ref": "dev", "repo": {"full_name": "pibeebee/C67"}},
            "base": {"ref": "main", "repo": {"full_name": "pibeebee/C67"}},
        }}

    def test_accepts_same_repository_dev_promotion(self):
        validate_promotion("pull_request", self.event, "pibeebee/C67")

    def test_rejects_feature_branch_and_fork_named_dev(self):
        for field, value in (("ref", "gi/feature"), ("repo", {"full_name": "external/C67"})):
            with self.subTest(field=field):
                event = copy.deepcopy(self.event)
                event["pull_request"]["head"][field] = value
                with self.assertRaises(ValueError):
                    validate_promotion("pull_request", event, "pibeebee/C67")

    def test_rejects_wrong_target_or_repository(self):
        for field, value in (("ref", "dev"), ("repo", {"full_name": "external/C67"})):
            with self.subTest(field=field):
                event = copy.deepcopy(self.event)
                event["pull_request"]["base"][field] = value
                with self.assertRaises(ValueError):
                    validate_promotion("pull_request", event, "pibeebee/C67")

    def test_rejects_missing_identity_payload_and_non_pr_events(self):
        for event_name, event, repository in (("push", self.event, "pibeebee/C67"),
                                             ("pull_request", {}, "pibeebee/C67"),
                                             ("pull_request", self.event, "")):
            with self.subTest(event_name=event_name, repository=repository):
                with self.assertRaises(ValueError):
                    validate_promotion(event_name, event, repository)


if __name__ == "__main__":
    unittest.main()
