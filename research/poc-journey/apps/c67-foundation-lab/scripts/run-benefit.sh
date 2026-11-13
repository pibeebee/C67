#!/bin/bash
set -euo pipefail
BENEFIT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export CLANG_MODULE_CACHE_PATH="$BENEFIT_ROOT/.build/quality-clang"
export SWIFT_MODULECACHE_PATH="$BENEFIT_ROOT/.build/quality-swift"
BENEFIT_SCRATCH="${QUALITY_BUILD_PATH:-$BENEFIT_ROOT/.build/quality}"
swift build --disable-sandbox --package-path "$BENEFIT_ROOT/Packages/PreferenceQuality" --scratch-path "$BENEFIT_SCRATCH" >&2
BENEFIT_BIN="$(swift build --disable-sandbox --package-path "$BENEFIT_ROOT/Packages/PreferenceQuality" --scratch-path "$BENEFIT_SCRATCH" --show-bin-path)"
exec "$BENEFIT_BIN/embedding-benefit-eval" "$@"
