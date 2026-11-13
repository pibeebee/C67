#!/bin/bash
set -euo pipefail

poc_project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
input_check_dir="$(mktemp -d "${TMPDIR:-/tmp}/c67-input-checks.XXXXXX")"
trap 'rm -rf "$input_check_dir"' EXIT

xcrun --sdk macosx swiftc -swift-version 5 \
  -target "$(uname -m)-apple-macosx14.0" \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -parse-as-library -module-cache-path "$input_check_dir/module-cache" \
  "$poc_project_root/poc-c67/Features/NativePlanner/NativeTripModels.swift" \
  "$poc_project_root/poc-c67/Features/NativePlanner/NativeTripWeatherSupport.swift" \
  "$poc_project_root/poc-c67/Features/NativePlanner/NativeTripInputSupport.swift" \
  "$poc_project_root/checks/input/NativeTripInputChecks.swift" \
  -o "$input_check_dir/input-checks"
"$input_check_dir/input-checks"
