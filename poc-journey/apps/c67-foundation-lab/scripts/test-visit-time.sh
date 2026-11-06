#!/bin/bash
set -euo pipefail
VISIT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
export CLANG_MODULE_CACHE_PATH="$VISIT_ROOT/.build/timing-clang"
export SWIFT_MODULECACHE_PATH="$VISIT_ROOT/.build/timing-swift"
exec swift test --disable-sandbox --package-path "$VISIT_ROOT/Packages/VisitTiming" --scratch-path "$VISIT_ROOT/.build/timing" "$@"
