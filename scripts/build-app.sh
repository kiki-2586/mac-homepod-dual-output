#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="${MAC_HOMEPOD_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk}"
if [ ! -d "$SDK" ]; then SDK="$(xcrun --show-sdk-path)"; fi
mkdir -p .cache/clang dist/MacHomePod.app/Contents/{MacOS,Resources}
swiftc -swift-version 5 -O -sdk "$SDK" -target arm64-apple-macosx15.0 \
  -module-cache-path .cache/clang Sources/HomeSoundsSync/*.swift \
  -o dist/MacHomePod.app/Contents/MacOS/HomeSoundsSync \
  -framework AppKit -framework CoreAudio -framework AudioToolbox -framework AVFoundation
cp Info.plist dist/MacHomePod.app/Contents/Info.plist
cp LICENSE UPSTREAM.md dist/MacHomePod.app/Contents/Resources/
if [ -d backend/runtime/usr ]; then
  mkdir -p dist/MacHomePod.app/Contents/Resources/backend
  ditto backend/runtime/usr dist/MacHomePod.app/Contents/Resources/backend/usr
  if [ -d backend/licenses ]; then ditto backend/licenses dist/MacHomePod.app/Contents/Resources/backend/licenses; fi
fi
codesign --force --sign - --timestamp=none dist/MacHomePod.app
plutil -lint dist/MacHomePod.app/Contents/Info.plist
codesign --verify --deep --strict dist/MacHomePod.app
printf '已构建：%s/dist/MacHomePod.app\n' "$PWD"
