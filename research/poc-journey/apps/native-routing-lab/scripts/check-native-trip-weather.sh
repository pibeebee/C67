#!/bin/bash
set -euo pipefail
poc_project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
weather_check_dir="$(mktemp -d "${TMPDIR:-/tmp}/c67-weather-checks.XXXXXX")"
trap 'rm -rf "$weather_check_dir"' EXIT
xcrun --sdk macosx swiftc -swift-version 5 \
  -target "$(uname -m)-apple-macosx14.0" \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -parse-as-library -module-cache-path "$weather_check_dir/module-cache" \
  "$poc_project_root/poc-c67/Features/NativePlanner/NativeTripWeatherSupport.swift" \
  "$poc_project_root/checks/weather/NativeTripWeatherChecks.swift" \
  -o "$weather_check_dir/weather-checks"
"$weather_check_dir/weather-checks"
