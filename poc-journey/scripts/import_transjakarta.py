#!/usr/bin/env python3
"""Import an attributed corridor-1 subset from the official TransJakarta GTFS ZIP."""

import argparse
import csv
import hashlib
import io
import json
import math
import urllib.request
import zipfile
from datetime import datetime, timezone
from pathlib import Path


SOURCE = "https://gtfs.transjakarta.co.id/files/file_gtfs.zip"


def seconds(value):
    hour, minute, second = map(int, value.split(":"))
    if not (0 <= hour <= 47 and 0 <= minute < 60 and 0 <= second < 60):
        raise ValueError(f"Invalid GTFS time {value}")
    return hour * 3600 + minute * 60 + second


def subset(data, checked_at, modified):
    archive = zipfile.ZipFile(io.BytesIO(data))

    def rows(name):
        if archive.getinfo(name).file_size > 20_000_000:
            raise ValueError(f"Unbounded table {name}")
        with archive.open(name) as file:
            return list(csv.DictReader(io.TextIOWrapper(file, encoding="utf-8-sig", newline="")))

    route = next(row for row in rows("routes.txt") if row["route_id"] == "1")
    if route["agency_id"] != "Tije" or route["route_desc"] != "BRT" or route["route_type"] != "3":
        raise ValueError("Corridor operator/category changed")
    trips = [row for row in rows("trips.txt") if row["route_id"] == "1"]
    stop_times = rows("stop_times.txt")
    frequencies = rows("frequencies.txt")
    patterns = []
    for trip in trips:
        times = sorted((row for row in stop_times if row["trip_id"] == trip["trip_id"]),
                       key=lambda row: int(row["stop_sequence"]))
        if len(times) < 2 or any(row.get("pickup_type", "") not in ("", "0") or row.get("drop_off_type", "") not in ("", "0") for row in times):
            raise ValueError("Unsupported boarding/alighting restriction or incomplete pattern")
        baseline = seconds(times[0]["departure_time"])
        windows = [row for row in frequencies if row["trip_id"] == trip["trip_id"]]
        if not windows or any(row.get("exact_times", "0") != "0" for row in windows):
            raise ValueError("This POC requires frequency-based corridor-1 service")
        patterns.append({
            "id": trip["trip_id"], "serviceID": trip["service_id"],
            "headsign": trip["trip_headsign"], "directionID": trip["direction_id"],
            "shapeID": trip["shape_id"],
            "calls": [{"stopID": row["stop_id"], "sequence": int(row["stop_sequence"]),
                       "arrivalOffset": seconds(row["arrival_time"]) - baseline,
                       "departureOffset": seconds(row["departure_time"]) - baseline} for row in times],
            "frequencies": [{"start": seconds(row["start_time"]), "end": seconds(row["end_time"]),
                             "headway": int(row["headway_secs"]), "exactTimes": 0} for row in windows],
        })
    stop_ids = {call["stopID"] for pattern in patterns for call in pattern["calls"]}
    stops = [{"id": row["stop_id"], "name": row["stop_name"],
              "latitude": float(row["stop_lat"]), "longitude": float(row["stop_lon"]),
              "parentStation": row["parent_station"], "platform": row["platform_code"]}
             for row in rows("stops.txt") if row["stop_id"] in stop_ids]
    service_ids = {trip["service_id"] for trip in trips}
    weekdays = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
    services = [{"id": row["service_id"], "startDate": row["start_date"], "endDate": row["end_date"],
                 "weekdays": [index + 1 for index, name in enumerate(weekdays) if row[name] == "1"]}
                for row in rows("calendar.txt") if row["service_id"] in service_ids]
    if "calendar_dates.txt" in archive.namelist():
        raise ValueError("New holiday exceptions require an importer/runtime update before publishing")
    result = {
        "schemaVersion": 1, "id": "transjakarta-corridor-1-" + checked_at[:10],
        "sourceURL": SOURCE, "attributionURL": "https://ppid.transjakarta.co.id/informasi/berkala",
        "licenseURL": "https://creativecommons.org/licenses/by/4.0/",
        "publisher": "PT Transportasi Jakarta", "checkedAt": checked_at,
        "lastModified": modified, "sourceSHA256": hashlib.sha256(data).hexdigest(),
        "modification": "Corridor 1 subset with stop-time offsets normalized to each trip's first departure. Shapes and fares omitted.",
        "agencyID": route["agency_id"], "routeID": route["route_id"], "routeName": route["route_long_name"],
        "category": route["route_desc"], "timeZone": "Asia/Jakarta",
        "stops": sorted(stops, key=lambda row: row["id"]), "services": services, "patterns": patterns,
    }
    source_keys = ["id", "sourceURL", "attributionURL", "licenseURL", "publisher", "checkedAt", "lastModified", "sourceSHA256", "modification"]
    result["source"] = {key: result.pop(key) for key in source_keys}
    return result


