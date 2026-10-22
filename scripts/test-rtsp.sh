#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
PREFIX="${MAC_HOMEPOD_BREW_PREFIX:-/private/tmp}"
SDK="${MAC_HOMEPOD_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk}"
clang -g -fsanitize=address -isysroot "$SDK" -I"$PREFIX/include" -I.deps/sources/owntone-29.2/src/evrtsp Tests/rtsp-failed-request.c .deps/sources/owntone-29.2/src/evrtsp/rtsp.c -L"$PREFIX/lib" -levent -o .cache/tests/rtsp-failure
.cache/tests/rtsp-failure
