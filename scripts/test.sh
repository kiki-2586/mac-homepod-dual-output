#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="${MAC_HOMEPOD_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk}"
if [ ! -d "$SDK" ]; then SDK="$(xcrun --show-sdk-path)"; fi
mkdir -p .cache/tests
COMMON=(-swift-version 5 -sdk "$SDK" -target arm64-apple-macosx15.0 -module-cache-path .cache/clang)
AUDIO=(Sources/HomeSoundsSync/{PCM48kConverter,AudioFrameQueue,FifoFeed,Diagnostics}.swift)
swiftc "${COMMON[@]}" "${AUDIO[@]}" Tests/AudioPipelineTests.swift -o .cache/tests/audio
.cache/tests/audio
swiftc "${COMMON[@]}" "${AUDIO[@]}" Sources/HomeSoundsSync/{ProcessTapCapture,RingBuffer}.swift Tests/CaptureConfigTests.swift -o .cache/tests/capture
.cache/tests/capture
cp Tests/ringtest.swift .cache/tests/main.swift
swiftc "${COMMON[@]}" Sources/HomeSoundsSync/RingBuffer.swift .cache/tests/main.swift -o .cache/tests/ring
.cache/tests/ring
swiftc "${COMMON[@]}" Sources/HomeSoundsSync/OwnToneClient.swift Tests/BackendTests.swift -o .cache/tests/backend
.cache/tests/backend
swiftc "${COMMON[@]}" Sources/HomeSoundsSync/{OwnToneService,ProcessTermination}.swift Tests/ServiceFilesystemTests.swift -o .cache/tests/service
.cache/tests/service
swiftc "${COMMON[@]}" Sources/HomeSoundsSync/PlaybackLifecycle.swift Tests/PlaybackLifecycleTests.swift -o .cache/tests/lifecycle
.cache/tests/lifecycle
if [ -f backend/runtime/usr/lib/libavformat.61.dylib ]; then
  clang -isysroot "$SDK" Tests/backend-capabilities.c -o .cache/tests/backend-capabilities
  .cache/tests/backend-capabilities "$PWD/backend/runtime/usr/lib"
fi
