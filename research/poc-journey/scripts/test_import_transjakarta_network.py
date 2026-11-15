"""Network import guards for restrictions, geographic bounds and transfer provenance."""

import hashlib
import io
import unittest
import zipfile

from import_transjakarta_network import build


class NetworkImportTests(unittest.TestCase):
    def fixture(self, outside=False, exact="0", pickup="0"):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            tables = {
                "routes.txt": "route_id,agency_id,route_desc\n1B,Tije,Angkutan Umum Integrasi\n",
                "trips.txt": "route_id,trip_id,service_id,trip_headsign,direction_id,shape_id\n1B,1B-test,day,Destination,0,shape\n",
                "stops.txt": "stop_id,stop_name,stop_lat,stop_lon,parent_station,platform_code\n"
                             f"a,Origin,-6.2,{108 if outside else 106.8},parent-a,A\n"
                             "b,Destination,-6.21,106.81,parent-b,B\n",
                "stop_times.txt": "trip_id,stop_id,stop_sequence,arrival_time,departure_time,pickup_type,drop_off_type\n"
                                  f"1B-test,a,1,09:00:00,09:00:00,{pickup},1\n"
                                  f"1B-test,b,2,09:10:00,09:10:00,{pickup},0\n",
                "frequencies.txt": "trip_id,start_time,end_time,headway_secs,exact_times\n"
                                   f"1B-test,09:00:00,22:00:00,600,{exact}\n",
                "calendar.txt": "service_id,start_date,end_date,monday,tuesday,wednesday,thursday,friday,saturday,sunday\n"
                                "day,20260101,20261231,1,1,1,1,1,1,1\n",
                "transfers.txt": "from_stop_id,to_stop_id,transfer_type,min_transfer_time\nparent-a,parent-b,0,\n",
            }
            for name, table in tables.items():
                archive.writestr(name, table)
        data = buffer.getvalue()
        original = {"source": {"sourceSHA256": hashlib.sha256(data).hexdigest(), "id": "synthetic-import-test"}}
        boundary = '#"[[[[106,-7],[107,-7],[107,-6],[106,-6],[106,-7]]]]"#'
        return data, original, boundary

    def test_category_and_boarding_restrictions_are_retained(self):
        network, _ = build(*self.fixture())
        pattern = network["patterns"][0]
        self.assertEqual((pattern["routeID"], pattern["category"]), ("1B", "Angkutan Umum Integrasi"))
        self.assertFalse(pattern["calls"][0]["dropOffAllowed"])
        self.assertTrue(pattern["calls"][0]["pickupAllowed"])

    def test_station_transfer_expands_to_actual_boarding_children(self):
        network, _ = build(*self.fixture())
        transfer = next(edge for edge in network["transfers"] if edge["fromStopID"] == "a" and edge["toStopID"] == "b")
        self.assertEqual(transfer["minimumSeconds"], 120)
        self.assertIn("parent-a to parent-b", transfer["evidence"])
        self.assertIn("validated walking", transfer["evidence"])

    def test_outside_patterns_are_excluded_without_truncating_their_stop_sequence(self):
        network, summary = build(*self.fixture(outside=True))
        self.assertEqual(network["patterns"], [])
        self.assertEqual(summary["excludedPatterns"], {"outside_existing_jakarta_boundary": 1})

    def test_exact_times_and_no_pickup_patterns_are_explicit_exclusions(self):
        network, summary = build(*self.fixture(exact="1"))
        self.assertEqual(network["patterns"], [])
        self.assertEqual(summary["excludedPatterns"], {"scheduled_or_missing_frequency": 1})
        network, summary = build(*self.fixture(pickup="1"))
        self.assertEqual(network["patterns"], [])
        self.assertEqual(summary["excludedPatterns"], {"no_unconditional_pickup": 1})

    def test_source_mismatch_is_rejected(self):
        data, original, boundary = self.fixture()
        original["source"]["sourceSHA256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "match"):
            build(data, original, boundary)


if __name__ == "__main__":
    unittest.main()
