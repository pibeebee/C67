#!/bin/bash
set -euo pipefail
poc_project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pipeline_check_dir="$(mktemp -d "${TMPDIR:-/tmp}/c67-pipeline-checks.XXXXXX")"
trap 'rm -rf "$pipeline_check_dir"' EXIT
sources=()
for name in NativeTripModels NativeTripWeatherSupport NativeTripRoutingCore NativeTripEngine NativeTripRoutingBridge NativeTripTimeAwarePlanner; do
  sources+=("$poc_project_root/poc-c67/Features/NativePlanner/$name.swift")
done
xcrun --sdk macosx swiftc -swift-version 5 -D PIPELINE_CHECKS \
  -target "$(uname -m)-apple-macosx14.0" -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -parse-as-library -module-cache-path "$pipeline_check_dir/module-cache" "${sources[@]}" \
  "$poc_project_root/checks/routing/NativeTripPipelineReplay.swift" \
  "$poc_project_root/checks/routing/NativeTripPipelineChecks.swift" -o "$pipeline_check_dir/checks"
"$pipeline_check_dir/checks"
