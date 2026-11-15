#!/bin/bash
set -euo pipefail
if [[ "$#" -ne 1 ]]; then echo 'Supply a fresh result directory.' >&2; exit 2; fi
poc_root="$(cd "$(dirname "$0")/.." && pwd)"
live_output="$1"
mkdir -p "$live_output"
live_output="$(cd "$live_output" && pwd)"
if [[ -e "$live_output/input.json" || -e "$live_output/manifest.json" ]]; then
  echo 'Use a fresh result directory; previous evidence is preserved.' >&2; exit 2
fi
live_work="$(mktemp -d /tmp/c67-jakarta-live.XXXXXX)"
trap 'rm -rf "$live_work"' EXIT
python3 - "$poc_root" "$live_output" "$live_work" <<'PY'
import sys,json,hashlib,subprocess,platform
from pathlib import Path
root,out,work=map(Path,sys.argv[1:])
names=['NativeTripModels','NativeTripInputSupport','NativeTripSearchSupport','NativeTripWeatherSupport',
 'NativeTripLogStore','NativeTripAppleServices','NativeTripRoutingCore','NativeTripEngine',
 'NativeTripRoutingBridge','NativeTripTimeAwarePlanner','NativeTripLocalStore','NativeTripActiveTrip','NativeTripActivePlanner']
paths=[root/'poc-c67/Features/NativePlanner'/(n+'.swift') for n in names]+[root/'checks/jakarta/NativeTripJakartaLiveProbe.swift']
manifest={'network':True,'providers':['Apple MapKit automobile ETA/search','Open-Meteo forecast'],
 'environment':platform.platform(),'swift':subprocess.check_output(['xcrun','swiftc','--version'],text=True).strip(),
 'scriptedReportedFacts':True,'physicalDevice':False,
 'sources':{str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths+[root/'scripts/test-native-trip-jakarta-live.sh']}}
(out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
command=['xcrun','--sdk','macosx','swiftc','-swift-version','5','-parse-as-library',
 '-module-cache-path',str(work/'module-cache'),*map(str,paths),'-o',str(work/'live-probe')]
with (out/'compile.log').open('w') as log:result=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT)
if result.returncode:
 print((out/'compile.log').read_text()[-6000:]);raise SystemExit(result.returncode)
with (out/'run.log').open('w') as log:result=subprocess.run([str(work/'live-probe'),str(out)],stdout=log,stderr=subprocess.STDOUT)
if result.returncode:
 print((out/'run.log').read_text()[-6000:]);raise SystemExit(result.returncode)
print((out/'summary.json').read_text())
PY
