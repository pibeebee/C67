#!/bin/bash
set -euo pipefail
poc_project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
benchmark_output="${1:?Usage: benchmark-routing-pipeline.sh OUTPUT_DIRECTORY}"
benchmark_work="$(mktemp -d "${TMPDIR:-/tmp}/c67-pipeline-replay.XXXXXX")"
trap 'rm -rf "$benchmark_work"' EXIT
benchmark_baseline=f55d1ecfdce973f8f1b387cba128441c92f3afe7
mkdir -p "$benchmark_output" "$benchmark_work/old"
benchmark_files=(NativeTripModels.swift NativeTripWeatherSupport.swift NativeTripRoutingCore.swift NativeTripEngine.swift NativeTripRoutingBridge.swift)
for name in "${benchmark_files[@]}"; do
  git -C "$poc_project_root" show "$benchmark_baseline:poc-c67/Features/NativePlanner/$name" > "$benchmark_work/old/$name"
done
for version in old new; do
  sources=()
  for name in "${benchmark_files[@]}"; do
    if [[ "$version" == old ]]; then sources+=("$benchmark_work/old/$name"); else sources+=("$poc_project_root/poc-c67/Features/NativePlanner/$name"); fi
  done
  if [[ "$version" == new ]]; then sources+=("$poc_project_root/poc-c67/Features/NativePlanner/NativeTripTimeAwarePlanner.swift"); fi
  xcrun --sdk macosx swiftc -O -swift-version 5 -target "$(uname -m)-apple-macosx14.0" \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" -parse-as-library \
    -module-cache-path "$benchmark_work/module-cache" "${sources[@]}" \
    "$poc_project_root/checks/routing/NativeTripPipelineReplay.swift" -o "$benchmark_work/$version-replay"
done
python3 "$poc_project_root/scripts/benchmark-routing-pipeline.py" \
  --root "$poc_project_root" --old "$benchmark_work/old-replay" --new "$benchmark_work/new-replay" \
  --output "$benchmark_output" --baseline "$benchmark_baseline"
