"""Two bounded real-forecast fallback probes; no UI/app changes or retries."""
import argparse
import copy
from datetime import date, datetime, timedelta, timezone
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import subprocess
import sys
from urllib.parse import urlencode
from zoneinfo import ZoneInfo

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("contextual", HERE.parent / "pocket-contextual-order-2026-11-14/experiment.py")
context = importlib.util.module_from_spec(spec)
spec.loader.exec_module(context)
DAY = "2026-11-16"  # Tomorrow relative to the user's Asia/Jakarta date, 2026-11-15.
ZONE = "Asia/Jakarta"
FIELDS = ["precipitation_probability", "precipitation", "rain", "showers", "snowfall", "cloud_cover"]


def forecast_url(places):
    return "https://api.open-meteo.com/v1/forecast?" + urlencode(dict(
        latitude=",".join(str(p["coordinates"]["latitude"]) for p in places),
        longitude=",".join(str(p["coordinates"]["longitude"]) for p in places),
        hourly=",".join(FIELDS), daily="sunrise,sunset", timezone=ZONE,
        start_date=DAY, end_date=DAY, timeformat="unixtime", precipitation_unit="mm"))


def normalize(raw, places, fetched):
    if not isinstance(raw,list) or len(raw)!=len(places):
        raise ValueError("Expected one forecast per requested coordinate")
    records=[]
    for index,(item,place) in enumerate(zip(raw,places)):
        if item.get("timezone")!=ZONE or item.get("utc_offset_seconds")!=25200:
            raise ValueError("Forecast timezone mismatch")
        units=item["hourly_units"]
        expected={"time":"unixtime","precipitation_probability":"%","precipitation":"mm",
                  "rain":"mm","showers":"mm","snowfall":"cm","cloud_cover":"%"}
        if any(units.get(k)!=v for k,v in expected.items()):
            raise ValueError("Unexpected forecast units")
        hourly=item["hourly"]
        stamps=hourly["time"]
        if not stamps or any(len(hourly[k])!=len(stamps) for k in FIELDS):
            raise ValueError("Missing/misaligned hourly series")
        if len(set(stamps))!=len(stamps) or any(b-a!=3600 for a,b in zip(stamps,stamps[1:])):
            raise ValueError("Non-contiguous provider hours")
        samples=[]
        # API values at T describe precipitation over T-1h..T, cloud at T.
        # Retain selected intervals including both calculated light opportunities.
        for i,stamp in enumerate(stamps):
            end=datetime.fromtimestamp(stamp,ZoneInfo(ZONE))
            if end.hour not in {6,10,13,16,18,19,21}:continue
            start=end-timedelta(hours=1)
            if start.date().isoformat()!=DAY:raise ValueError("Wrong forecast date")
            values={k:hourly[k][i] for k in FIELDS}
            if any(type(v) not in {int,float} or not math.isfinite(v) for v in values.values()):
                raise ValueError("Null/non-finite forecast sample; not filling it")
            if any(not 0<=values[k]<=100 for k in ["precipitation_probability","cloud_cover"]):
                raise ValueError("Probability/cloud percent outside bounds")
            if any(values[k]<0 for k in ["precipitation","rain","showers","snowfall"]):
                raise ValueError("Negative precipitation amount")
            liquid=values["rain"]+values["showers"]
            kind="mixed" if liquid>0 and values["snowfall"]>0 else "snow" if values["snowfall"]>0 else "rain" if liquid>0 else "none"
            label="pagi" if start.hour<11 else "siang" if start.hour<15 else "sore" if start.hour<18 else "malam"
            samples.append(dict(period=label,start=start.isoformat(),end=end.isoformat(),
                precipitationChance=values["precipitation_probability"]/100,
                cloudCover=values["cloud_cover"]/100,precipitationType=kind,
                precipitationAmountMM=values["precipitation"],rainAmountMM=values["rain"],
                showersAmountMM=values["showers"],snowfallCM=values["snowfall"],
                cloudCoverValidAt=end.isoformat(),providerRowIndex=i))
        if len(samples)!=7:raise ValueError("Required sampled intervals unavailable")
        grid=dict(latitude=item["latitude"],longitude=item["longitude"])
        displacement=context.previous.km(place["coordinates"],grid)
        if displacement>50:raise ValueError("Provider grid far from requested coordinate")
        records.append(dict(id=f"OM{index+1}",placeID=place["id"],coordinates=place["coordinates"],
            gridCoordinates=grid,requestedToReturnedGridKM=round(displacement,3),date=DAY,timeZone=ZONE,
            source="Open-Meteo live forecast; https://open-meteo.com/; attribution CC BY 4.0",
            kind="live_forecast",retrievedAt=fetched,
            expiresAt=(context.parse(fetched)+timedelta(minutes=30)).isoformat(),
            freshnessPolicy="Local 30-minute test freshness deadline, not provider-issued expiry/issue time",
            coverage="Selected one-hour precipitation intervals; cloud is instantaneous at interval end; other hours omitted from model context",
            probabilitySemantics="Preceding-hour precipitation probability, not whole-visit/day or rain-only probability",
            typeSemantics="Derived from forecast liquid/snow amounts; none means zero predicted amount, not zero precipitation probability",
            hourlySamples=samples))
    return records


