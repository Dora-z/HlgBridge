#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
PROJECT_DIR="$PWD"
APP_PATH="${1:-$PROJECT_DIR/dist/HlgBridge.app}"
if [ ! -d "$APP_PATH/Contents" ]; then
  printf '未找到应用：%s，请先运行 Scripts/build-app.sh\n' "$APP_PATH" >&2
  exit 1
fi
APP_PATH="$(cd "$(dirname "$APP_PATH")" && pwd)/$(basename "$APP_PATH")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
ARCHS="$(lipo -archs "$APP_PATH/Contents/MacOS/HlgBridge")"
case "$ARCHS" in
  x86_64) ARCH_LABEL=x64 ;;
  arm64) ARCH_LABEL=arm64 ;;
  *x86_64*arm64*|*arm64*x86_64*) ARCH_LABEL=universal ;;
  *) printf '不支持的架构：%s\n' "$ARCHS" >&2; exit 1 ;;
esac
PYTHON_BIN="${PYTHON_BIN:-python3}"
VENV="$PROJECT_DIR/.build/dmg-venv"
if [ ! -x "$VENV/bin/python" ]; then
  "$PYTHON_BIN" -c 'import sys; assert sys.version_info >= (3, 10), "DMG 构建需要 Python 3.10+，可通过 PYTHON_BIN 指定"'
  "$PYTHON_BIN" -m venv "$VENV"
fi
# Pinned build-only tools; nothing from this environment ships inside the DMG.
"$VENV/bin/python" -m pip install --disable-pip-version-check -r Scripts/dmg-requirements.txt
mkdir -p .build/dmg-artwork dist
swift Scripts/dmg-background.swift .build/dmg-artwork
codesign --verify --deep --strict "$APP_PATH"
OUTPUT="$PROJECT_DIR/dist/HlgBridge-v${VERSION}-macOS-${ARCH_LABEL}.dmg"
TEMP_OUTPUT="$PROJECT_DIR/dist/.HlgBridge-v${VERSION}-macOS-${ARCH_LABEL}.tmp.dmg"
trap 'rm -f "$TEMP_OUTPUT"' EXIT
"$VENV/bin/python" -m dmgbuild -s Scripts/dmg-settings.py \
  -D "app=$APP_PATH" -D "background=$PROJECT_DIR/.build/dmg-artwork/background.png" \
  HlgBridge "$TEMP_OUTPUT"
hdiutil verify "$TEMP_OUTPUT"
"$VENV/bin/python" Scripts/verify-dmg.py "$TEMP_OUTPUT"
mv -f "$TEMP_OUTPUT" "$OUTPUT"
(cd dist && shasum -a 256 "$(basename "$OUTPUT")" > "$(basename "$OUTPUT").sha256")
printf 'DMG 安装包已生成：%s\n' "$OUTPUT"
