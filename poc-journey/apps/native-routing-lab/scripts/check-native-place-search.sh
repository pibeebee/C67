#!/bin/bash
set -euo pipefail

poc_project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
search_check_dir="$(mktemp -d "${TMPDIR:-/tmp}/c67-search-checks.XXXXXX")"
trap 'rm -rf "$search_check_dir"' EXIT

xcrun --sdk macosx swiftc -swift-version 5 \
  -target "$(uname -m)-apple-macosx14.0" \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -parse-as-library -module-cache-path "$search_check_dir/module-cache" \
  "$poc_project_root/poc-c67/Features/NativePlanner/NativeTripSearchSupport.swift" \
  "$poc_project_root/checks/search/NativeTripSearchChecks.swift" \
  -o "$search_check_dir/search-checks"
"$search_check_dir/search-checks"