def prepare():
    manifest=HERE/"inputs.json"
    if manifest.exists():
        raise SystemExit("Refusing overwrite of this registered run")
    prior=json.loads((context.HERE/"inputs.json").read_text())
    source={row["key"]:row["input"] for row in prior["cases"]}
    primary=copy.deepcopy(source["A3-clear-photo"])
    url=forecast_url(primary["places"])
    fetch_path=HERE/"forecast-fetch.json"
    if fetch_path.exists():
        fetch=json.loads(fetch_path.read_text())
        if fetch["url"]!=url or fetch["httpStatus"]!="200" or fetch["curlExit"]:
            raise SystemExit("Previous fetch failed/changed; no retry")
        raw=json.loads((HERE/"forecast-raw.json").read_text())
        fetched,status=fetch["fetchedAt"],fetch["httpStatus"]
        print("Reusing the exact saved HTTP snapshot for normalization; no network request.")
    else:
        started=datetime.now(timezone.utc).isoformat()
        result=subprocess.run(["/usr/bin/curl","--silent","--show-error","--proto","=https",
            "--connect-timeout","15","--max-time","45","--user-agent","C67-headless-weather-test/1.0",
            "--write-out","\n%{http_code}",url],capture_output=True,text=True,timeout=50)
        body,_,status=result.stdout.rpartition("\n")
        fetched=datetime.now(timezone.utc).isoformat()
        fetch=dict(url=url,startedAt=started,fetchedAt=fetched,httpStatus=status,curlExit=result.returncode,
                   provider="Open-Meteo",fallbackReason="WeatherKit REST configuration unavailable; fallback explicitly authorized by user on 2026-11-15")
        fetch_path.write_text(json.dumps(fetch,indent=2)+"\n")
        if result.returncode or status!="200":raise SystemExit("Actual forecast fetch failed; no retry or synthetic replacement")
        raw=json.loads(body)
        (HERE/"forecast-raw.json").write_text(json.dumps(raw,indent=2)+"\n")
    records=normalize(raw,primary["places"],fetched)
    primary["caseID"]="C11"
    primary["planningContext"]=dict(date=DAY,timeZone=ZONE,dateSource="system_suggested_test_date",checkedAt=fetched,
        clientCurrentDate="2026-11-15")
    primary["weatherSources"]=records
    primary["solarWindows"]=context.solar([p for p in primary["places"] if p["id"]==primary["mainSpotID"]],DAY,ZONE)
    primary["dayPartVocabulary"]=dict(morning="pagi",afternoon="siang",evening="sore",night="malam",flexible="fleksibel")
    primary["inputProvenance"]="Actual Open-Meteo forecast fetched once as authorized WeatherKit fallback. Original selected names/pins; controlled preference/origin/endpoint fixtures; calculated solar geometry. Forecast is not an observation. No synthetic weather replacement or verified operator facts."
    secondary=copy.deepcopy(primary)
    secondary["caseID"]="C12"
    secondary["userPreferences"]=copy.deepcopy(source["A6-photo-deprioritized"]["userPreferences"])
    checks=[]
    for case in [primary,secondary]:context.validate_context(case)
    checks.append("date/zone/location/probability/range/reference context checks pass")
    assert primary["weatherSources"]==secondary["weatherSources"]
    checks.append("same actual forecast snapshot in both preference variants")
    from astral import Observer
    from astral.sun import sunrise,sunset
    solar_comparisons=[]
    for item,place in zip(raw,primary["places"]):
        daily=item["daily"]
        assert item["daily_units"]["sunrise"]==item["daily_units"]["sunset"]=="unixtime"
        observer=Observer(**place["coordinates"])
        comparison=dict(placeID=place["id"])
        for event,func in [("sunrise",sunrise),("sunset",sunset)]:
            provider=datetime.fromtimestamp(daily[event][0],ZoneInfo(ZONE))
            assert provider.date().isoformat()==DAY
            calculated=func(observer,date.fromisoformat(DAY),ZoneInfo(ZONE))
            delta=abs((calculated-provider).total_seconds())
            assert delta<300,(event,delta)
            comparison[event+"DifferenceSeconds"]=round(delta,3)
        solar_comparisons.append(comparison)
    checks.append("actual provider sunrise/sunset sanity comparison within predeclared 300s tolerance at all five pins")
    park=next(p for p in primary["places"] if p["id"]==primary["mainSpotID"])
    w=next(w for w in records if w["placeID"]==park["id"])
    for window in primary["solarWindows"]:
        cursor=context.parse(window["start"])
        for sample in w["hourlySamples"]:
            start,end=context.parse(sample["start"]),context.parse(sample["end"])
            if start<=cursor<end:cursor=end
        assert cursor>=context.parse(window["end"])
    checks.append("precipitation intervals cover both solar windows; cloud remains an end-of-interval instantaneous forecast")
    # Mutate independent copies: bad units/time are rejected rather than filled.
    bad=copy.deepcopy(raw);bad[0]["hourly_units"]["precipitation_probability"]="fraction"
    try:normalize(bad,primary["places"],fetched)
    except ValueError:checks.append("wrong provider probability units rejected")
    else:raise AssertionError("Bad units accepted")
    bad=copy.deepcopy(raw);idx=next(i for i,t in enumerate(bad[0]["hourly"]["time"]) if datetime.fromtimestamp(t,ZoneInfo(ZONE)).hour==6);bad[0]["hourly"]["precipitation_probability"][idx]=None
    try:normalize(bad,primary["places"],fetched)
    except ValueError:checks.append("missing sample probability rejected; no imputation")
    else:raise AssertionError("Missing probability accepted")
    bad=copy.deepcopy(raw);bad[0]["timezone"]="UTC"
    try:normalize(bad,primary["places"],fetched)
    except ValueError:checks.append("wrong provider timezone rejected")
    else:raise AssertionError("Bad timezone accepted")
    manifest.write_text(json.dumps(dict(systemPrompt=context.PROMPT,cases=[dict(key="C11-photo-priority",input=primary),dict(key="C12-reading-food",input=secondary)]),indent=2,ensure_ascii=False)+"\n")
    (HERE/"source-checks.json").write_text(json.dumps(dict(passed=len(checks),checks=checks,solarComparisons=solar_comparisons),indent=2)+"\n")
    print(json.dumps(dict(httpStatus=status,forecastLocations=len(records),samplesPerLocation=len(records[0]["hourlySamples"]),sourceChecks=len(checks),targetDate=DAY)))


