#!/bin/bash
set -euo pipefail

poc_project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
map_check_dir="$(mktemp -d "${TMPDIR:-/tmp}/c67-map-checks.XXXXXX")"
trap 'rm -rf "$map_check_dir"' EXIT

xcrun --sdk macosx swiftc -swift-version 5 \
  -target "$(uname -m)-apple-macosx15.0" \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -parse-as-library -module-cache-path "$map_check_dir/module-cache" \
  "$poc_project_root/poc-c67/Features/NativePlanner/NativeTripModels.swift" \
  "$poc_project_root/poc-c67/Features/NativePlanner/NativeTripWeatherSupport.swift" \
  "$poc_project_root/poc-c67/Features/NativePlanner/NativeTripLogStore.swift" \
  "$poc_project_root/poc-c67/Features/NativePlanner/NativeTripMapRoutes.swift" \
  "$poc_project_root/checks/map/NativeTripMapChecks.swift" \
  -o "$map_check_dir/map-checks"
"$map_check_dir/map-checks"
