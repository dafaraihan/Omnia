#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
work_root="$(mktemp -d /tmp/omnia-local-torrent-tests.XXXXXX)"
trap 'rm -rf "$work_root"' EXIT

mkdir -p "$work_root/module-cache"
xcrun swiftc \
    -module-cache-path "$work_root/module-cache" \
    "$repo_root/Omnia/Domain/Playback/LocalTorrentPlayback.swift" \
    "$repo_root/Scripts/Tests/LocalTorrentDescriptorSmoke.swift" \
    -o "$work_root/local-torrent-descriptor-tests"
"$work_root/local-torrent-descriptor-tests"