def run():
    source=json.loads((HERE/"inputs.json").read_text())
    if source["systemPrompt"]!=context.PROMPT:raise SystemExit("Prompt changed")
    ledger_path=HERE/"call-ledger.json"
    if ledger_path.exists():raise SystemExit("Refusing model rerun/retry")
    previous_ledger=json.loads((context.HERE/"call-ledger.json").read_text())
    assert len(previous_ledger)==10 and len(source["cases"])==2
    context.transport.server.load_env("/Users/giovan/Documents/ChatGPT/C6 - Pisang Besar Balaraja/poc/c67-pocket-engine-lab/Server/.env")
    os.environ["POCKET_LLM_BASE_URL"]="https://ai.giovanc.com/v1"
    module=context.transport.server.advice_module();module.credentials()
    ledger=[dict(case=row["key"],state="reserved-before-dispatch",inputSHA256=hashlib.sha256(json.dumps(row["input"],sort_keys=True).encode()).hexdigest()) for row in source["cases"]]
    ledger_path.write_text(json.dumps(ledger,indent=2)+"\n")
    # Sequential calls avoid simultaneous stress on the already observed provider.
    for row in source["cases"]:
        case=row["input"]
        context.validate_context(case)
        try:record=context.transport.request(case,module)
        except Exception as error:record=dict(caseID=case["caseID"],transportError=type(error).__name__)
        record["experimentCaseID"]=row["key"]
        try:record["validation"]=context.validate(case,record)
        except Exception as error:record["validation"]=dict(structurePassed=False,errors=["Malformed output rejected: "+type(error).__name__],reviewFlags=[])
        (HERE/(row["key"]+".json")).write_text(json.dumps(record,indent=2,ensure_ascii=False)+"\n")
        for entry in ledger:
            if entry["case"]==row["key"]:entry.update(state="completed" if record.get("answer") else "failed",httpStatus=record.get("httpStatus"))
        ledger_path.write_text(json.dumps(ledger,indent=2)+"\n")
        print(json.dumps(dict(case=row["key"],seconds=record.get("elapsedSeconds"),http=record.get("httpStatus"),validation=record["validation"])),flush=True)


if __name__=="__main__":
    parser=argparse.ArgumentParser();parser.add_argument("phase",choices=["prepare","run"])
    args=parser.parse_args();prepare() if args.phase=="prepare" else run()
