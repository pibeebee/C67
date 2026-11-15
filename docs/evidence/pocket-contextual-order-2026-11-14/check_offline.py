"""Independent source/shape checks and NOAA approximate solar cross-check; no API."""
import copy
from datetime import datetime, timedelta
import importlib.util
import json
import math
from pathlib import Path
import sys

from astral import Observer
from astral.sun import elevation, sunrise, sunset

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("context_experiment", HERE / "experiment.py")
e = importlib.util.module_from_spec(spec)
spec.loader.exec_module(e)


def noaa_geometric_elevation(point, instant):
    # Independent approximation from NOAA's General Solar Position Calculations,
    # https://gml.noaa.gov/grad/solcalc/solareqns.PDF (not an Astral function).
    hour = instant.hour + instant.minute/60 + instant.second/3600
    days = 366 if instant.year % 4 == 0 and (instant.year % 100 != 0 or instant.year % 400 == 0) else 365
    gamma = 2*math.pi/days*(instant.timetuple().tm_yday-1+(hour-12)/24)
    eq = 229.18*(0.000075+0.001868*math.cos(gamma)-0.032077*math.sin(gamma)-0.014615*math.cos(2*gamma)-0.040849*math.sin(2*gamma))
    decl = 0.006918-0.399912*math.cos(gamma)+0.070257*math.sin(gamma)-0.006758*math.cos(2*gamma)+0.000907*math.sin(2*gamma)-0.002697*math.cos(3*gamma)+0.00148*math.sin(3*gamma)
    true_minutes = hour*60+eq+4*point["longitude"]-60*instant.utcoffset().total_seconds()/3600
    angle = math.radians(true_minutes/4-180)
    lat = math.radians(point["latitude"])
    cos_zenith = math.sin(lat)*math.sin(decl)+math.cos(lat)*math.cos(decl)*math.cos(angle)
    return 90-math.degrees(math.acos(max(-1,min(1,cos_zenith))))


def control(case):
    stops = []
    for place in case["places"]:
        ident = place["id"]
        w = [r["id"] for r in case["weatherSources"] if r["placeID"] == ident]
        light = next((r["id"] for r in case["solarWindows"] if r["placeID"] == ident), None)
        stops.append(dict(placeID=ident, activity=dict(suggestion="Synthetic validator control",basis="unknown"),
            role="main" if ident == case["mainSpotID"] else "supporting",
            duration=dict(minMinutes=10,maxMinutes=20,rationale="Fixture only",basis="experience_estimate"),
            durationUnknownReason=None, preferredDayPart="flexible", reason="Fixture only",
            weather=dict(sourceRefs=w,advice="Fixture only",status="available" if w else "unavailable"),
            light=dict(windowRef=light,priority="unknown",advice="Fixture only"), uncertainties=["Unknown venue facts"]))
    return dict(answer=dict(status="proposed",orderedIDs=[p["id"] for p in case["places"]],
        tripRationale="Validator control only",stops=stops,alternativeOrder=None,tradeoffs=[],
        uncertainties=["No availability or arrival guarantee"]),
        provider=dict(model="gpt-6-luna",reasoning=dict(effort="max"),completionStatus="completed"))


