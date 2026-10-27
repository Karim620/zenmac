#!/usr/bin/env bash
set -euo pipefail

# ZenMac Open Source DMG Packager
# Packages release-optimized Swift 6 binary into a distributable, compressed macOS .dmg

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

APP_NAME="ZenMac"
VERSION="1.0.0"
DIST_DIR="$REPO_DIR/dist"
STAGING_DIR="$DIST_DIR/dmg_staging"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"

echo "🧘‍♂️ [1/6] Building $APP_NAME in Release mode (Swift 6)..."
swift build -c release

echo "🎨 [2/6] Ensuring high-DPI AppIcon.icns is up to date..."
if [ ! -f "AppIcon.icns" ] && [ -f "icon.png" ]; then
    ICONSET="ZenMac.iconset"
    mkdir -p "$ICONSET"
    sips -z 16 16     icon.png --out "$ICONSET/icon_16x16.png" >/dev/null
    sips -z 32 32     icon.png --out "$ICONSET/icon_16x16@2x.png" >/dev/null
    sips -z 32 32     icon.png --out "$ICONSET/icon_32x32.png" >/dev/null
    sips -z 64 64     icon.png --out "$ICONSET/icon_32x32@2x.png" >/dev/null
    sips -z 128 128   icon.png --out "$ICONSET/icon_128x128.png" >/dev/null
    sips -z 256 256   icon.png --out "$ICONSET/icon_128x128@2x.png" >/dev/null
    sips -z 256 256   icon.png --out "$ICONSET/icon_256x256.png" >/dev/null
    sips -z 512 512   icon.png --out "$ICONSET/icon_256x256@2x.png" >/dev/null
    sips -z 512 512   icon.png --out "$ICONSET/icon_512x512.png" >/dev/null
    sips -z 1024 1024 icon.png --out "$ICONSET/icon_512x512@2x.png" >/dev/null
    iconutil -c icns "$ICONSET" -o "AppIcon.icns"
    rm -rf "$ICONSET"
fi

echo "📦 [3/6] Assembling $APP_NAME.app bundle..."
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR" "$STAGING_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary from SPM release build
RELEASE_BIN=".build/out/Products/Release/$APP_NAME"
if [ ! -f "$RELEASE_BIN" ]; then
    RELEASE_BIN=".build/arm64-apple-macosx/release/$APP_NAME"
fi
cp "$RELEASE_BIN" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy assets
if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi
if [ -f "icon.png" ]; then
    cp icon.png "$APP_BUNDLE/Contents/Resources/icon.png"
fi

# Write Info.plist
cat <<EOF > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.zenmac.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

echo "✍️ [4/6] Ad-hoc codesigning $APP_NAME.app..."
codesign -s - --force --deep "$APP_BUNDLE"

echo "📂 [5/6] Preparing DMG staging environment..."
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

echo "💿 [6/6] Generating compressed DMG via hdiutil..."
rm -f "$DMG_PATH"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$STAGING_DIR"

echo "✅ Success! Distributable DMG created at:"
echo "   👉 $DMG_PATH ($(ls -lh "$DMG_PATH" | awk '{print $5}'))"
