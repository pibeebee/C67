#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d /tmp/dds-checks.XXXXXX)"
trap 'rm -rf "$check_dir"' EXIT
xcrun swiftc -parse-as-library -default-isolation MainActor -target arm64-apple-macos26.0 \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  "$project_root/poc-c67/Core/SimulationModels.swift" \
  "$project_root/poc-c67/Core/RoutingService.swift" \
  "$project_root/poc-c67/Core/RouteLab.swift" \
  "$project_root/checks/routing/RouteLabChecks.swift" \
  -o "$check_dir/route-lab-checks"
"$check_dir/route-lab-checks"
