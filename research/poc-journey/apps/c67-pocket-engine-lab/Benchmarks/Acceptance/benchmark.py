"""Freeze controlled Pocket inputs and audit raw benchmark JSONL."""
import argparse
import hashlib
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
from statistics import median

WIB = timezone(timedelta(hours=7))
DAY = datetime(2026, 11, 14, tzinfo=WIB)
CHECKED = "2026-11-10T00:00:00Z"
EXPIRES = "2026-11-20T00:00:00Z"
SOURCE = "https://example.invalid/acceptance-fixture"


def stamp(value):
    return value.isoformat().replace("+00:00", "Z")


def venue(key, distance, *, category="art", windows=((480, 1140),), access="supported",
          facets=(), dated=None, expired=False):
    def fact(field, status):
        return dict(field=field, status=status, value="Fixture", sourceURL=SOURCE,
                    quote="Synthetic test evidence", checkedAt=CHECKED, expiresAt=EXPIRES)

    intervals = [
        dict(weekday=7, startMinute=start, endMinute=end, date=date)
        for date, rows in ((None, windows), ("2026-11-14", dated or ()))
        for start, end in rows
    ]
    facts = [fact("publicAccess", access)] + [fact(field, status) for field, status in facets]
    hours = dict(intervals=intervals, sourceURL=SOURCE, quote="Synthetic opening hours",
                 checkedAt=CHECKED, expiresAt="2026-11-13T00:00:00Z" if expired else EXPIRES)
    return dict(id=key, name={"textile-pin": "Museum Tekstil (label lokal)"}.get(key, key),
                branch="", address="", coordinate=dict(latitude=-6.2, longitude=106.8 + distance / 1000),
                categories=[category], aliases=[], sourceURLs=[SOURCE], operatorURLs=[],
                license="Synthetic fixture", facts=facts, hours=hours)


def edge(source, destination, minutes, start=0, fail_first=False):
    return {"from": source, "to": destination, "minutes": minutes, "fromMinute": start, "failFirst": fail_first}


def trial(key, places, durations, *, required=None, departure=540, deadline=1140,
          want=1, eta=10, budget=60, edges=(), weather=None, avoid_rain=False,
          preferences=None, categories=("art",), departure_range=None, appointment=None,
          preferred_time=None, last=None, retry=False, should_plan=True, ranking=None):
    required = [places[0]["id"]] if required is None else required
    choices = [
        dict(venueID=v["id"], required=v["id"] in required, durationMinutes=duration, override=None)
        for v, duration in zip(places, durations, strict=True)
    ]
    return dict(id=key, venues=places, choices=choices, categories=list(categories),
                preferences=preferences or {}, departure=departure, deadline=deadline,
                returnToOrigin=True, maxWait=30, avoidRain=avoid_rain, budget=budget,
                defaultETA=eta, edges=list(edges), weather=weather or {}, rankingOnly=ranking is not None,
                expected=dict(shouldPlan=should_plan, want=want, departureRange=departure_range,
                              appointment=appointment, preferredTime=preferred_time, last=last,
                              retry=retry, ranking=ranking))


