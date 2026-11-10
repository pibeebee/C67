"""TJ source-audit semantics, distinct from app-routing acceptance."""

from datetime import date
import hashlib
from pathlib import Path
import tempfile
import unittest
import zipfile

from transjakarta_network_audit import (
    audit_network, conservative_board_at, regular_permission, service_seconds,
)


class TJNetworkAuditTests(unittest.TestCase):
    def service(self, weekdays=None):
        names = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        return dict(start_date="20260101", end_date="20261231",
                    **{name: "1" if weekdays is None or name in weekdays else "0" for name in names})

    def window(self, start="09:00:00", end="10:00:00", exact="0"):
        return [dict(start_time=start, end_time=end, headway_secs="600", exact_times=exact)]

    def test_after_midnight_times_do_not_wrap(self):
        self.assertEqual(service_seconds("26:05:00"), 26 * 3600 + 300)
        with self.assertRaises(ValueError):
            service_seconds("24:60:00")

    def test_on_request_and_forbidden_pickup_are_not_unconditional(self):
        for value in ["1", "2", "3"]:
            self.assertFalse(regular_permission({"pickup_type": value}, "pickup"))
            self.assertFalse(regular_permission({"drop_off_type": value}, "drop_off"))
        self.assertTrue(regular_permission({}, "pickup"))

    def test_before_opening_retains_opening_wait_plus_full_headway(self):
        board, outcome, _ = conservative_board_at(self.window(), 0, 8 * 3600, self.service(), date(2026, 11, 7))
        self.assertEqual((board, outcome), (9 * 3600 + 600, "source_available"))

    def test_exclusive_end_includes_boarding_stop_offset(self):
        board, outcome, _ = conservative_board_at(self.window(), 120, 10 * 3600 + 120 - 600,
                                                 self.service(), date(2026, 11, 7))
        self.assertIsNone(board)
        self.assertEqual(outcome, "source_unavailable")

    def test_overnight_checks_the_previous_service_calendar(self):
        board, outcome, _ = conservative_board_at(self.window("23:00:00", "26:00:00"), 0, 3600,
                                                 self.service({"friday"}), date(2026, 11, 7))
        self.assertEqual((board, outcome), (4200, "source_available"))

    def test_exact_times_is_a_gap_instead_of_a_guessed_frequency(self):
        board, outcome, _ = conservative_board_at(self.window(exact="1"), 0, 9 * 3600,
                                                 self.service(), date(2026, 11, 7))
        self.assertIsNone(board)
        self.assertEqual(outcome, "source_gap")

    def test_inactive_calendar_does_not_create_a_bus(self):
        board, outcome, _ = conservative_board_at(self.window(), 0, 9 * 3600,
                                                 self.service({"monday"}), date(2026, 11, 7))
        self.assertEqual((board, outcome), (None, "source_unavailable"))

    def fixture(self, folder, agency="Tije", bad_sequence=False):
        path = Path(folder) / "synthetic-tj.zip"
        with zipfile.ZipFile(path, "w") as archive:
            for name, text in {
                "routes.txt": f"route_id,agency_id,route_desc\n1,{agency},BRT\n",
                "trips.txt": "route_id,trip_id,service_id,direction_id\n1,1-test,day,0\n",
                "stops.txt": "stop_id,stop_name\na,Origin\nb,Destination\n",
                "stop_times.txt": "trip_id,stop_id,stop_sequence,arrival_time,departure_time,pickup_type,drop_off_type\n"
                                  "1-test,a,1,00:00:00,00:00:00,0,0\n"
                                  f"1-test,b,{1 if bad_sequence else 2},00:10:00,00:10:00,0,0\n",
                "frequencies.txt": "trip_id,start_time,end_time,headway_secs,exact_times\n1-test,09:00:00,10:00:00,600,0\n",
                "calendar.txt": "service_id,start_date,end_date,monday,tuesday,wednesday,thursday,friday,saturday,sunday\n"
                                "day,20260101,20261231,1,1,1,1,1,1,1\n",
                "transfers.txt": "from_stop_id,to_stop_id,transfer_type,min_transfer_time\na,b,0,\n",
            }.items():
                archive.writestr(name, text)
        return path, hashlib.sha256(path.read_bytes()).hexdigest()

    def test_source_matrix_keeps_app_journey_claim_false(self):
        with tempfile.TemporaryDirectory() as folder:
            path, digest = self.fixture(folder)
            report = audit_network(path, digest, [{"routeCandidates": ["1"]}])
        self.assertEqual((report["routeCount"], report["patternCount"], report["observationCount"]), (1, 1, 8))
        self.assertEqual(report["invariantFailures"], [])
        self.assertTrue(all(row["generatedAppJourney"] is False for row in report["observations"]))
        self.assertEqual(report["explicitTransfers"][0]["outcome"], "source_gap")

    def test_source_integrity_failure_is_preserved(self):
        with tempfile.TemporaryDirectory() as folder:
            path, digest = self.fixture(folder, bad_sequence=True)
            report = audit_network(path, digest, [{"routeCandidates": ["1"]}])
        self.assertEqual(report["invariantFailures"], ["1-test"])

    def test_present_calendar_exceptions_cannot_be_ignored_for_availability(self):
        with tempfile.TemporaryDirectory() as folder:
            path, _ = self.fixture(folder)
            with zipfile.ZipFile(path, "a") as archive:
                archive.writestr("calendar_dates.txt", "service_id,date,exception_type\nday,20261107,2\n")
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            report = audit_network(path, digest, [{"routeCandidates": ["1"]}])
        queries = [row for row in report["observations"] if row["probe"] in {
            "before_opening", "morning", "evening_access_delay_30m", "after_midnight", "final_window_end"}]
        self.assertEqual(len(queries), 5)
        self.assertTrue(all(row["outcome"] == "source_gap" and row["boardAtSeconds"] is None for row in queries))

    def test_absent_candidate_and_non_tj_operator_fail(self):
        with tempfile.TemporaryDirectory() as folder:
            path, digest = self.fixture(folder)
            with self.assertRaisesRegex(ValueError, "absent from source"):
                audit_network(path, digest, [{"routeCandidates": ["2"]}])
            path, digest = self.fixture(folder, agency="other")
            with self.assertRaisesRegex(ValueError, "non-Tije"):
                audit_network(path, digest, [{"routeCandidates": ["1"]}])


if __name__ == "__main__":
    unittest.main()
