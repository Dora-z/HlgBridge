#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ ! -f .build/native/lib/libuhdr.a ]; then Scripts/bootstrap.sh; fi
swift build -c release
APP="$PWD/dist/HlgBridge.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Licenses"
cp .build/release/HlgBridge "$APP/Contents/MacOS/"
cp .build/release/hlgbridge-cli dist/
cp .build/native/licenses/* "$APP/Contents/Resources/Licenses/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>HlgBridge</string>
<key>CFBundleDisplayName</key><string>HlgBridge</string>
<key>CFBundleIdentifier</key><string>io.github.dora-z.hlgbridge</string>
<key>CFBundleExecutable</key><string>HlgBridge</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
</dict></plist>
PLIST
# Local ad-hoc signature only; no Developer ID identity or notarization.
codesign --force --sign - "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" dist/HlgBridge-macOS.zip
printf '应用已生成：%s\n' "$APP"
