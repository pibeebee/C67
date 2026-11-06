#!/bin/bash
set -euo pipefail
TIMING_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export CLANG_MODULE_CACHE_PATH="$TIMING_ROOT/.build/timing-clang"
export SWIFT_MODULECACHE_PATH="$TIMING_ROOT/.build/timing-swift"
swift build --disable-sandbox --package-path "$TIMING_ROOT/Packages/VisitTiming" --scratch-path "$TIMING_ROOT/.build/timing" >&2
TIMING_BIN="$(swift build --disable-sandbox --package-path "$TIMING_ROOT/Packages/VisitTiming" --scratch-path "$TIMING_ROOT/.build/timing" --show-bin-path)"
exec "$TIMING_BIN/visit-time-eval" "$@"
