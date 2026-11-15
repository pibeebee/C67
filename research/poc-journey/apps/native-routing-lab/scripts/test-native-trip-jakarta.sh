#!/bin/bash
set -euo pipefail
poc_project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
jakarta_work="$(mktemp -d "${TMPDIR:-/tmp}/c67-jakarta-xctest.XXXXXX")"
trap 'rm -rf "$jakarta_work"' EXIT
jakarta_output="${1:-$(mktemp -d "${TMPDIR:-/tmp}/c67-jakarta-results.XXXXXX")}"
mkdir -p "$jakarta_output"
jakarta_output="$(cd "$jakarta_output" && pwd)"
if [[ -e "$jakarta_output/junit.xml" || -e "$jakarta_output/test.log" ]]; then
  echo "Use a fresh output directory to preserve previous test evidence." >&2
  exit 2
fi
mkdir -p "$jakarta_work/Sources/C67RoutingHarness" "$jakarta_work/Tests/JakartaRoutingTests"
cp "$poc_project_root/checks/jakarta/Package.swift.template" "$jakarta_work/Package.swift"
for name in NativeTripModels NativeTripWeatherSupport NativeTripRoutingCore NativeTripEngine NativeTripRoutingBridge NativeTripTimeAwarePlanner; do
  cp "$poc_project_root/poc-c67/Features/NativePlanner/$name.swift" "$jakarta_work/Sources/C67RoutingHarness/"
done
cp "$poc_project_root/checks/routing/NativeTripPipelineReplay.swift" "$jakarta_work/Sources/C67RoutingHarness/"
cp "$poc_project_root/checks/jakarta/NativeTripJakartaTests.swift" "$poc_project_root/checks/jakarta/JakartaFixture.swift" "$jakarta_work/Tests/JakartaRoutingTests/"
cp -R "$poc_project_root/checks/jakarta/Fixtures" "$jakarta_work/Tests/JakartaRoutingTests/"
python3 - "$poc_project_root" "$jakarta_output" <<'PY'
import hashlib,json,platform,subprocess,sys
from pathlib import Path
root,out=map(Path,sys.argv[1:])
paths=list((root/'checks/jakarta').rglob('*'))+[root/'checks/routing/NativeTripPipelineReplay.swift']
paths += [root/'poc-c67/Features/NativePlanner'/f'{name}.swift' for name in ['NativeTripModels','NativeTripWeatherSupport','NativeTripRoutingCore','NativeTripEngine','NativeTripRoutingBridge','NativeTripTimeAwarePlanner']]
paths += [root/'scripts/test-native-trip-jakarta.sh',root/'scripts/report-native-trip-jakarta.py']
fixture=json.loads((root/'checks/jakarta/Fixtures/jakarta-recorded-static.json').read_text())
recorded=root/fixture['source']
assert hashlib.sha256(recorded.read_bytes()).hexdigest()==fixture['sourceSHA256'], 'Recorded ETA provenance changed'
manifest={'gitCommit':subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD'],text=True).strip(),
 'platform':platform.platform(),'swift':subprocess.check_output(['xcrun','swiftc','--version'],text=True).strip(),
 'framework':'XCTest, SwiftPM host macOS','network':False,'weatherData':False,
 'adapter':'Existing frozen replay adapter; actual production planner/core/model/engine compiled unchanged.',
 'configuration':'Debug, Swift 5 language mode, macOS 14 target, serial XCTest; pipeline request cap 96 unless overridden.',
 'sources':{str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths if p.is_file()}}
(out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
PY
jakarta_status=0
C67_JAKARTA_METRICS="$jakarta_output/itineraries.jsonl" \
CLANG_MODULE_CACHE_PATH="$jakarta_work/module-cache" \
xcrun swift test --package-path "$jakarta_work" \
  --cache-path "$jakarta_work/cache" --config-path "$jakarta_work/config" \
  --security-path "$jakarta_work/security" --scratch-path "$jakarta_work/build" \
  --enable-xctest --disable-swift-testing --no-parallel \
  --xunit-output "$jakarta_output/junit.xml" > "$jakarta_output/test.log" 2>&1 || jakarta_status=$?
jakarta_report_status=0
python3 "$poc_project_root/scripts/report-native-trip-jakarta.py" "$jakarta_output" --test-status "$jakarta_status" || jakarta_report_status=$?
if [[ "$jakarta_status" -ne 0 ]]; then tail -n 45 "$jakarta_output/test.log"; fi
if [[ "$jakarta_status" -ne 0 ]]; then exit "$jakarta_status"; fi
exit "$jakarta_report_status"
