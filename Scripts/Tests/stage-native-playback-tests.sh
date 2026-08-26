#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
stager="$repo_root/Omnia/Platform/Playback/stage-native-playback.sh"

if CONFIGURATION=Release PLATFORM_NAME=macosx \
    OMNIA_NATIVE_PLAYBACK_ROOT=/missing \
    /bin/bash "$stager" >/dev/null 2>&1; then
    echo "expected Release to reject a missing staged dependency root" >&2
    exit 1
fi

CONFIGURATION=Debug PLATFORM_NAME=iphonesimulator \
    /bin/bash "$stager"

debug_output="$(mktemp -d)"
trap 'rm -rf "$debug_output"' EXIT
CONFIGURATION=Debug PLATFORM_NAME=macosx \
    TARGET_BUILD_DIR="$debug_output" WRAPPER_NAME=Omnia.app \
    CODE_SIGNING_ALLOWED=NO \
    /bin/bash "$stager"

staged_torrent_count="$(find "$debug_output/Omnia.app/Contents/Frameworks" \
    -maxdepth 1 -name 'libtorrent-rasterbar*.dylib' | wc -l | tr -d ' ')"
if [[ "$staged_torrent_count" != "1" ]]; then
    echo "expected Debug to stage exactly one local torrent runtime" >&2
    exit 1
fi

if CONFIGURATION=Release PLATFORM_NAME=macosx \
    OMNIA_NATIVE_PLAYBACK_ROOT="$repo_root/NativeDependencies" \
    /bin/bash "$stager" >/dev/null 2>&1; then
    echo "expected Release to reject the pending dependency review" >&2
    exit 1
fi