def cases():
    public = venue("public", 1, category="cafe", facets=(("reading", "supported"),))
    category_only = venue("category-only", 2, category="cafe")
    restricted = venue("restricted", 3, category="cafe", facets=(("reading", "contradicted"),))
    conflicting = venue("conflicting", 4, category="cafe",
                        facets=(("reading", "supported"), ("reading", "contradicted")))
    dinner = venue("dinner", 1, category="japanese_cuisine", windows=((690, 1320),))
    museum = venue("macan", 1, windows=((600, 1080),))
    park = venue("park", 2, category="garden", facets=(("outdoor", "supported"),))
    aquarium = venue("aquarium", 3, category="animal", windows=((600, 1260),))
    gallery = venue("gallery", 4)
    textile = venue("textile-pin", 5, windows=((540, 960),))
    plain = venue("plain", 6)
    return [
        trial("ranking-required-evidence", [public, category_only, restricted, conflicting], [45] * 4,
              categories=("cafe",), preferences={"reading": "required"},
              ranking={"eligible": ["public"], "unknown": ["category-only", "conflicting"]}),
        trial("ranking-liked-evidence", [category_only, public, restricted], [45] * 3,
              categories=("cafe",), preferences={"reading": "liked"},
              ranking={"eligible": ["public", "category-only", "restricted"], "unknown": ["category-only"]}),
        trial("five-places-coordinate-pin", [museum, park, aquarium, gallery, textile], [60, 30, 60, 30, 45],
              departure=570, want=5, categories=("animal", "art", "garden")),
        trial("deadline-includes-return", [plain], [60], deadline=619, should_plan=False),
        trial("six-places-early-close", [venue(f"stop-{i}", i, windows=((480, 660 if i == 6 else 1200),))
                                            for i in range(1, 7)], [60] * 6, want=6,
              required=[f"stop-{i}" for i in range(1, 7)], deadline=1200),
        trial("flexible-departure-dinner", [dinner], [50], departure=480,
              departure_range=[480, 1100], preferred_time=["dinner", 1090, 20]),
        trial("fixed-departure-dinner-control", [dinner], [50], departure=1070,
              preferred_time=["dinner", 1090, 20]),
        trial("dinner-last", [dinner, gallery, textile | {"hours": gallery["hours"]}], [50, 30, 20],
              departure=1015, want=3, eta=5, last="dinner",
              preferred_time=["dinner", 1080, 0]),
        trial("macan-exact-appointment", [museum, gallery, aquarium], [60, 45, 60],
              departure=750, want=3, appointment=["macan", 840]),
        trial("macan-soft-time-five-places", [museum, park, aquarium, gallery, textile],
              [60, 30, 60, 30, 45], departure=750, want=5,
              preferred_time=["macan", 840, 20], categories=("animal", "art", "garden")),
        trial("weather-safe-later-slot", [park], [45], departure=630, avoid_rain=True,
              weather={"park": dict(rainBefore=660, early=0.8, late=0.1)}),
        trial("weather-unknown", [park], [45], departure=630, avoid_rain=True, should_plan=False),
        trial("time-dependent-eta", [venue("a", 1), venue("b", 2)], [40, 40],
              required=["a", "b"], want=2, deadline=670,
              edges=[edge("a", "b", 80, start=570), edge("b", "a", 8), edge("a", "origin", 10)]),
        trial("eta-permanently-unavailable", [plain], [45], should_plan=False,
              edges=[edge("origin", "plain", None)]),
        trial("eta-transient-then-recovers", [plain], [45], retry=True,
              edges=[edge("origin", "plain", 10, fail_first=True)]),
        trial("unknown-access-optional", [plain, venue("unverified", 7, access="unknown")], [45, 45]),
        trial("expired-hours-required", [venue("expired", 1, expired=True)], [45], should_plan=False),
        trial("dated-hours-and-split-session",
              [venue("short-session", 1, windows=((480, 1080),), dated=((540, 555), (600, 690)))],
              [35], departure=575, deadline=690),
    ]


def minute(value):
    return (datetime.fromisoformat(value) - DAY).total_seconds() / 60


def visit_windows(place):
    hours = place["hours"]
    if datetime.fromisoformat(hours["expiresAt"]) <= DAY:
        return []
    rows = hours["intervals"]
    dated = [row for row in rows if row["date"] == "2026-11-14"]
    return [(row["startMinute"], row["endMinute"]) for row in dated or rows if row["weekday"] == 7]


def travel(case, source, dest, departure, *, recovered):
    candidates = [leg for leg in case["edges"] if
                  (leg["from"], leg["to"]) == (source, dest) and departure >= leg["fromMinute"]]
    if not candidates:
        return case["defaultETA"]
    leg = candidates[-1]
    return None if leg["failFirst"] and not recovered else leg["minutes"]


def weather_allowed(case, place, start):
    if not case["avoidRain"]:
        return True
    outdoor = next((f["status"] for f in place["facts"] if f["field"] == "outdoor"), "unknown")
    if outdoor != "supported":
        return outdoor == "contradicted"
    weather = case["weather"].get(place["id"])
    if not weather:
        return False
    chance = weather["early"] if start < weather["rainBefore"] else weather["late"]
    return chance is not None and chance <= 0.5


