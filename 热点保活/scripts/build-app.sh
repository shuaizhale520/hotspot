#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="热点保活"
APP_PATH="$ROOT/dist/$APP_NAME.app"
BUILD_DIR="$ROOT/.build/app-build"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"

cd "$ROOT"
mkdir -p "$BUILD_DIR"
for ARCH in arm64 x86_64; do
    mkdir -p "$BUILD_DIR/ModuleCache-$ARCH"
    swiftc \
        -parse-as-library \
        -target "$ARCH-apple-macosx15.0" \
        -sdk "$SDK_PATH" \
        -module-cache-path "$BUILD_DIR/ModuleCache-$ARCH" \
        -swift-version 6 \
        -O \
        Sources/HotspotKeeper/main.swift \
        -framework AppKit \
        -framework SwiftUI \
        -framework Network \
        -framework ServiceManagement \
        -framework IOKit \
        -o "$BUILD_DIR/HotspotKeeper-$ARCH"
done
lipo -create \
    "$BUILD_DIR/HotspotKeeper-arm64" \
    "$BUILD_DIR/HotspotKeeper-x86_64" \
    -output "$BUILD_DIR/HotspotKeeper"

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BUILD_DIR/HotspotKeeper" "$APP_PATH/Contents/MacOS/HotspotKeeper"
cat > "$APP_PATH/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
    <key>CFBundleExecutable</key><string>HotspotKeeper</string>
    <key>CFBundleIdentifier</key><string>com.lgg.HotspotKeeper</string>
    <key>CFBundleName</key><string>热点保活</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --deep --sign - "$APP_PATH"
echo "Built: $APP_PATH"
