#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Agent Family"
EXECUTABLE_NAME="AgentFamily"
BUNDLE_ID="com.sjw.agentfamily"
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${TMPDIR:-/tmp}/agent-family-build-${USER:-local}"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INFO_PLIST="$CONTENTS_DIR/Info.plist"

cd "$ROOT_DIR"

swift build -c release --build-path "$BUILD_DIR"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BUILD_DIR/release/$EXECUTABLE_NAME" "$MACOS_DIR/$EXECUTABLE_NAME"
chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"

/usr/libexec/PlistBuddy -c "Clear dict" "$INFO_PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleDevelopmentRegion string ko" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $EXECUTABLE_NAME" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_ID" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleInfoDictionaryVersion string 6.0" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string $APP_NAME" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $APP_NAME" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 0.2.0" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 2" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 14.0" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :NSAppleEventsUsageDescription string Agent Family needs permission to read, activate, and control Terminal and iTerm windows." "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :NSHumanReadableCopyright string Copyright (c) 2026 SJW. All rights reserved." "$INFO_PLIST"

printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"
xattr -dr com.apple.quarantine "$APP_DIR" 2>/dev/null || true

echo "Built: $APP_DIR"
