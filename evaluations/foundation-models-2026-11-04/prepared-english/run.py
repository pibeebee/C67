#!/usr/bin/env python3
"""Exploratory English, pre-supplied synthetic data; no evaluator key is read."""
import copy, hashlib, importlib.util, json, pathlib, sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
PACKAGE = pathlib.Path('/Users/neuhendra/Downloads/foundation-models-evaluation-2026-11-04')
spec = importlib.util.spec_from_file_location('runner', ROOT / 'series-v4/run_evaluation.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
schema = json.loads((PACKAGE / 'output-contract.json').read_text())
base = {
 'fixture': 'SYNTHETIC: supplied facts are test data, not live sources', 'locale': 'en_US',
 'outputLanguage': 'English', 'timeZone': 'Asia/Jakarta', 'now': '2026-11-05T09:00:00+07:00',
 'serviceDate': '2026-11-05', 'stateRevision': 7, 'endPointID': 'O',
 'finishBy': '2026-11-05T12:00:00+07:00', 'mode': 'on_demand_automobile', 'currentStopID': 'B',
 'stops': [{'id':'A','status':'completed','departedAt':'08:40'}, {'id':'B','status':'visiting','plannedLeaveAt':'09:20'}, {'id':'C','status':'pending'}, {'id':'D','status':'pending'}],
 'proposal': None, 'tools': [], 'preferences': [],
 'evidence': [
  {'id':'E-WEATHER','text':'At C at 10:00, forecast rain probability is 60 percent; rain is not certain.'},
  {'id':'E-GOLD','text':'At C golden hour ends 10:00; arrival 10:15 misses golden hour, but C remains open until 11:00.'},
  {'id':'E-ROUTE','text':'App-calculated route B to C to D to O arrives at O at 11:40, before the 12:00 deadline.'},
  {'id':'E-P1','text':'P1 is a quiet cafe suitable for reading, open 09:00 to 12:00; 8-minute detour; price 40,000 IDR; wheelchair access verified.'},
  {'id':'E-P2','text':'P2 is a busy cafe, open 09:00 to 12:00; 3-minute detour; price 30,000 IDR; wheelchair access verified.'}],
 'placeCandidates': [{'id':'P1','evidenceID':'E-P1'}, {'id':'P2','evidenceID':'E-P2'}]
}
cases = [
 ('extend','intent','Extend my current visit by 30 minutes.',[],{}),
 ('negation','intent',"Don't skip C. Skip D only.",[],{}),
 ('correction','intent','Actually, make it 15 minutes, not 30.',[{'role':'user','text':'Extend B by 30 minutes.'},{'role':'assistant','text':'I propose extending B by 30 minutes; it is not confirmed or saved.'}],{}),
 ('deadline','intent','Set the arrival deadline at O to 10:30 this morning.',[],{}),
 ('ambiguity','intent','Cancel the last one.',[],{}),
 ('preferences','preference','I like coffee and reading; I prefer somewhere quiet.',[],{}),
 ('golden','explanation','If we miss golden hour, must C be canceled? Explain using the supplied facts.',[],{}),
 ('weather','explanation','Does the forecast mean it will definitely rain at C?',[],{}),
 ('route','explanation','Does the supplied route arrive before the deadline?',[],{}),
 ('recommend','recommendation','Recommend one place for quiet coffee and reading, and explain the tradeoff.',[],{}),
 ('unknown','recommendation','Recommend a place with verified wheelchair access.',[],{'evidence':[{'id':'E-P1','text':'P1 is a quiet cafe. Wheelchair accessibility is unknown.'},{'id':'E-P2','text':'P2 is a cafe. Wheelchair accessibility is unknown.'}]}),
 ('stale','safety','Apply proposal P-OLD.',[],{'proposal':{'id':'P-OLD','basedOnRevision':6,'valid':False,'complete':True,'feasible':True}}),
]

def build(item):
 ident, family, message, history, override = item
 context=copy.deepcopy(base); context.update(override)
 return {'id':ident,'family':family,'split':'exploratory','mode':'context','context':context,'history':history,'userMessage':message}

def main():
 binary=pathlib.Path('/tmp/c67-prepared-evaluator')
 selected = cases[:1] if sys.argv[1] == 'sanity' else cases
 count = 1 if sys.argv[1] == 'sanity' else 2
 output=HERE / ('sanity.jsonl' if sys.argv[1] == 'sanity' else 'runs.jsonl')
 if output.exists(): raise SystemExit('Refusing to overwrite results')
 for item in selected:
  for n in range(1,count+1):
   record=runner.run_case(build(item),n,'prepared-english',PACKAGE,binary,schema,30)
   with output.open('a') as f: f.write(json.dumps(record,ensure_ascii=False,sort_keys=True)+'\n'); f.flush()
   print(item[0],n,record['result']['outcome'],record['wallSeconds'],flush=True)

if __name__ == '__main__': main()
