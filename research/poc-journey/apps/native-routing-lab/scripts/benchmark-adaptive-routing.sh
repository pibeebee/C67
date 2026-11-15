#!/bin/bash
set -euo pipefail
poc_project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
adaptive_output="${1:?Usage: benchmark-adaptive-routing.sh NEW_OUTPUT_DIRECTORY [COMMITTED_SOURCE_ROOT]}"
committed_source_root="${2:-$poc_project_root}"
adaptive_work="$(mktemp -d "${TMPDIR:-/tmp}/c67-adaptive-replay.XXXXXX")"
trap 'rm -rf "$adaptive_work"' EXIT
adaptive_baseline=712f036b222839173d7ea82bb736dd57aaeed6f5
if [[ -e "$adaptive_output" ]]; then echo 'Use a new output directory.' >&2; exit 2; fi
mkdir -p "$adaptive_output" "$adaptive_work/full"
for name in NativeTripModels NativeTripWeatherSupport NativeTripRoutingCore NativeTripEngine NativeTripRoutingBridge NativeTripTimeAwarePlanner; do
  git -C "$committed_source_root" show "$adaptive_baseline:poc-c67/Features/NativePlanner/$name.swift" > "$adaptive_work/full/$name.swift"
done
for version in full adaptive; do
  sources=()
  for name in NativeTripModels NativeTripWeatherSupport NativeTripRoutingCore NativeTripEngine NativeTripRoutingBridge NativeTripTimeAwarePlanner; do
    if [[ "$version" == full ]]; then sources+=("$adaptive_work/full/$name.swift"); else sources+=("$poc_project_root/poc-c67/Features/NativePlanner/$name.swift"); fi
  done
  xcrun --sdk macosx swiftc -O -swift-version 5 -target "$(uname -m)-apple-macosx14.0" \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" -parse-as-library \
    -module-cache-path "$adaptive_work/module-cache" "${sources[@]}" \
    "$poc_project_root/checks/routing/NativeTripPipelineReplay.swift" -o "$adaptive_work/$version-replay"
done
python3 "$poc_project_root/scripts/benchmark-adaptive-routing.py" \
  --root "$poc_project_root" --committed-root "$committed_source_root" \
  --full "$adaptive_work/full-replay" --adaptive "$adaptive_work/adaptive-replay" \
  --output "$adaptive_output" --baseline "$adaptive_baseline"