def geometry(data, feed, allow_partial=False):
    if hashlib.sha256(data).hexdigest() != feed["source"]["sourceSHA256"]:
        raise ValueError("Geometry ZIP must match the routing feed source hash")
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        if archive.getinfo("shapes.txt").file_size > 20_000_000:
            raise ValueError("Unbounded shapes table")
        with archive.open("shapes.txt") as file:
            rows = list(csv.DictReader(io.TextIOWrapper(file, encoding="utf-8-sig")))
    stops = {stop["id"]: stop for stop in feed["stops"]}
    patterns, missing = [], []
    shape_rows = {}
    for row in rows:
        shape_rows.setdefault(row["shape_id"], []).append(row)
    for pattern in feed["patterns"]:
        try:
            shape = sorted(shape_rows.get(pattern["shapeID"], []),
                           key=lambda row: int(row["shape_pt_sequence"]))
            points = [{"latitude": float(row["shape_pt_lat"]), "longitude": float(row["shape_pt_lon"])} for row in shape]
            if len(points) < 2:
                raise ValueError("Missing shape " + pattern["shapeID"])
            # Prefix minima give the closest ordered match, including repeated stops on loops.
            costs = [0.0] * len(points)
            predecessors = []
            for call in pattern["calls"]:
                stop = stops[call["stopID"]]
                best, previous = math.inf, 0
                next_costs, parents = [], []
                for index, point in enumerate(points):
                    if costs[index] < best:
                        best, previous = costs[index], index
                    distance = math.hypot((point["latitude"] - stop["latitude"]) * 111195,
                                          (point["longitude"] - stop["longitude"]) * 110537)
                    next_costs.append(best + distance * distance if distance <= 150 else math.inf)
                    parents.append(previous)
                predecessors.append(parents)
                costs = next_costs
            index = min(range(len(points)), key=lambda value: costs[value])
            if not math.isfinite(costs[index]):
                raise ValueError("No ordered shape match within 150 m for " + pattern["id"])
            indices = []
            for parents in reversed(predecessors):
                indices.append(index)
                index = parents[index]
            indices.reverse()
            patterns.append({"id": pattern["id"], "shapeID": pattern["shapeID"], "points": points,
                             "calls": [{"stopID": call["stopID"], "sequence": call["sequence"], "pointIndex": index}
                                       for call, index in zip(pattern["calls"], indices)]})
        except ValueError as error:
            if not allow_partial:
                raise
            missing.append({"id": pattern["id"], "reason": str(error)})
    return {"schemaVersion": 2 if allow_partial else 1, "sourceSHA256": feed["source"]["sourceSHA256"], "patterns": patterns, "missingPatterns": missing}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--geometry-output", type=Path)
    parser.add_argument("--feed", type=Path)
    parser.add_argument("--input-zip", type=Path)
    parser.add_argument("--allow-partial-geometry", action="store_true")
    args = parser.parse_args()
    if args.input_zip:
        if not args.feed or not args.geometry_output:
            parser.error("--input-zip requires --feed and --geometry-output")
        result = geometry(args.input_zip.read_bytes(), json.loads(args.feed.read_text()), allow_partial=args.allow_partial_geometry)
        args.geometry_output.write_text(json.dumps(result, indent=2) + "\n")
        print(f"Imported geometry for {len(result['patterns'])} patterns; {len(result['missingPatterns'])} unavailable")
        return
    if not args.output:
        parser.error("--output is required when downloading a feed")
    with urllib.request.urlopen(SOURCE, timeout=40) as response:
        data = response.read(20_000_001)
        modified = response.headers.get("Last-Modified", "Unknown")
    if len(data) > 20_000_000:
        raise ValueError("Feed exceeds the 20 MB import bound")
    checked_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    result = subset(data, checked_at, modified)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
    if args.geometry_output:
        args.geometry_output.write_text(json.dumps(geometry(data, result), indent=2) + "\n")
    print(f"Imported {len(result['patterns'])} patterns, {len(result['stops'])} boarding stops, SHA256 {result['source']['sourceSHA256']}")


if __name__ == "__main__":
    main()
