#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
MACOS_ARCH="${MACOS_ARCH:-${1:-}}"
case "$MACOS_ARCH" in
  ""|x86_64|arm64) ;;
  *) printf '不支持的 macOS 架构：%s（可用 x86_64 或 arm64）\n' "$MACOS_ARCH" >&2; exit 1 ;;
esac
NEED_BOOTSTRAP=0
if [ ! -f .build/native/lib/libuhdr.a ]; then NEED_BOOTSTRAP=1
elif [ -n "$MACOS_ARCH" ] && command -v lipo >/dev/null 2>&1 && ! lipo -archs .build/native/lib/libuhdr.a | tr ' ' '\n' | grep -qx "$MACOS_ARCH"; then NEED_BOOTSTRAP=1
fi
if [ "$NEED_BOOTSTRAP" -eq 1 ]; then MACOS_ARCH="$MACOS_ARCH" Scripts/bootstrap.sh; fi
SWIFT_BUILD_ARGS=(-c release)
if [ -n "$MACOS_ARCH" ]; then SWIFT_BUILD_ARGS+=(--arch "$MACOS_ARCH"); fi
swift build "${SWIFT_BUILD_ARGS[@]}"
Scripts/build-icon.sh
APP="$PWD/dist/HlgBridge.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Licenses"
BUILD_DIR="$(swift build "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)"
cp "$BUILD_DIR/HlgBridge" "$APP/Contents/MacOS/"
cp .build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp "$BUILD_DIR/hlgbridge-cli" dist/
cp .build/native/licenses/* "$APP/Contents/Resources/Licenses/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>HlgBridge</string>
<key>CFBundleDisplayName</key><string>HlgBridge</string>
<key>CFBundleIdentifier</key><string>io.github.dora-z.hlgbridge</string>
<key>CFBundleExecutable</key><string>HlgBridge</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.2.1</string>
<key>CFBundleVersion</key><string>5</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
</dict></plist>
PLIST
# Local ad-hoc signature only; no Developer ID identity or notarization.
codesign --force --sign - "$APP"
if [ -n "$MACOS_ARCH" ] && command -v lipo >/dev/null 2>&1 && ! lipo -archs "$APP/Contents/MacOS/HlgBridge" | tr ' ' '\n' | grep -qx "$MACOS_ARCH"; then
  printf '构建产物架构不匹配：期望 %s，实际 %s\n' "$MACOS_ARCH" "$(lipo -archs "$APP/Contents/MacOS/HlgBridge")" >&2
  exit 1
fi
ditto -c -k --sequesterRsrc --keepParent "$APP" dist/HlgBridge-macOS.zip
printf '应用已生成：%s\n' "$APP"
Scripts/build-dmg.sh "$APP"
