#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MODULE_CACHE="$PROJECT_DIR/.build/module-cache"
SWIFTPM_CACHE="$PROJECT_DIR/.build/swiftpm-cache"
SWIFTPM_CONFIG="$PROJECT_DIR/.build/swiftpm-config"
SWIFTPM_SECURITY="$PROJECT_DIR/.build/swiftpm-security"

if xcodebuild -version >/dev/null 2>&1; then
    TASK_SDK="$(xcrun --sdk macosx --show-sdk-path)"
else
    TASK_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
fi

mkdir -p "$MODULE_CACHE" "$SWIFTPM_CACHE" "$SWIFTPM_CONFIG" "$SWIFTPM_SECURITY"

SDKROOT="$TASK_SDK" \
CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE" \
swift run \
    --disable-sandbox \
    --cache-path "$SWIFTPM_CACHE" \
    --config-path "$SWIFTPM_CONFIG" \
    --security-path "$SWIFTPM_SECURITY" \
    --package-path "$PROJECT_DIR" \
    MiniExplorerCoreTests
