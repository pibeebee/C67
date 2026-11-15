"""Offline replay and provenance/source binding. No provider calls."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent
s=importlib.util.spec_from_file_location("open_meteo_experiment",HERE/"experiment.py")
e=importlib.util.module_from_spec(s);s.loader.exec_module(e)


def main():
    source=json.loads((HERE/"inputs.json").read_text())
    fetch=json.loads((HERE/"forecast-fetch.json").read_text())
    raw=json.loads((HERE/"forecast-raw.json").read_text())
    rows=[];bindings={};checks=[]
    for row in source["cases"]:
        key,case=row["key"],row["input"]
        record=json.loads((HERE/(key+".json")).read_text())
        e.context.validate_context(case)
        assert e.normalize(raw,case["places"],fetch["fetchedAt"])==case["weatherSources"]
        assert record["request"]["input"][0]["content"]==source["systemPrompt"]==e.context.PROMPT
        assert json.loads(record["request"]["input"][1]["content"])==case
        assert e.context.validate(case,record)==record["validation"]
        checks.append(key+": payload, normalization and output replay match")
        result={k:record.get(k) for k in ["experimentCaseID","httpStatus","curlExit","elapsedSeconds","transportError","provider","validation"]}
        result["reportedTokens"]=(record.get("usage") or {}).get("total_tokens")
        if record.get("answer"):
            answer=record["answer"];names={p["id"]:p["name"] for p in case["places"]}
            result["orderedNames"]=[names[x] for x in answer["orderedIDs"]]
            index={r["id"]:r for r in case["weatherSources"]+case["solarWindows"]}
            bound={}
            for stop in answer["stops"]:
                refs=stop["weather"]["sourceRefs"]+([stop["light"]["windowRef"]] if stop["light"]["windowRef"] else [])
                bound[stop["placeID"]]=[copy.deepcopy(index[ref]) for ref in refs]
                assert all(x==index[x["id"]] for x in bound[stop["placeID"]])
            bindings[key]=bound
        rows.append(result)
    cases=[r["input"] for r in source["cases"]]
    assert cases[0]["weatherSources"]==cases[1]["weatherSources"]
    assert cases[0]["solarWindows"]==cases[1]["solarWindows"]
    ledger=json.loads((HERE/"call-ledger.json").read_text())
    assert len(ledger)==2 and len({r["case"] for r in ledger})==2
    summary=dict(openMeteoHTTPRequests=1,forecastHTTPStatus=fetch["httpStatus"],forecastLocations=5,
        modelRequests=2,modelCompleted=sum(r["provider"] is not None for r in rows),
        structurePassed=sum(r["validation"]["structurePassed"] for r in rows),
        reportedTokensForCompleted=sum(r["reportedTokens"] or 0 for r in rows),
        failedCallTokenUsage="unknown",checks=checks,cases=rows,
        rawForecastSHA256=hashlib.sha256((HERE/"forecast-raw.json").read_bytes()).hexdigest())
    (HERE/"summary.json").write_text(json.dumps(summary,indent=2,ensure_ascii=False)+"\n")
    (HERE/"bound-source-values.json").write_text(json.dumps(bindings,indent=2,ensure_ascii=False)+"\n")
    print(json.dumps({k:v for k,v in summary.items() if k not in {"cases","checks"}}))


if __name__=="__main__":main()
