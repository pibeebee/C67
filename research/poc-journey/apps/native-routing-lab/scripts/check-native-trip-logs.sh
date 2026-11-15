#!/bin/bash
set -euo pipefail

poc_project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
log_check_dir="$(mktemp -d "${TMPDIR:-/tmp}/c67-log-checks.XXXXXX")"
trap 'rm -rf "$log_check_dir"' EXIT

xcrun --sdk macosx swiftc -swift-version 5 \
  -target "$(uname -m)-apple-macosx14.0" \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -parse-as-library -module-cache-path "$log_check_dir/module-cache" \
  "$poc_project_root/poc-c67/Features/NativePlanner/NativeTripLogStore.swift" \
  "$poc_project_root/checks/logs/NativeTripLogChecks.swift" \
  -o "$log_check_dir/log-checks"
"$log_check_dir/log-checks"
"$log_check_dir/log-checks" --seed "$log_check_dir/relaunch"
"$log_check_dir/log-checks" --read "$log_check_dir/relaunch"
printf '9 persistent-log checks passed on macOS; no iOS runtime or network.\n'