def preference_errors(expected, stops):
    times = {key: start for key, start, _ in stops}
    errors = []
    if len(stops) < expected["want"]:
        errors.append("requested stop count")
    if (last := expected["last"]) and stops[-1][0] != last:
        errors.append("required last stop")
    if (appointment := expected["appointment"]) and times.get(appointment[0]) != appointment[1]:
        errors.append("exact appointment")
    if (preferred := expected["preferredTime"]):
        actual = times.get(preferred[0])
        if actual is None or abs(actual - preferred[1]) > preferred[2]:
            errors.append("preferred-time tolerance")
    return errors


def witness(case):
    """Enumerate feasible orders and integer starts on appointment/weather cases."""
    wanted = case["expected"]
    places = {p["id"]: p for p in case["venues"]}
    choices = {x["venueID"]: x for x in case["choices"]}
    required = {k for k, x in choices.items() if x["required"]}
    eligible = {k for k, p in places.items() if
                any(f["field"] == "publicAccess" and f["status"] == "supported" for f in p["facts"])}

    def search(depart, now, source, remaining, stops):
        if stops and not required.intersection(remaining) and not preference_errors(wanted, stops):
            eta = travel(case, source, "origin", now, recovered=wanted["retry"])
            if eta is not None and now + eta <= case["deadline"]:
                return dict(departure=depart, stops=stops, finish=now + eta)
        for key in sorted(remaining & eligible):
            if wanted["last"] == key and len(stops) + 1 < wanted["want"]:
                continue
            eta = travel(case, source, key, now, recovered=wanted["retry"])
            if eta is None:
                continue
            arrival = now + eta
            duration = choices[key]["durationMinutes"]
            for opens, closes in visit_windows(places[key]):
                earliest = max(opens, arrival)
                latest = min(closes - duration, case["deadline"] - duration, arrival + case["maxWait"])
                times = range(earliest, latest + 1) if wanted["appointment"] or case["avoidRain"] else (earliest,)
                for start in times:
                    if start > latest or not weather_allowed(case, places[key], start):
                        continue
                    end = start + duration
                    result = search(depart, end, key, remaining - {key}, [*stops, (key, start, end)])
                    if result:
                        return result
        return None

    bounds = wanted["departureRange"]
    departures = range(bounds[0], bounds[1] + 1, 5) if bounds else [case["departure"]]
    return next((plan for d in departures if (plan := search(d, d, "origin", set(choices), []))), None)


def audit(case, run):
    expected = case["expected"]
    errors = []
    hard = []
    if run["etaCalls"] > case["budget"]:
        hard.append("ETA budget exceeded")
    if expected["ranking"] is not None:
        rank = run["ranking"]
        actual = dict(eligible=[row["id"] for row in rank if row["eligible"]],
                      unknown=sorted(row["id"] for row in rank if row["unknowns"]))
        if actual != expected["ranking"]:
            errors.append("ranking evidence")
        return errors, hard
    plan = run.get("itinerary")
    if plan is None:
        if expected["shouldPlan"]:
            errors.append("no itinerary")
        if not run.get("error"):
            hard.append("missing failure diagnostic")
        return errors, hard
    if not expected["shouldPlan"]:
        hard.append("itinerary returned for impossible request")
    places = {p["id"]: p for p in case["venues"]}
    choices = {x["venueID"]: x for x in case["choices"]}
    visits = plan["stops"]
    ids = [stop["venueID"] for stop in visits]
    if not {k for k, x in choices.items() if x["required"]}.issubset(ids) or len(ids) != len(set(ids)):
        hard.append("required stops or uniqueness")
    if set(ids) - places.keys():
        return errors, hard + ["unrecognized destination"]
    source = "origin"
    now = minute(plan["departure"])
    bounds = expected["departureRange"] or [case["departure"], case["departure"]]
    if not bounds[0] <= now <= bounds[1]:
        hard.append("departure outside user window")
    stops = []
    for stop in visits:
        key = stop["venueID"]
        place = places[key]
        if stop["name"] != place["name"] or stop["coordinate"] != place["coordinate"]:
            hard.append("pin name or coordinate changed")
        departure, arrival, start, end = (minute(stop[field]) for field in
                                          ("departure", "arrival", "visitStart", "visitEnd"))
        eta = travel(case, source, key, departure, recovered=True)
        if eta is None or departure != now or arrival != departure + eta or stop["driveSeconds"] != eta * 60:
            hard.append("inconsistent ETA or temporal chain")
        if start < arrival or start - arrival > case["maxWait"] or end - start != choices[key]["durationMinutes"]:
            hard.append("invalid wait or visit duration")
        if not any(a <= start and end <= b for a, b in visit_windows(place)):
            hard.append("outside confirmed opening window")
        if not any(f["field"] == "publicAccess" and f["status"] == "supported" for f in place["facts"]):
            hard.append("unverified access")
        if not weather_allowed(case, place, start):
            hard.append("weather condition")
        stops.append((key, start, end))
        now, source = end, key
    eta = travel(case, source, "origin", now, recovered=True)
    finish = minute(plan["finish"])
    if eta is None or plan["returnSeconds"] != eta * 60 or finish != now + eta or finish > case["deadline"]:
        hard.append("invalid return or deadline")
    errors.extend(preference_errors(expected, stops))
    return errors, hard


