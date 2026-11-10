"""Test-only source audits across TJ services; never an application routing adapter."""

from collections import Counter, defaultdict
import csv
from datetime import date, timedelta
import hashlib
import io
import zipfile


def service_seconds(value):
    parts = value.split(":")
    if len(parts) != 3:
        raise ValueError(f"Invalid GTFS time: {value}")
    hour, minute, second = map(int, parts)
    if hour < 0 or not 0 <= minute < 60 or not 0 <= second < 60:
        raise ValueError(f"Invalid GTFS time: {value}")
    return hour * 3600 + minute * 60 + second


def regular_permission(call, action):
    # Values 2/3 require arrangements with the operator; they are not unconditional permission.
    return call.get(f"{action}_type", "") in ("", "0")


def service_operates(service, day):
    formatted = day.strftime("%Y%m%d")
    weekday = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"][day.weekday()]
    return service["start_date"] <= formatted <= service["end_date"] and service[weekday] == "1"


def conservative_board_at(frequencies, offset, ready, service, baseline):
    """Frequency-only diagnostic: full-headway wait, no walking/transfer/realtime promise."""
    if any((row.get("exact_times", "0") or "0") != "0" for row in frequencies):
        return None, "source_gap", "Exact-times service needs a separate scheduled-service interpretation."
    candidates = []
    current_day = ready // 86400
    for day_offset in [current_day - 1, current_day]:
        if not service_operates(service, baseline + timedelta(days=day_offset)):
            continue
        for row in frequencies:
            start = day_offset * 86400 + service_seconds(row["start_time"]) + offset
            end = day_offset * 86400 + service_seconds(row["end_time"]) + offset
            headway = int(row["headway_secs"])
            if headway <= 0 or start >= end:
                raise ValueError("Invalid frequency window or headway")
            board = max(ready, start) + headway
            if board < end:
                candidates.append(board)
    if not candidates:
        return None, "source_unavailable", "No boarding fits the source calendar/window under the full-headway assumption."
    return min(candidates), "source_available", "Source window admits a boarding under the authored full-headway assumption; no app route generated."


