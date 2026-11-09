"""Regression checks for ordered GTFS shape projection without live downloads."""
import csv
import hashlib
import io
import unittest
import zipfile

from import_transjakarta import geometry


class GeometryImportTests(unittest.TestCase):
    def fixture(self):
        buffer = io.BytesIO()
        text = io.StringIO()
        writer = csv.DictWriter(text, fieldnames=["shape_id", "shape_pt_sequence", "shape_pt_lat", "shape_pt_lon"])
        writer.writeheader()
        for index, latitude in enumerate([-6.2, -6.201, -6.202, -6.201, -6.2]):
            writer.writerow(dict(shape_id="loop", shape_pt_sequence=index, shape_pt_lat=latitude, shape_pt_lon=106.8))
        with zipfile.ZipFile(buffer, "w") as archive:
            archive.writestr("shapes.txt", text.getvalue())
        data = buffer.getvalue()
        feed = dict(source=dict(sourceSHA256=hashlib.sha256(data).hexdigest()),
                    stops=[dict(id="A", latitude=-6.2, longitude=106.8), dict(id="B", latitude=-6.202, longitude=106.8)],
                    patterns=[dict(id="1-loop", shapeID="loop", calls=[dict(stopID="A", sequence=0),
                                  dict(stopID="B", sequence=5), dict(stopID="A", sequence=10)])])
        return data, feed

    def test_loop_uses_separate_ordered_occurrences(self):
        data, feed = self.fixture()
        result = geometry(data, feed)
        self.assertEqual([call["pointIndex"] for call in result["patterns"][0]["calls"]], [0, 2, 4])
        self.assertEqual([call["sequence"] for call in result["patterns"][0]["calls"]], [0, 5, 10])

    def test_source_mismatch_is_rejected(self):
        data, feed = self.fixture()
        feed["source"]["sourceSHA256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "source hash"):
            geometry(data, feed)

    def test_remote_stop_is_rejected(self):
        data, feed = self.fixture()
        feed["stops"][1]["latitude"] = -6.3
        with self.assertRaisesRegex(ValueError, "150 m"):
            geometry(data, feed)

    def test_partial_catalog_records_unmatched_pattern_without_fabricating_its_line(self):
        data, feed = self.fixture()
        import copy
        invalid = copy.deepcopy(feed["patterns"][0])
        invalid["id"] = "missing-pattern"; invalid["shapeID"] = "absent-shape"
        feed["patterns"].append(invalid)
        result = geometry(data, feed, allow_partial=True)
        self.assertEqual(result["schemaVersion"], 2)
        self.assertEqual([pattern["id"] for pattern in result["patterns"]], ["1-loop"])
        self.assertEqual(result["missingPatterns"], [{"id": "missing-pattern", "reason": "Missing shape absent-shape"}])


if __name__ == "__main__":
    unittest.main()
