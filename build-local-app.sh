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

if [ -d "$ROOT_DIR/AppResources" ]; then
    cp -R "$ROOT_DIR/AppResources/." "$RESOURCES_DIR/"
fi

if [ -f "$ROOT_DIR/AppResources/AppIcon.png" ]; then
    ICONSET_DIR="$RESOURCES_DIR/AgentFamily.iconset"
    mkdir -p "$ICONSET_DIR"
    sips -z 16 16 "$ROOT_DIR/AppResources/AppIcon.png" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
    sips -z 32 32 "$ROOT_DIR/AppResources/AppIcon.png" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
    sips -z 32 32 "$ROOT_DIR/AppResources/AppIcon.png" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
    sips -z 64 64 "$ROOT_DIR/AppResources/AppIcon.png" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
    sips -z 128 128 "$ROOT_DIR/AppResources/AppIcon.png" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
    sips -z 256 256 "$ROOT_DIR/AppResources/AppIcon.png" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
    sips -z 256 256 "$ROOT_DIR/AppResources/AppIcon.png" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
    sips -z 512 512 "$ROOT_DIR/AppResources/AppIcon.png" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
    sips -z 512 512 "$ROOT_DIR/AppResources/AppIcon.png" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
    sips -z 1024 1024 "$ROOT_DIR/AppResources/AppIcon.png" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
    iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AgentFamily.icns"
    rm -rf "$ICONSET_DIR"
fi

/usr/libexec/PlistBuddy -c "Clear dict" "$INFO_PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleDevelopmentRegion string ko" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $EXECUTABLE_NAME" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_ID" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleInfoDictionaryVersion string 6.0" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string $APP_NAME" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $APP_NAME" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AgentFamily" "$INFO_PLIST"
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
