#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
PREFIX="${MAC_HOMEPOD_BREW_PREFIX:-/private/tmp}"
SDK="${MAC_HOMEPOD_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk}"
mkdir -p .cache/tests
clang -std=c11 -isysroot "$SDK" -I.deps/sources/owntone-29.2/src/libairptp -I"$PREFIX/include" Tests/ptp-peer-registration.c .deps/sources/owntone-29.2/src/libairptp/src/libairptp.a -L"$PREFIX/lib" -levent -levent_pthreads -o .cache/tests/ptp-peer
# Production uses both wildcard families. Test actual asynchronous registration,
# not merely the UDP sender's success return value.
.cache/tests/ptp-peer
