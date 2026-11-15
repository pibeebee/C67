#!/bin/bash
set -euo pipefail
QUALITY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export CLANG_MODULE_CACHE_PATH="$QUALITY_ROOT/.build/quality-clang"
export SWIFT_MODULECACHE_PATH="$QUALITY_ROOT/.build/quality-swift"
QUALITY_SCRATCH="${QUALITY_BUILD_PATH:-$QUALITY_ROOT/.build/quality}"
exec swift test --disable-sandbox --package-path "$QUALITY_ROOT/Packages/PreferenceQuality" --scratch-path "$QUALITY_SCRATCH" "$@"
