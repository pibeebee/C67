#!/usr/bin/env python3
"""Build an attributed, bounded TJ network snapshot from an existing captured ZIP."""

import argparse
from collections import Counter, defaultdict
import csv
import hashlib
import io
import json
from pathlib import Path
import re
import zipfile

from import_transjakarta import seconds


def build(data, original, boundary_source):
    digest = hashlib.sha256(data).hexdigest()
    if digest != original["source"]["sourceSHA256"]:
        raise ValueError("Network ZIP must match the original attributed snapshot")
    polygons = json.loads(re.search(r'#"(\[\[\[\[.*?\]\]\]\])"#', boundary_source).group(1))

    def inside_ring(x, y, ring):
        result = False
        for a, b in zip(ring, ring[1:]):
            cross = (x - a[0]) * (b[1] - a[1]) - (y - a[1]) * (b[0] - a[0])
            if abs(cross) < 1e-10 and min(a[0], b[0]) - 1e-10 <= x <= max(a[0], b[0]) + 1e-10 and min(a[1], b[1]) - 1e-10 <= y <= max(a[1], b[1]) + 1e-10:
                return True
            if (a[1] > y) != (b[1] > y) and x < (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]) + a[0]:
                result = not result
        return result

    def within(stop):
        x, y = float(stop["stop_lon"]), float(stop["stop_lat"])
        return any(inside_ring(x, y, polygon[0]) and not any(inside_ring(x, y, hole) for hole in polygon[1:]) for polygon in polygons)

    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        def rows(name):
            if archive.getinfo(name).file_size > 30_000_000:
                raise ValueError("Unbounded table " + name)
            with archive.open(name) as stream:
                return list(csv.DictReader(io.TextIOWrapper(stream, encoding="utf-8-sig")))

        if "calendar_dates.txt" in archive.namelist():
            raise ValueError("Calendar exceptions require an explicit runtime update")
        routes = {r["route_id"]: r for r in rows("routes.txt")}
        stops = {s["stop_id"]: s for s in rows("stops.txt")}
        calls, windows = defaultdict(list), defaultdict(list)
        for call in rows("stop_times.txt"):
            calls[call["trip_id"]].append(call)
        for window in rows("frequencies.txt"):
            windows[window["trip_id"]].append(window)
        patterns, exclusions = [], Counter()
        for trip in rows("trips.txt"):
            route = routes[trip["route_id"]]
            times = sorted(calls[trip["trip_id"]], key=lambda row: int(row["stop_sequence"]))
            frequency = windows[trip["trip_id"]]
            if route["agency_id"] != "Tije" or len(times) < 2:
                exclusions["operator_or_incomplete"] += 1
                continue
            if not all(within(stops[t["stop_id"]]) for t in times):
                exclusions["outside_existing_jakarta_boundary"] += 1
                continue
            if not frequency or any((w.get("exact_times", "0") or "0") != "0" for w in frequency):
                exclusions["scheduled_or_missing_frequency"] += 1
                continue
            if not any(t.get("pickup_type", "") in ("", "0") for t in times):
                exclusions["no_unconditional_pickup"] += 1
                continue
            baseline = seconds(times[0]["departure_time"])
            patterns.append(dict(id=trip["trip_id"], serviceID=trip["service_id"], headsign=trip["trip_headsign"],
                                 directionID=trip["direction_id"], shapeID=trip["shape_id"], routeID=route["route_id"], category=route["route_desc"],
                                 calls=[dict(stopID=t["stop_id"], sequence=int(t["stop_sequence"]),
                                             arrivalOffset=seconds(t["arrival_time"]) - baseline,
                                             departureOffset=seconds(t["departure_time"]) - baseline,
                                             pickupAllowed=t.get("pickup_type", "") in ("", "0"),
                                             dropOffAllowed=t.get("drop_off_type", "") in ("", "0")) for t in times],
                                 frequencies=[dict(start=seconds(w["start_time"]), end=seconds(w["end_time"]), headway=int(w["headway_secs"]), exactTimes=0) for w in frequency]))
        used = {c["stopID"] for p in patterns for c in p["calls"]}
        used_services = {p["serviceID"] for p in patterns}
        weekdays = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        services = [dict(id=r["service_id"], startDate=r["start_date"], endDate=r["end_date"],
                         weekdays=[i + 1 for i, day in enumerate(weekdays) if r[day] == "1"]) for r in rows("calendar.txt") if r["service_id"] in used_services]
        edges = {}
        # Candidates retain their origin. Native walking is still required for every transfer.
        groups = defaultdict(list)
        for stop in sorted(used):
            parent = stops[stop]["parent_station"]
            if parent:
                groups[parent].append(stop)
            edges[(stop, stop)] = dict(fromStopID=stop, toStopID=stop, minimumSeconds=120,
                                      evidence="GTFS identical boarding stop; authored 120-second interchange buffer; access requires walking validation")
        for parent, members in groups.items():
            for a in members:
                for b in members:
                    if a != b:
                        edges[(a, b)] = dict(fromStopID=a, toStopID=b, minimumSeconds=120,
                                            evidence=f"GTFS shared parent {parent}; authored 120-second buffer; platform connection requires walking validation")
        for row in rows("transfers.txt"):
            a, b = row["from_stop_id"], row["to_stop_id"]
            origins = [a] if a in used else groups.get(a, [])
            destinations = [b] if b in used else groups.get(b, [])
            if row["transfer_type"] == "0":
                for origin in origins:
                    for destination in destinations:
                        edges[(origin, destination)] = dict(fromStopID=origin, toStopID=destination, minimumSeconds=120,
                                                           evidence=f"GTFS recommended transfer {a} to {b} with no minimum time; authored 120-second buffer plus validated walking")
    source = dict(original["source"])
    source["id"] += "-network-v1"
    source["modification"] = "TJ patterns wholly inside the existing Jakarta boundary. Unconditional pickup/drop-off retained. Frequency service only. One-transfer candidate links use identical stops, shared parents or explicit type-0 transfers, a 120-second buffer and separately validated walking."
    network = dict(schemaVersion=2, source=source, agencyID="Tije", routeID="network", routeName="TJ Jakarta network", category="TJ", timeZone="Asia/Jakarta",
                   stops=[dict(id=i, name=stops[i]["stop_name"], latitude=float(stops[i]["stop_lat"]), longitude=float(stops[i]["stop_lon"]), parentStation=stops[i]["parent_station"], platform=stops[i]["platform_code"]) for i in sorted(used)],
                   services=services, patterns=patterns, transfers=list(edges.values()))
    summary = dict(sourceSHA256=digest, routes=len({p["routeID"] for p in patterns}), patterns=len(patterns), stops=len(used),
                   categories=dict(Counter(p["category"] for p in patterns)), excludedPatterns=dict(exclusions), transferCandidates=len(edges))
    return network, summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-zip", type=Path, required=True)
    parser.add_argument("--feed", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    boundary = Path(__file__).resolve().parents[1] / "apps/c67-trip-integration/Packages/TripIntegration/Sources/TripIntegration/VendorRouting/NativeTripModels.swift"
    network, summary = build(args.input_zip.read_bytes(), json.loads(args.feed.read_text()), boundary.read_text())
    args.output.write_text(json.dumps(network, separators=(",", ":")) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
