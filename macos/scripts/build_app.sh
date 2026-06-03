#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$(cd "$ROOT_DIR/../../.." && pwd)/packages"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$PACKAGE_DIR/BT Sentinel Mac.app"
ZIP_PATH="$PACKAGE_DIR/BT-Sentinel-Mac-1.0-beta.zip"

mkdir -p "$PACKAGE_DIR"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR" "$ZIP_PATH"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BUILD_DIR/BTSentinelMac" "$APP_DIR/Contents/MacOS/BTSentinelMac"
cp "$ROOT_DIR/PackageSupport/Info.plist" "$APP_DIR/Contents/Info.plist"

codesign --force --deep --sign - "$APP_DIR"
ditto -c -k --norsrc --keepParent "$APP_DIR" "$ZIP_PATH"

echo "$APP_DIR"
echo "$ZIP_PATH"