def review(fixtures, raw):
    data = json.loads(fixtures.read_text())
    rows = [json.loads(line) for line in raw.read_text().splitlines()]
    if set(r["id"] for r in rows) != {c["id"] for c in data}:
        raise SystemExit("Missing or unexpected case")
    report = []
    for case in data:
        runs = sorted((row for row in rows if row["id"] == case["id"]), key=lambda row: row["iteration"])
        if len(runs) < 2 or [r["iteration"] for r in runs] != list(range(len(runs))):
            raise SystemExit("Missing or duplicate iteration: " + case["id"])
        measured = runs[1:]
        reference = None if case["rankingOnly"] else witness(case)
        if not case["rankingOnly"] and bool(reference) != case["expected"]["shouldPlan"]:
            raise SystemExit("Expectation does not match reference: " + case["id"])
        audits = [audit(case, r) for r in measured]
        errors = sorted(set(message for e, _ in audits for message in e))
        hard = sorted(set(message for _, h in audits for message in h))
        first = measured[0]
        plan = first.get("itinerary")
        signatures = {
            json.dumps([
                r["ranking"], r.get("error"), r["etaCalls"], r["etaFailures"], r["weatherCalls"],
                [r["itinerary"][k] for k in ("stops", "finish", "searchTruncated")] if r.get("itinerary") else None
            ], sort_keys=True)
            for r in measured
        }
        if len(signatures) != 1:
            errors.append("non-deterministic outcome")
        report.append(dict(id=case["id"], passed=not (errors or hard), gaps=errors,
                           hardViolations=hard, witness=reference, observedError=first.get("error"),
                           observedStops=[(s["venueID"], minute(s["visitStart"])) for s in plan["stops"]] if plan else [],
                           measuredRuns=len(measured), medianMs=median(r["elapsedMs"] for r in measured),
                           etaCalls=first["etaCalls"], etaFailures=first["etaFailures"],
                           weatherCalls=first["weatherCalls"], truncated=plan["searchTruncated"] if plan else
                           "Batas pencarian tercapai" in first.get("error", "")))
    return dict(passed=sum(row["passed"] for row in report), total=len(report), cases=report)


if __name__ == "__main__":
    cli = argparse.ArgumentParser(description=__doc__)
    commands = cli.add_subparsers(dest="command", required=True)
    freeze = commands.add_parser("freeze")
    freeze.add_argument("output", type=Path)
    score = commands.add_parser("score")
    score.add_argument("fixtures", type=Path)
    score.add_argument("raw", type=Path)
    args = cli.parse_args()
    if args.command == "freeze":
        with args.output.open("x") as stream:
            json.dump(cases(), stream, indent=2, sort_keys=True)
            stream.write("\n")
        print(hashlib.sha256(args.output.read_bytes()).hexdigest())
    else:
        print(json.dumps(review(args.fixtures, args.raw), indent=2))
