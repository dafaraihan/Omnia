#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
verifier="$repo_root/Scripts/verify-playback-manifest.sh"
manifest="$repo_root/NativeDependencies/playback-dependencies.json"

"$verifier" --allow-pending-review "$manifest"
jq -e '
  .components
  | map(.name)
  | contains([
      "mpv", "ffmpeg", "libtorrent", "boost", "libbluray",
      "libplacebo", "libass", "freetype", "fribidi", "harfbuzz",
      "openssl", "libudfread", "jinja", "markupsafe", "vulkan-headers"
    ])
' "$manifest" >/dev/null

if "$verifier" "$manifest" >/dev/null 2>&1; then
    echo "expected the release gate to reject pending review" >&2
    exit 1
fi

fixture_directory="$(mktemp -d)"
trap 'rm -rf "$fixture_directory"' EXIT

expect_invalid() {
    local name="$1"
    local filter="$2"
    local fixture="$fixture_directory/$name.json"
    jq "$filter" "$manifest" > "$fixture"
    if "$verifier" --allow-pending-review "$fixture" >/dev/null 2>&1; then
        echo "expected invalid manifest to be rejected: $name" >&2
        exit 1
    fi
}

expect_invalid duplicate-name '.components[1].name = .components[0].name'
expect_invalid insecure-url '.components[0].source_url = "http://example.com/source.tar.gz"'
expect_invalid url-user-info '.components[0].source_url = "https://token@example.com/source.tar.gz"'
expect_invalid invalid-digest '.components[0].sha256 = "not-a-digest"'
expect_invalid unexpected-version '.components[0].version = "0.42.0"'
