#!/bin/bash
set -euo pipefail
poc_project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
local_work="$(mktemp -d "${TMPDIR:-/tmp}/c67-weather-tests.XXXXXX")"
trap 'rm -rf "$local_work"' EXIT
local_output="${1:?Supply a new output directory}"
mkdir -p "$local_output"
local_output="$(cd "$local_output" && pwd)"
if [[ -e "$local_output/test.log" ]]; then echo 'Use a fresh result directory.' >&2; exit 2; fi
mkdir -p "$local_work/Sources/C67LocalHarness" "$local_work/Tests/LocalTests/Fixtures"
cat > "$local_work/Package.swift" <<'SWIFT'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "C67LocalTests", platforms: [.macOS(.v14)], targets: [
 .executableTarget(name: "StorageProbe", dependencies: ["C67LocalHarness"]),
 .target(name: "C67LocalHarness", swiftSettings: [.define("PIPELINE_CHECKS")]),
 .testTarget(name: "LocalTests", dependencies: ["C67LocalHarness"], resources: [.copy("Fixtures")])
], swiftLanguageModes: [.v5])
SWIFT
for name in NativeTripModels NativeTripWeatherSupport NativeTripRoutingCore NativeTripEngine NativeTripRoutingBridge NativeTripTimeAwarePlanner NativeTripLocalStore NativeTripActiveTrip NativeTripActivePlanner NativeTripActiveController NativeTripInputSupport NativeTripSearchSupport NativeTripModel NativeTripLogStore; do
 cp "$poc_project_root/poc-c67/Features/NativePlanner/$name.swift" "$local_work/Sources/C67LocalHarness/"
done
cp "$poc_project_root/checks/routing/NativeTripPipelineReplay.swift" "$local_work/Sources/C67LocalHarness/"
cat > "$local_work/Sources/C67LocalHarness/ModelAdapter.swift" <<'SWIFT'
import Foundation
import WeatherKit
// Test-only UI-model dependencies. No transport exists in this target.
extension NativeTripAppleServices {
 convenience init(logs: NativeTripLogStore, operationID: String, requestLimit: Int = 96, simulated: Bool = false) {
   self.init(["oracle": [] as [[String:Any]]], draft: .empty())
 }
 var attribution: WeatherAttribution? { nil }
 var searchAttempts: [NativeTripSearchAttempt] { [] }
 func cancel() {}
 func searchPlaces(_ query: String, region: NativeTripSearchRegion?) async throws -> [NativeTripMatch] { [] }
}
SWIFT
mkdir -p "$local_work/Sources/StorageProbe"
cat > "$local_work/Sources/StorageProbe/main.swift" <<'SWIFT'
import Foundation
@testable import C67LocalHarness
@main struct StorageProbe {
 @MainActor static func main() throws {
   let store = NativeTripLocalStore(directory: URL(fileURLWithPath: CommandLine.arguments[2]))
   if CommandLine.arguments[1] == "write" {
     var draft = NativeTripDraft.empty(); draft.searchContext = "cross-process-test"
     _ = try store.commit(.init(draft: draft), expected: nil)
   } else {
     let loaded = try store.load().session
     guard loaded?.draft.searchContext == "cross-process-test", loaded?.revision == 1 else { fatalError("Restore mismatch") }
   }
   print("PASS cross-process \(CommandLine.arguments[1])")
 }
}
SWIFT
for name in WeatherLabCore WeatherLabModel WeatherLabService; do
 cp "$poc_project_root/poc-c67/Features/WeatherLab/$name.swift" "$local_work/Sources/C67LocalHarness/"
done
cp "$poc_project_root/checks/weather/WeatherLabTests.swift" "$local_work/Tests/LocalTests/"
cp "$poc_project_root/checks/local/LocalTripTests.swift" "$local_work/Tests/LocalTests/"
cp "$poc_project_root/checks/local/JakartaProfileTests.swift" "$local_work/Tests/LocalTests/"
cp "$poc_project_root/checks/active/NativeTripActiveTests.swift" "$local_work/Tests/LocalTests/"
cp "$poc_project_root/checks/jakarta/Fixtures/jakarta-recorded-static.json" "$local_work/Tests/LocalTests/Fixtures/"
python3 - "$poc_project_root" "$local_output" <<'PY'
import hashlib,json,sys
from pathlib import Path
root,out=map(Path,sys.argv[1:]);paths=list((root/'poc-c67/Features/NativePlanner').glob('*.swift'))+list((root/'poc-c67/Features/WeatherLab').glob('*.swift'))+[root/'checks/local/LocalTripTests.swift',root/'checks/local/JakartaProfileTests.swift',root/'checks/active/NativeTripActiveTests.swift',root/'checks/routing/NativeTripPipelineReplay.swift',root/'scripts/test-native-trip-local.sh',root/'scripts/test-weather-lab.sh',root/'checks/weather/WeatherLabTests.swift']
(out/'manifest.json').write_text(json.dumps({'network':False,'weather':'Production Weather Lab core/model/provider compiled; provider calls injected with XCTest fixtures','adapter':'Frozen ETA replay plus test-only model dependency adapter; production source compiled unchanged','sources':{str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}},indent=2))
PY
xcrun swift test --package-path "$local_work" --scratch-path "$local_work/build" --cache-path "$local_work/cache" --config-path "$local_work/config" --security-path "$local_work/security" --enable-xctest --disable-swift-testing --no-parallel --xunit-output "$local_output/junit.xml" > "$local_output/test.log" 2>&1 || { tail -n 80 "$local_output/test.log"; exit 1; }
python3 - "$local_output" <<'PYREPORT'
import json,re,sys,xml.etree.ElementTree as ET
from pathlib import Path
out=Path(sys.argv[1]);log=(out/'test.log').read_text()
cases=re.findall(r"Test Case '-\[([^ ]+) ([^]]+)\]' (passed|failed|skipped) \(([0-9.]+) seconds\)\.",log)
summary=re.findall(r'Executed (\d+) tests, with (\d+) failures',log)
assert cases and summary and len(cases)==int(summary[-1][0]), 'XCTest event count does not match summary'
failures=sum(c[2]=='failed' for c in cases);assert failures==int(summary[-1][1]),'Failure summary mismatch'
if not (out/'junit.xml').exists():
 root=ET.Element('testsuites');suite=ET.SubElement(root,'testsuite',name='LocalTripTests',tests=str(len(cases)),failures=str(failures))
 for cls,name,status,seconds in cases:
  case=ET.SubElement(suite,'testcase',classname=cls,name=name,time=seconds)
  if status!='passed':ET.SubElement(case,'failure' if status=='failed' else 'skipped')
 ET.ElementTree(root).write(out/'junit.xml',encoding='utf-8',xml_declaration=True)
(out/'summary.json').write_text(json.dumps({'tests':len(cases),'failures':failures,'skipped':sum(c[2]=='skipped' for c in cases),'source':'Actual XCTest console events, cross-checked with suite summary; JUnit reconstructed when SwiftPM omits it','cases':[dict(name=c[1],status=c[2]) for c in cases]},indent=2))
PYREPORT
tail -n 8 "$local_output/test.log"

"$local_work/build/debug/StorageProbe" write "$local_output/cross-process" > "$local_output/cross-process.log"
"$local_work/build/debug/StorageProbe" read "$local_output/cross-process" >> "$local_output/cross-process.log"
cat "$local_output/cross-process.log"
