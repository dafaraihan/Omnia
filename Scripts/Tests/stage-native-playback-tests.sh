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

if CONFIGURATION=Release PLATFORM_NAME=macosx \
    OMNIA_NATIVE_PLAYBACK_ROOT="$repo_root/NativeDependencies" \
    /bin/bash "$stager" >/dev/null 2>&1; then
    echo "expected Release to reject the pending dependency review" >&2
    exit 1
fi
