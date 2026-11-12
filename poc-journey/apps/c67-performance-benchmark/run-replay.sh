#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
output="${1:?Supply a fresh evidence directory}"
work="${2:?Supply a persistent scratch package directory}"
mkdir -p "$output" "$work/Sources/Benchmark"
output="$(cd "$output" && pwd)"
work="$(cd "$work" && pwd)"
cp "$root/Benchmark.swift" "$root/BenchmarkApp.swift" "$work/Sources/Benchmark/"
cp "$root/../c67-trip-integration/App/IntegrationModel.swift" "$work/Sources/Benchmark/OriginalIntegrationModel.swift"
python3 - "$root" "$work" <<'PY'
from pathlib import Path
import json,sys
root,work=map(Path,sys.argv[1:])
integration=json.dumps(str(root.parent/'c67-trip-integration/Packages/TripIntegration'))
quality=json.dumps(str(root.parent/'c67-foundation-lab/Packages/PreferenceQuality'))
(work/'Package.swift').write_text('''// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "Benchmark", platforms: [.macOS(.v26)], dependencies: [
  .package(path: INTEGRATION), .package(path: QUALITY)
], targets: [ .executableTarget(name: "Benchmark", dependencies: [
  .product(name: "TripIntegration", package: "TripIntegration"),
  .product(name: "PreferenceQuality", package: "PreferenceQuality")
], swiftSettings: [.define("BENCHMARK_REPLAY")]) ], swiftLanguageModes: [.v6])
'''.replace('INTEGRATION',integration).replace('QUALITY',quality))
PY
swift run --package-path "$work" Benchmark "$output"
