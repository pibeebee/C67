#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d /tmp/dds-channel.XXXXXX)"
trap 'rm -rf "$check_dir"' EXIT
xcrun swiftc -parse-as-library -default-isolation MainActor -target arm64-apple-macos27.0 \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  "$project_root/poc-c67/Core/LiveLocationModels.swift" \
  "$project_root/poc-c67/Core/LocalLocationChannel.swift" \
  "$project_root/checks/routing/LiveChannelChecks.swift" \
  -o "$check_dir/channel-checks"
"$check_dir/channel-checks"
