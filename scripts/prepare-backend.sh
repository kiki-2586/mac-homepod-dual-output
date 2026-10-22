#!/bin/bash
# Build the backend from fixed source archives; never registers system services.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
BREW="${MAC_HOMEPOD_BREW_BIN:-$(command -v brew || true)}"
if [ -z "$BREW" ] && [ -x /private/tmp/bin/brew ]; then BREW=/private/tmp/bin/brew; fi
if [ ! -x "$BREW" ]; then
  echo '需要 Homebrew 来构建后端。直接使用完整 .app 不需要安装 Homebrew。' >&2
  exit 1
fi
mkdir -p .deps/sources logs backend/usr
DEPS=(pkgconf gettext libunistring confuse libplist libwebsockets libevent libgcrypt json-c protobuf-c libsodium gnutls openssl@3 sqlite)
ASK=()
if "$BREW" install --help 2>&1 | rg -q -- --no-ask; then ASK=(--no-ask); fi
HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 "$BREW" install "${ASK[@]}" "${DEPS[@]}"
fetch() {
  local file="$1" expected="$2" url="$3"
  if [ ! -f "$file" ]; then
    curl -fL --retry 5 --retry-all-errors -o "$file.partial" "$url"
    mv "$file.partial" "$file"
  fi
  local actual
  actual=$(shasum -a 256 "$file" | awk '{print $1}')
  if [ "$actual" != "$expected" ]; then echo "校验失败：$file" >&2; exit 1; fi
}
fetch .deps/sources/owntone-29.2.tar.xz 4d5693f7fb34ced35a7a0937acca244184b46aa4cd1dc623a3f5dbfc02b7e0cf https://github.com/owntone/owntone-server/releases/download/29.2/owntone-29.2.tar.xz
fetch .deps/sources/ffmpeg-7.1.2.complete.tar.xz 089bc60fb59d6aecc5d994ff530fd0dcb3ee39aa55867849a2bbc4e555f9c304 https://ffmpeg.org/releases/ffmpeg-7.1.2.tar.xz
fetch .deps/sources/libinotify-20240724.tar.gz 5cc3fb7af407b17b7daa871cc98bb882716c4b5c296fadfb66bfe86c37cc599c https://github.com/libinotify-kqueue/libinotify-kqueue/releases/download/20240724/libinotify-20240724.tar.gz
for archive in .deps/sources/owntone-29.2.tar.xz .deps/sources/ffmpeg-7.1.2.complete.tar.xz .deps/sources/libinotify-20240724.tar.gz; do tar -xf "$archive" -C .deps/sources; done
(cd .deps/sources/owntone-29.2 && patch --forward -p1 < "$ROOT/patches/owntone-macos-ptp.patch" && patch --forward -p1 < "$ROOT/patches/owntone-audio-udp.patch" && patch --forward -p1 < "$ROOT/patches/owntone-rtsp-failed-request.patch")
SDK="${MAC_HOMEPOD_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk}"
cd .deps/sources/ffmpeg-7.1.2
./configure --prefix="$ROOT/backend/usr" --cc=clang --extra-cflags="-isysroot $SDK -mmacosx-version-min=15.0" --extra-ldflags="-isysroot $SDK" --disable-everything --disable-autodetect --enable-shared --disable-static --disable-programs --disable-doc --enable-encoder=alac,pcm_s16le,pcm_s16be --enable-decoder=alac,pcm_s16le,pcm_s16be,mp3,flac,aac --enable-demuxer=wav,pcm_s16le,mp3,flac,mov --enable-muxer=wav,pcm_s16le,data --enable-protocol=file,pipe --enable-filter=abuffer,abuffersink,aformat,aresample,volume,anull > "$ROOT/logs/ffmpeg-configure.log" 2>&1
make -j6 > "$ROOT/logs/ffmpeg-build.log" 2>&1
make install > "$ROOT/logs/ffmpeg-install.log" 2>&1
cd ../libinotify-20240724
./configure --prefix="$ROOT/backend/usr" CFLAGS="-O2 -Wno-error -isysroot $SDK" > "$ROOT/logs/inotify-configure.log" 2>&1
make -j4 > "$ROOT/logs/inotify-build.log" 2>&1
make install > "$ROOT/logs/inotify-install.log" 2>&1
cd "$ROOT"
export MAC_HOMEPOD_BREW_PREFIX
MAC_HOMEPOD_BREW_PREFIX=$("$BREW" --prefix)
bash scripts/build-backend-local.sh
python3 scripts/bundle-backend.py
mkdir -p backend/licenses
cp .deps/sources/owntone-29.2/COPYING backend/licenses/OwnTone-GPL-2.txt
cp .deps/sources/ffmpeg-7.1.2/COPYING.LGPLv2.1 backend/licenses/FFmpeg-LGPL-2.1.txt
cp .deps/sources/libinotify-20240724/LICENSE backend/licenses/libinotify-LICENSE
