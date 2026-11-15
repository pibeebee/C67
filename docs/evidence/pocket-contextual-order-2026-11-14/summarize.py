"""Offline result replay, source binding and human-review preparation."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import statistics
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("context_experiment", HERE / "experiment.py")
e = importlib.util.module_from_spec(spec)
spec.loader.exec_module(e)


def main():
    source = json.loads((HERE / "inputs.json").read_text())
    cases = {row["key"]:row["input"] for row in source["cases"]}
    rows, records, bindings = [], {}, {}
    for key, case in cases.items():
        path = HERE / (key+".json")
        if not path.exists():continue
        record=json.loads(path.read_text())
        e.validate_context(case)
        assert e.validate(case,record)==record["validation"]
        records[key]=record
        answer=record.get("answer")
        row=dict(case=key,completed=answer is not None, httpStatus=record.get("httpStatus"),
                 elapsedSeconds=record.get("elapsedSeconds"),validation=record["validation"],
                 provider=record.get("provider"),reportedTokens=(record.get("usage") or {}).get("total_tokens"))
        if answer:
            names={p["id"]:p["name"] for p in case["places"]}
            row["orderedIDs"]=answer["orderedIDs"]
            row["namesVisibleToModelInOrder"]=[names[x] for x in answer["orderedIDs"]]
            row["stops"]=[{k:stop.get(k) for k in ["placeID","role","duration","durationUnknownReason","preferredDayPart","weather","light"]} for stop in answer["stops"]]
            index={r["id"]:r for r in case["weatherSources"]+case["solarWindows"]}
            bound={}
            for stop in answer["stops"]:
                refs=stop["weather"]["sourceRefs"]+([stop["light"]["windowRef"]] if stop["light"]["windowRef"] else [])
                bound[stop["placeID"]]=[copy.deepcopy(index[ref]) for ref in refs]
                assert all(item==index[item["id"]] for item in bound[stop["placeID"]])
            bindings[key]=bound
        rows.append(row)
    alias=e.previous.cases()[1]
    def stop(key,ident):
        return next(s for s in records[key]["answer"]["stops"] if s["placeID"]==ident)
    pairs={}
    if all(k in records and records[k].get("answer") for k in ["A1-no-context","A2-shorter-visits"]):
        pairs["durationIntent"]={}
        for name in ["library","coffee"]:
            a,b=stop("A1-no-context",alias[name])["duration"],stop("A2-shorter-visits",alias[name])["duration"]
            pairs["durationIntent"][name]=dict(immersiveEstimate=a,shortEstimate=b,
                bothShortBoundsLower=bool(a and b and b["minMinutes"]<a["minMinutes"] and b["maxMinutes"]<a["maxMinutes"]))
    if all(k in records and records[k].get("answer") for k in ["A3-clear-photo","A6-photo-deprioritized"]):
        pairs["photographyPriority"]={k:stop(k,alias["park"])["light"] for k in ["A3-clear-photo","A6-photo-deprioritized"]}
    pairs["cloudChangeKeepsCalculatedSolarWindows"]=cases["A3-clear-photo"]["solarWindows"]==cases["A5-dry-cloudy"]["solarWindows"]
    if all(k in records and records[k].get("answer") for k in ["A3-clear-photo","B10-exact-repeat"]):
        a,b=records["A3-clear-photo"],records["B10-exact-repeat"]
        assert a["request"]==b["request"]
        pairs["repeat"]=dict(identicalRequest=True,identicalOrder=a["answer"]["orderedIDs"]==b["answer"]["orderedIDs"],
            durations={name:dict(first=stop("A3-clear-photo",ident)["duration"],repeat=stop("B10-exact-repeat",ident)["duration"]) for name,ident in alias.items()})
    latencies=[r["elapsedSeconds"] for r in rows if r.get("elapsedSeconds") is not None]
    summary=dict(attempted=len(rows),completed=sum(r["completed"] for r in rows),
        structurePassed=sum(r["validation"]["structurePassed"] for r in rows),
        latencySeconds=dict(minimum=min(latencies),median=statistics.median(latencies),maximum=max(latencies)),
        providerReportedTotalTokens=sum(r.get("reportedTokens") or 0 for r in rows),
        phaseC=json.loads((HERE/"phase-C-status.json").read_text()),pairedComparisons=pairs,cases=rows,
        inputsSHA256=hashlib.sha256((HERE/"inputs.json").read_bytes()).hexdigest())
    (HERE/"summary.json").write_text(json.dumps(summary,indent=2,ensure_ascii=False)+"\n")
    (HERE/"bound-source-values.json").write_text(json.dumps(bindings,indent=2,ensure_ascii=False)+"\n")
    ledger=json.loads((HERE/"call-ledger.json").read_text())
    assert len(ledger)<=12 and len({r["case"] for r in ledger})==len(ledger)
    packet=["# Human review packet", "", "No traveller/mentor scores have been collected. Implementing-agent ratings and experimental labels are omitted. This is preparation, not an executed blinded study.",
        "Assess preference fit, activity flow, duration plausibility, context use and factual restraint. Record unsupported claims and disagreements. Durations are unvalidated estimates; weather fixtures are synthetic. Solar windows are calculated opportunities, not observed light.", ""]
    mapping={}
    keys=["A5-dry-cloudy","B8-ambiguous-setting","A2-shorter-visits","B9-competing-light","A3-clear-photo","A6-photo-deprioritized","B7-weather-unavailable","A1-no-context","B10-exact-repeat","A4-rainy-afternoon"]
    for index,key in enumerate(keys,1):
        if key not in records:continue
        mapping["R"+str(index)]=key
        case=copy.deepcopy(cases[key]);case.pop("caseID",None)
        packet.extend(["## R"+str(index),"","Input:","","```json",json.dumps(case,indent=2,ensure_ascii=False),"```","","Output:","","```json",json.dumps(records[key].get("answer"),indent=2,ensure_ascii=False),"```","","Reviewer notes: __",""])
    (HERE/"review-packet.md").write_text("\n".join(packet))
    (HERE/"review-key.json").write_text(json.dumps(mapping,indent=2)+"\n")
    print(json.dumps({k:v for k,v in summary.items() if k in {"attempted","completed","structurePassed","latencySeconds","providerReportedTotalTokens","inputsSHA256"}}))


if __name__=="__main__":main()