def audit_network(path, expected_hash, scenarios, baseline=date(2026, 11, 7)):
    if hashlib.sha256(path.read_bytes()).hexdigest() != expected_hash:
        raise ValueError("Network audit ZIP differs from the manifest SHA256")
    with zipfile.ZipFile(path) as archive:
        def rows(name):
            if archive.getinfo(name).file_size > 30_000_000:
                raise ValueError(f"Unbounded GTFS table: {name}")
            with archive.open(name) as stream:
                return list(csv.DictReader(io.TextIOWrapper(stream, encoding="utf-8-sig")))

        routes = {row["route_id"]: row for row in rows("routes.txt")}
        trips = rows("trips.txt")
        services = {row["service_id"]: row for row in rows("calendar.txt")}
        stops = {row["stop_id"]: row for row in rows("stops.txt")}
        calls, frequencies = defaultdict(list), defaultdict(list)
        for row in rows("stop_times.txt"):
            calls[row["trip_id"]].append(row)
        for row in rows("frequencies.txt"):
            frequencies[row["trip_id"]].append(row)
        transfers = rows("transfers.txt") if "transfers.txt" in archive.namelist() else []
        has_exceptions = "calendar_dates.txt" in archive.namelist()

    candidate_ids = {route for case in scenarios for route in case["routeCandidates"]}
    absent = sorted(candidate_ids - routes.keys())
    if absent:
        raise ValueError(f"Manifest TJ routes absent from source: {absent}")
    if any(route["agency_id"] != "Tije" for route in routes.values()):
        raise ValueError("TJ-only audit received a non-Tije route")

    observations, invariant_failures = [], []
    membership = defaultdict(set)
    for trip in trips:
        route = routes[trip["route_id"]]
        ordered = sorted(calls[trip["trip_id"]], key=lambda row: int(row["stop_sequence"]))
        windows = frequencies[trip["trip_id"]]
        base = {"routeID": trip["route_id"], "tripID": trip["trip_id"], "category": route["route_desc"],
                "directionID": trip.get("direction_id", ""), "evidenceMode": "tj_source_audit_only",
                "generatedAppJourney": False}

        def record(probe, outcome, detail, **values):
            observations.append(dict(base, probe=probe, outcome=outcome, detail=detail, **values))

        try:
            valid = len(ordered) >= 2 and all(
                service_seconds(row["arrival_time"]) <= service_seconds(row["departure_time"])
                and row["stop_id"] in stops for row in ordered)
            valid = valid and all(int(a["stop_sequence"]) < int(b["stop_sequence"])
                                  and service_seconds(a["departure_time"]) <= service_seconds(b["arrival_time"])
                                  for a, b in zip(ordered, ordered[1:]))
            if not valid:
                invariant_failures.append(trip["trip_id"])
            record("ordered_call_integrity", "source_valid" if valid else "source_conflict",
                   "Check actual ordered occurrences, time monotonicity and source stop references.", calls=len(ordered))
            restricted = [row for row in ordered if not regular_permission(row, "pickup") or not regular_permission(row, "drop_off")]
            record("boarding_restrictions", "source_valid",
                   "Restricted/on-request pickup/drop-off calls cannot be treated as unconditional boarding/alighting.",
                   restrictedCalls=len(restricted))
            service = services[trip["service_id"]]
            record("calendar_and_holidays", "source_gap",
                   "Weekly calendar evaluated; holiday exceptions are not inferred or applied by this source-only auditor.",
                   baselineActive=service_operates(service, baseline))
            pair = next(((a, b) for index, a in enumerate(ordered) if regular_permission(a, "pickup")
                         for b in reversed(ordered[index + 1:]) if regular_permission(b, "drop_off")
                         and a["stop_id"] != b["stop_id"]
                         and service_seconds(b["arrival_time"]) > service_seconds(a["departure_time"])), None)
            for call in ordered:
                if regular_permission(call, "pickup"):
                    membership[call["stop_id"]].add(trip["route_id"])
            for probe, clock in [("before_opening", None), ("morning", 9 * 3600),
                                 ("evening_access_delay_30m", 17 * 3600 + 1800),
                                 ("after_midnight", 86400 + 60), ("final_window_end", -1)]:
                if not pair or not windows:
                    record(probe, "source_gap", "No unconditional ordered stop pair or frequency windows.")
                    continue
                board, alight = pair
                offset = service_seconds(board["departure_time"]) - service_seconds(ordered[0]["departure_time"])
                ready = min(service_seconds(row["start_time"]) for row in windows) + offset - 3600 if clock is None else clock
                if clock == -1:
                    ready = max(service_seconds(row["end_time"]) for row in windows) + offset
                boarding, outcome, detail = conservative_board_at(windows, offset, ready, service, baseline)
                if has_exceptions:
                    boarding, outcome, detail = None, "source_gap", "Calendar exceptions require explicit handling before a source availability claim."
                record(probe, outcome, detail, readySeconds=ready, boardAtSeconds=boarding,
                       boardID=board["stop_id"], alightID=alight["stop_id"],
                       rideOffsetSeconds=service_seconds(alight["arrival_time"]) - service_seconds(board["departure_time"]))
        except (KeyError, ValueError) as error:
            # A malformed source is retained as evidence and makes the caller fail the run.
            invariant_failures.append(trip["trip_id"])
            record("source_parse", "source_conflict", str(error))

    interchange_candidates = [{"stopID": stop, "name": stops[stop]["stop_name"], "routes": sorted(route_ids),
                               "categories": sorted({routes[route]["route_desc"] for route in route_ids}),
                               "verifiedTransferDuration": None}
                              for stop, route_ids in membership.items() if len(route_ids) >= 2]
    interchange_candidates.sort(key=lambda row: (-len(row["routes"]), row["stopID"]))
    transfer_observations = [{"from": row["from_stop_id"], "to": row["to_stop_id"],
                              "type": row["transfer_type"], "minimumSeconds": row.get("min_transfer_time") or None,
                              "outcome": "source_gap" if not row.get("min_transfer_time") else "needs_access_validation"}
                             for row in transfers]
    return {
        "status": "audited_pinned_tj_network", "baselineWIBDate": baseline.isoformat(),
        "routeCount": len(routes), "patternCount": len(trips), "observations": observations,
        "observationCount": len(observations), "outcomeCounts": dict(Counter(row["outcome"] for row in observations)),
        "categoryPatternCounts": dict(Counter(routes[trip["route_id"]]["route_desc"] for trip in trips)),
        "categoryRouteCounts": dict(Counter(row["route_desc"] for row in routes.values())),
        "candidateRouteIDs": sorted(candidate_ids), "invariantFailures": sorted(set(invariant_failures)),
        "sharedBoardingStopCount": len(interchange_candidates), "sharedBoardingCandidates": interchange_candidates[:20],
        "explicitTransfers": transfer_observations,
        "limitations": ["Source-window audits are not application router results.",
                        "Shared boarding stops are only interchange candidates; no walking, paid-area, or transfer duration is inferred.",
                        "Exact-times service and absent calendar exceptions remain explicit gaps.",
                        "The full-headway source diagnostic does not predict vehicle arrivals."],
    }
