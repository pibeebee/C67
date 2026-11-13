#!/bin/bash
set -euo pipefail
LAB_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export CLANG_MODULE_CACHE_PATH="$LAB_ROOT/.build/clang"
export SWIFT_MODULECACHE_PATH="$LAB_ROOT/.build/swift"
swift test --disable-sandbox --package-path "$LAB_ROOT/Packages/TripIntelligence" --scratch-path "$LAB_ROOT/.build" "$@"
