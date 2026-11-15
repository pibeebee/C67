#!/bin/bash
set -euo pipefail
poc_project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
routing_check_dir="$(mktemp -d "${TMPDIR:-/tmp}/c67-routing-checks.XXXXXX")"
trap 'rm -rf "$routing_check_dir"' EXIT
xcrun --sdk macosx swiftc -swift-version 5 \
  -target "$(uname -m)-apple-macosx14.0" \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -parse-as-library -module-cache-path "$routing_check_dir/module-cache" \
  "$poc_project_root/poc-c67/Features/NativePlanner/NativeTripRoutingCore.swift" \
  "$poc_project_root/poc-c67/Features/NativePlanner/NativeTripRoutingFixtures.swift" \
  "$poc_project_root/checks/routing/NativeTripRoutingChecks.swift" \
  -o "$routing_check_dir/routing-checks"
"$routing_check_dir/routing-checks"
if [[ -n "${C67_ORTOOLS_PYTHON:-}" ]]; then
  "$routing_check_dir/routing-checks" --emit-case "$routing_check_dir/case.json"
  "$C67_ORTOOLS_PYTHON" "$poc_project_root/scripts/solve-routing-ortools.py" "$routing_check_dir/case.json" --output "$routing_check_dir/result.json" --seconds 1
  "$routing_check_dir/routing-checks" --verify-result "$routing_check_dir/case.json" "$routing_check_dir/result.json"
  "$C67_ORTOOLS_PYTHON" "$poc_project_root/checks/routing/check_ortools_elapsed.py" "$poc_project_root/scripts/solve-routing-ortools.py"
fi
