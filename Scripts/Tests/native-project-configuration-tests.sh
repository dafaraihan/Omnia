#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
project="$repo_root/Omnia.xcodeproj/project.pbxproj"

for expected in \
    '"$(OMNIA_NATIVE_PLAYBACK_ROOT)/Headers"' \
    '"$(OMNIA_NATIVE_PLAYBACK_ROOT)/Runtime"' \
    '"OMNIA_LOCAL_TORRENT=1"' \
    '"TORRENT_NO_DEPRECATE"' \
    '"$(OMNIA_NATIVE_PLAYBACK_ROOT)/Runtime/libmpv.2.dylib"' \
    '"$(OMNIA_NATIVE_PLAYBACK_ROOT)/Runtime/libtorrent-rasterbar.2.0.dylib"' \
    '"$(OMNIA_NATIVE_PLAYBACK_ROOT)/Runtime/libssl.3.dylib"' \
    '"$(OMNIA_NATIVE_PLAYBACK_ROOT)/Runtime/libcrypto.3.dylib"'; do
    rg -Fq "$expected" "$project" || {
        echo "missing native Release project setting: $expected" >&2
        exit 1
    }
done

for obsolete in '"-ltorrent-rasterbar"' '"-lssl"' '"-lcrypto"'; do
    if rg -Fq "$obsolete" "$project"; then
        echo "Release project still uses an unpinned native linker name: $obsolete" >&2
        exit 1
    fi
done

if rg -Fq '"$(OMNIA_NATIVE_PLAYBACK_ROOT)/Libraries"' "$project"; then
    echo "Release project still references the obsolete native Libraries directory" >&2
    exit 1
fi
