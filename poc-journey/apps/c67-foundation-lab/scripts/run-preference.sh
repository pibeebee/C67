#!/bin/bash
set -euo pipefail
PREFERENCE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export CLANG_MODULE_CACHE_PATH="$PREFERENCE_ROOT/.build/preference-clang"
export SWIFT_MODULECACHE_PATH="$PREFERENCE_ROOT/.build/preference-swift"
swift build --disable-sandbox --package-path "$PREFERENCE_ROOT/Packages/PreferenceLearning" --scratch-path "$PREFERENCE_ROOT/.build/preference" >&2
PREFERENCE_BIN="$(swift build --disable-sandbox --package-path "$PREFERENCE_ROOT/Packages/PreferenceLearning" --scratch-path "$PREFERENCE_ROOT/.build/preference" --show-bin-path)"
exec "$PREFERENCE_BIN/preference-eval" "$@"