def main():
    source = json.loads((HERE / "inputs.json").read_text())
    cases = {x["key"]:x["input"] for x in source["cases"]}
    checks = []
    def check(name, predicate):
        assert predicate, name
        checks.append(name)
    for key, case in cases.items():
        e.validate_context(case)
        check("valid-context-"+key, True)
    check("exact-repeat-input", cases["A3-clear-photo"] == cases["B10-exact-repeat"])
    for key in ["A1-no-context", "A3-clear-photo", "B8-ambiguous-setting", "B9-competing-light"]:
        check("validator-accepts-control-"+key,e.validate(cases[key],control(cases[key]))["structurePassed"])
    good = cases["A3-clear-photo"]
    def reject_context(name, mutate):
        candidate = copy.deepcopy(good)
        mutate(candidate)
        try:e.validate_context(candidate)
        except (ValueError,KeyError):check(name,True)
        else:raise AssertionError(name)
    reject_context("reject-percent-in-probability-field",lambda c:c["weatherSources"][0]["hourlySamples"][0].update(precipitationChance=85))
    reject_context("reject-nan-cloud",lambda c:c["weatherSources"][0]["hourlySamples"][0].update(cloudCover=float("nan")))
    reject_context("reject-negative-amount",lambda c:c["weatherSources"][0]["hourlySamples"][0].update(precipitationAmountMM=-1))
    reject_context("reject-wrong-location",lambda c:c["weatherSources"][0].update(coordinates=dict(latitude=0,longitude=0)))
    reject_context("reject-wrong-date",lambda c:c["weatherSources"][0].update(date="2026-11-16"))
    reject_context("reject-wrong-zone",lambda c:c["weatherSources"][0].update(timeZone="UTC"))
    reject_context("reject-expired-source",lambda c:c["weatherSources"][0].update(expiresAt=(e.parse(c["planningContext"]["checkedAt"])-timedelta(seconds=1)).isoformat()))
    reject_context("reject-future-retrieval",lambda c:c["weatherSources"][0].update(retrievedAt=(e.parse(c["planningContext"]["checkedAt"])+timedelta(days=1)).isoformat()))
    reject_context("reject-duplicate-reference",lambda c:c["weatherSources"].append(copy.deepcopy(c["weatherSources"][0])))
    reject_context("reject-invalid-hour-coverage",lambda c:c["weatherSources"][0]["hourlySamples"][0].update(end=c["weatherSources"][0]["hourlySamples"][0]["start"]))
    reject_context("reject-reversed-solar-window",lambda c:c["solarWindows"][0].update(end=c["solarWindows"][0]["start"]))
    def reject_answer(name, mutate):
        answer = control(good)
        mutate(answer["answer"])
        check(name,not e.validate(good,answer)["structurePassed"])
    reject_answer("reject-duplicate-destination",lambda a:a["orderedIDs"].__setitem__(0,a["orderedIDs"][1]))
    reject_answer("reject-new-alternative-destination",lambda a:a.update(alternativeOrder=["new-place"]))
    reject_answer("reject-inverted-duration",lambda a:a["stops"][0]["duration"].update(minMinutes=40,maxMinutes=20))
    reject_answer("reject-zero-duration",lambda a:a["stops"][0]["duration"].update(minMinutes=0))
    reject_answer("reject-bool-duration",lambda a:a["stops"][0]["duration"].update(minMinutes=True))
    reject_answer("reject-invented-duration-basis",lambda a:a["stops"][0]["duration"].update(basis="operator_rule"))
    reject_answer("reject-cross-place-weather",lambda a:a["stops"][1]["weather"].update(sourceRefs=["W1"]))
    reject_answer("reject-cross-place-light",lambda a:a["stops"][1]["light"].update(windowRef="L1-evening"))
    reject_answer("reject-fake-weather-availability",lambda a:a["stops"][0]["weather"].update(status="unavailable"))
    reject_answer("reject-invented-fixture-facility",lambda a:a["stops"][0]["activity"].update(basis="fixture_attribute"))
    unknown = control(good)
    unknown["answer"]["stops"][0].update(duration=None,durationUnknownReason="Insufficient activity context")
    check("allow-explicit-unknown-duration",e.validate(good,unknown)["structurePassed"])
    # Bind original source objects by ID; model strings never become source values.
    before = json.dumps(good,sort_keys=True)
    source_index={x["id"]:x for x in good["weatherSources"]+good["solarWindows"]}
    for stop in control(good)["answer"]["stops"]:
        for ref in stop["weather"]["sourceRefs"] + ([stop["light"]["windowRef"]] if stop["light"]["windowRef"] else []):
            bound=copy.deepcopy(source_index[ref]);check("source-binding-"+stop["placeID"]+"-"+ref,bound==source_index[ref])
    check("source-values-remain-immutable",json.dumps(good,sort_keys=True)==before)
    cloud = cases["A5-dry-cloudy"]
    check("cloud-change-preserves-solar",cloud["solarWindows"]==good["solarWindows"])
    check("cloud-change-preserves-rain-probabilities",[h["precipitationChance"] for w in cloud["weatherSources"] for h in w["hourlySamples"]]==[h["precipitationChance"] for w in good["weatherSources"] for h in w["hourlySamples"]])
    check("polar-no-crossing-remains-unavailable",not e.solar([dict(id="polar",coordinates=dict(latitude=90,longitude=0))],"2026-06-21","UTC"))
    comparisons=[]
    points=good["places"][:1]
    for when in ["2026-02-15", "2026-06-15", "2026-11-15"]:
        rows=e.solar(points,when)
        for row in rows:
            observer=Observer(**row["coordinates"])
            for boundary in ["start","end"]:
                instant=e.parse(row[boundary])
                actual=elevation(observer,instant,with_refraction=False)
                independent=noaa_geometric_elevation(row["coordinates"],instant)
                delta=abs(actual-independent)
                check("NOAA-position-"+when+"-"+row["period"]+"-"+boundary,delta<0.75)
                comparisons.append(dict(date=when,period=row["period"],boundary=boundary,
                    astralGeometricElevation=round(actual,5),noaaApproxElevation=round(independent,5),differenceDegrees=round(delta,5)))
        day=e.date.fromisoformat(when);observer=Observer(**points[0]["coordinates"])
        check("sunrise-within-morning-"+when,e.parse(rows[0]["start"])<sunrise(observer,day,e.ZoneInfo(e.TZ))<e.parse(rows[0]["end"]))
        check("sunset-within-evening-"+when,e.parse(rows[1]["start"])<sunset(observer,day,e.ZoneInfo(e.TZ))<e.parse(rows[1]["end"]))
        check("local-zone-date-"+when,all(e.parse(r["start"]).utcoffset()==timedelta(hours=7) and r["start"].startswith(when) for r in rows))
    artifact=dict(passed=len(checks),checks=checks,solarComparisons=comparisons,
        limitation="NOAA simplified position cross-check is approximate; not field-observed golden light or independent photographic validation.")
    (HERE/"offline-checks.json").write_text(json.dumps(artifact,indent=2)+"\n")
    print(json.dumps(dict(passed=len(checks),maxSolarDifferenceDegrees=max(x["differenceDegrees"] for x in comparisons))))


if __name__ == "__main__":main()
