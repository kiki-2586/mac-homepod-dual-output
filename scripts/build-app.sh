#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="${MAC_HOMEPOD_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk}"
if [ ! -d "$SDK" ]; then SDK="$(xcrun --show-sdk-path)"; fi
APP="${MAC_HOMEPOD_APP_PATH:-dist/MacHomePod.app}"
mkdir -p .cache/clang "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -swift-version 5 -O -sdk "$SDK" -target arm64-apple-macosx15.0 \
  -module-cache-path .cache/clang Sources/HomeSoundsSync/*.swift \
  -o "$APP/Contents/MacOS/HomeSoundsSync" \
  -framework AppKit -framework CoreAudio -framework AudioToolbox -framework AVFoundation
cp Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.png ]; then
  bash scripts/build-icon.sh "$APP/Contents/Resources/AppIcon.icns"
fi
cp LICENSE UPSTREAM.md "$APP/Contents/Resources/"
if [ -d backend/runtime/usr ]; then
  mkdir -p "$APP/Contents/Resources/backend"
  ditto backend/runtime/usr "$APP/Contents/Resources/backend/usr"
  if [ -d backend/licenses ]; then ditto backend/licenses "$APP/Contents/Resources/backend/licenses"; fi
fi
codesign --force --sign - --timestamp=none "$APP"
plutil -lint "$APP/Contents/Info.plist"
codesign --verify --deep --strict "$APP"
printf '已构建：%s\n' "$APP"
