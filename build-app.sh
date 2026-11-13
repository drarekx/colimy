#!/bin/zsh
# Builds Colimy.app (release, universal) into ./build
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Colimy.app
VERSION=${VERSION:-1.0.0}
BUILD=${BUILD:-1}
swift build -c release --arch arm64 --arch x86_64
BIN=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Colimy

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Colimy"
# Icons come from brand/*.svg, rendered by scripts/make-icon.sh.
cp Resources/AppIcon.icns Resources/MenuBarIcon.png Resources/MenuBarIcon@2x.png "$APP/Contents/Resources/"
# Localized Info.plist strings (local network prompt).
cp -R Resources/*.lproj "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Colimy</string>
    <key>CFBundleIdentifier</key><string>com.egluu.colimy</string>
    <key>CFBundleName</key><string>Colimy</string>
    <key>CFBundleDisplayName</key><string>Colimy</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>en</string><string>es</string><string>ca</string></array>
    <key>NSLocalNetworkUsageDescription</key><string>Colimy starts Colima, and its containers need to reach services on your local network (databases, NAS, printers…).</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
(cd build && rm -f Colimy.zip && ditto -c -k --keepParent Colimy.app Colimy.zip)
echo "Built $APP ($VERSION) and build/Colimy.zip"
