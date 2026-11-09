"""Import evidence must stay immutable while reviewed maintained code can evolve."""
import copy
import hashlib
from pathlib import Path
import tempfile
import unittest

from verify_evidence import validate


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.path = "apps/c67-trip-integration/App/IntegrationModel.swift"
        self.target = self.root / self.path
        self.target.parent.mkdir(parents=True)
        self.target.write_text("imported source")
        self.baseline = self.digest(self.target)
        self.manifest = {"files": [{"publicationPath": self.path, "disposition": "included",
                                   "originalSHA256": "a" * 64, "publishedSHA256": self.baseline}]}
        (self.root / "verification.md").write_text("Bounded verification plan and results")

    @staticmethod
    def digest(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def ledger(self):
        return {"schemaVersion": 1, "changes": [{"publicationPath": self.path,
                "importedPublishedSHA256": self.baseline, "currentSHA256": self.digest(self.target),
                "reason": "Add reviewed itinerary capability", "verification": "verification.md"}]}

    def test_imported_baseline_needs_no_ledger(self):
        self.assertEqual(validate(self.root, self.manifest), [])

    def test_reviewed_change_passes_without_rewriting_import_manifest(self):
        before = copy.deepcopy(self.manifest)
        self.target.write_text("new functionality")
        self.assertEqual(validate(self.root, self.manifest, self.ledger()), [])
        self.assertEqual(self.manifest, before)

    def test_unregistered_change_fails(self):
        self.target.write_text("unreviewed")
        self.assertTrue(validate(self.root, self.manifest))

    def test_changed_source_after_approval_fails(self):
        self.target.write_text("reviewed")
        ledger = self.ledger()
        self.target.write_text("tampered")
        self.assertTrue(validate(self.root, self.manifest, ledger))

    def test_wrong_baseline_duplicate_and_unknown_entries_fail(self):
        self.target.write_text("reviewed")
        for mutation in ("baseline", "duplicate", "unknown", "schema", "reason", "reference", "hash"):
            with self.subTest(mutation=mutation):
                ledger = self.ledger(); change = ledger["changes"][0]
                if mutation == "baseline": change["importedPublishedSHA256"] = "b" * 64
                elif mutation == "duplicate": ledger["changes"].append(dict(change))
                elif mutation == "unknown": change["publicationPath"] = "unknown.swift"
                elif mutation == "schema": ledger["schemaVersion"] = 2
                elif mutation == "reason": change["reason"] = ""
                elif mutation == "reference": change["verification"] = "missing.md"
                else: change["currentSHA256"] = "invalid"
                self.assertTrue(validate(self.root, self.manifest, ledger))

    def test_archival_file_cannot_be_approved_as_maintained_code(self):
        path = "apps/c67-trip-integration/artifacts/historical.json"
        target = self.root / path; target.parent.mkdir(parents=True); target.write_text("original")
        baseline = self.digest(target)
        self.manifest["files"].append({"publicationPath": path, "disposition": "included", "publishedSHA256": baseline})
        target.write_text("rewritten result")
        ledger = {"schemaVersion": 1, "changes": [{"publicationPath": path, "importedPublishedSHA256": baseline,
                  "currentSHA256": self.digest(target), "reason": "Not permitted", "verification": "verification.md"}]}
        self.assertTrue(validate(self.root, self.manifest, ledger))

    def test_missing_file_and_ignored_copy_fail(self):
        self.assertTrue(validate(self.root, self.manifest, published_paths=set()))
        self.target.unlink()
        self.assertTrue(validate(self.root, self.manifest))

    def test_traversal_or_external_verification_reference_fails(self):
        self.target.write_text("reviewed")
        ledger = self.ledger(); ledger["changes"][0]["verification"] = "../outside.md"
        self.assertTrue(validate(self.root, self.manifest, ledger))


if __name__ == "__main__":
    unittest.main()
