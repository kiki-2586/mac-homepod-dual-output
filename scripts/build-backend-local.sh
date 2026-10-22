#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
BREW_PREFIX="${MAC_HOMEPOD_BREW_PREFIX:-/private/tmp}"
export PATH="$BREW_PREFIX/bin:$PATH"
export PKG_CONFIG_PATH="$ROOT/backend/usr/lib/pkgconfig:$BREW_PREFIX/lib/pkgconfig:$BREW_PREFIX/opt/sqlite/lib/pkgconfig:$BREW_PREFIX/opt/openssl@3/lib/pkgconfig"
SDK="${MAC_HOMEPOD_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk}"
export ZLIB_CFLAGS="-I$SDK/usr/include" ZLIB_LIBS=-lz
export LIBCURL_CFLAGS="-I$SDK/usr/include" LIBCURL_LIBS=-lcurl
export LIBXML2_CFLAGS="-I$SDK/usr/include/libxml2" LIBXML2_LIBS=-lxml2
export CFLAGS="-O2 -I$BREW_PREFIX/include -I$ROOT/backend/usr/include -I$BREW_PREFIX/opt/sqlite/include -isysroot $SDK -Wno-error"
export LDFLAGS="-L$BREW_PREFIX/lib -L$ROOT/backend/usr/lib -L$BREW_PREFIX/opt/sqlite/lib -isysroot $SDK"
cd .deps/sources/owntone-29.2
./configure --prefix="$ROOT/backend/usr" --sysconfdir="$ROOT/backend/etc" --localstatedir="$ROOT/backend/var" --disable-spotify --disable-lastfm --disable-mpd --disable-webinterface --disable-install_systemd --disable-install_conf_file > "$ROOT/logs/owntone-configure.log" 2>&1
make -j6 > "$ROOT/logs/owntone-build.log" 2>&1
make install > "$ROOT/logs/owntone-install.log" 2>&1
