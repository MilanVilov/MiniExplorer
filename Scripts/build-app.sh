#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MODULE_CACHE="$PROJECT_DIR/.build/module-cache"
SWIFTPM_CACHE="$PROJECT_DIR/.build/swiftpm-cache"
SWIFTPM_CONFIG="$PROJECT_DIR/.build/swiftpm-config"
SWIFTPM_SECURITY="$PROJECT_DIR/.build/swiftpm-security"
APP_DIR="$PROJECT_DIR/.build/app/MiniExplorer.app"

if xcodebuild -version >/dev/null 2>&1; then
    TASK_SDK="$(xcrun --sdk macosx --show-sdk-path)"
else
    TASK_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
fi

mkdir -p "$MODULE_CACHE" "$SWIFTPM_CACHE" "$SWIFTPM_CONFIG" "$SWIFTPM_SECURITY"

SWIFT_OPTIONS=(
    --disable-sandbox
    --cache-path "$SWIFTPM_CACHE"
    --config-path "$SWIFTPM_CONFIG"
    --security-path "$SWIFTPM_SECURITY"
    --package-path "$PROJECT_DIR"
    --configuration release
)

SDKROOT="$TASK_SDK" \
CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE" \
swift build "${SWIFT_OPTIONS[@]}" --product MiniExplorer

BIN_PATH="$(
    SDKROOT="$TASK_SDK" \
    CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
    SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE" \
    swift build "${SWIFT_OPTIONS[@]}" --show-bin-path
)"

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_PATH/MiniExplorer" "$APP_DIR/Contents/MacOS/MiniExplorer"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
codesign --force --sign - --timestamp=none "$APP_DIR"

echo "$APP_DIR"
