#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
builder="$repo_root/Scripts/build-playback-dependencies.sh"
real_manifest="$repo_root/NativeDependencies/playback-dependencies.json"
fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT

plan_output="$fixture_root/plan-output"
(
    cd "$repo_root"
    OMNIA_NATIVE_BUILD_MODE=plan-only \
        /bin/bash Scripts/build-playback-dependencies.sh \
        NativeDependencies/playback-dependencies.json "$plan_output"
)
jq -e '
  .schema_version == 1 and
  .deployment_target == "26.5" and
  .architectures == ["arm64", "x86_64"] and
  .architecture_configuration.x86_64 == "meson-cross-file" and
  .build_order == [
    "boost", "openssl", "freetype", "fribidi", "harfbuzz", "libass",
    "libplacebo", "ffmpeg", "libbluray", "libtorrent", "mpv"
  ] and
  (.build_only_components == ["jinja", "markupsafe", "vulkan-headers"]) and
  (.build_flags.mpv | index("-Dgpl=false") != null) and
  (.build_flags.mpv | index("-Dlua=disabled") != null) and
  (.build_flags.mpv | index("-Djavascript=disabled") != null) and
  (.build_flags.mpv | index("-Ddvdnav=disabled") != null) and
  (.build_flags.ffmpeg | index("--disable-gpl") != null) and
  (.build_flags.ffmpeg | index("--disable-nonfree") != null) and
  (.build_flags.libplacebo | index("-Dopengl=disabled") != null) and
  (.build_flags.harfbuzz | index("-Dsubset=disabled") != null) and
  (.build_flags.openssl | index("no-module") != null) and
  (.build_flags.libtorrent | index("TORRENT_DISABLE_LOGGING=ON") != null) and
  (.embedded_components == ["libudfread"])
' "$plan_output/build-plan.json" >/dev/null

mkdir -p "$fixture_root/safe/package"
printf '%s\n' 'bounded native source fixture' > "$fixture_root/safe/package/README"
tar -czf "$fixture_root/safe.tar.gz" -C "$fixture_root/safe" package
safe_digest="$(shasum -a 256 "$fixture_root/safe.tar.gz" | awk '{print $1}')"

jq --arg digest "$safe_digest" '
  .components |= map(
    .source_url = "https://fixtures.example/source.tar.gz"
    | .sha256 = $digest
  )
' "$real_manifest" > "$fixture_root/safe-manifest.json"

run_fetch() {
    local manifest="$1"
    local output="$2"
    OMNIA_NATIVE_BUILD_MODE=fetch-only \
    OMNIA_TEST_ARCHIVE="$fixture_root/safe.tar.gz" \
    PATH="$repo_root/Scripts/Tests/Fixtures:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin" \
        /bin/bash "$builder" "$manifest" "$output"
}

safe_output="$fixture_root/safe-output"
mkdir -p "$fixture_root/populated-cache"
OMNIA_NATIVE_BUILD_MODE=fetch-only \
OMNIA_NATIVE_SOURCE_CACHE="$fixture_root/populated-cache" \
OMNIA_TEST_ARCHIVE="$fixture_root/safe.tar.gz" \
PATH="$repo_root/Scripts/Tests/Fixtures:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin" \
    /bin/bash "$builder" "$fixture_root/safe-manifest.json" "$safe_output"
if [[ ! -f "$fixture_root/populated-cache/$safe_digest" || \
      -L "$fixture_root/populated-cache/$safe_digest" ]]; then
    echo "expected fetch mode to populate a regular digest-addressed cache entry" >&2
    exit 1
fi
if [[ "$(shasum -a 256 "$fixture_root/populated-cache/$safe_digest" | awk '{print $1}')" != "$safe_digest" ]]; then
    echo "expected populated cache entry to retain the verified digest" >&2
    exit 1
fi
jq -e \
  --argjson expected "$(jq '.components | length' "$real_manifest")" \
  --arg digest "$safe_digest" '
  .schema_version == 1 and
  (.components | length) == $expected and
  all(.components[]; .sha256 == $digest)
' "$safe_output/source-metadata.json" >/dev/null

mkdir -p "$fixture_root/cache"
cp "$fixture_root/safe.tar.gz" "$fixture_root/cache/$safe_digest"
cache_output="$fixture_root/cache-output"
OMNIA_NATIVE_BUILD_MODE=fetch-only \
OMNIA_NATIVE_SOURCE_CACHE="$fixture_root/cache" \
OMNIA_TEST_ARCHIVE=/missing \
PATH="$repo_root/Scripts/Tests/Fixtures:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin" \
    /bin/bash "$builder" "$fixture_root/safe-manifest.json" "$cache_output"
jq -e --arg digest "$safe_digest" '
  all(.components[]; .sha256 == $digest)
' "$cache_output/source-metadata.json" >/dev/null

mkdir -p "$fixture_root/relative-link/package"
printf '%s\n' 'relative link target' > "$fixture_root/relative-link/package/AGENTS.md"
ln -s AGENTS.md "$fixture_root/relative-link/package/CLAUDE.md"
tar -czf "$fixture_root/relative-link.tar.gz" -C "$fixture_root/relative-link" package
relative_link_digest="$(shasum -a 256 "$fixture_root/relative-link.tar.gz" | awk '{print $1}')"
jq --arg digest "$relative_link_digest" '
  .components |= map(
    .source_url = "https://fixtures.example/source.tar.gz"
    | .sha256 = $digest
  )
' "$real_manifest" > "$fixture_root/relative-link-manifest.json"
OMNIA_NATIVE_BUILD_MODE=fetch-only \
OMNIA_TEST_ARCHIVE="$fixture_root/relative-link.tar.gz" \
PATH="$repo_root/Scripts/Tests/Fixtures:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin" \
    /bin/bash "$builder" \
    "$fixture_root/relative-link-manifest.json" \
    "$fixture_root/relative-link-output"

jq '.components[0].sha256 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' \
    "$fixture_root/safe-manifest.json" > "$fixture_root/bad-hash-manifest.json"
if run_fetch "$fixture_root/bad-hash-manifest.json" "$fixture_root/bad-hash-output" \
    >/dev/null 2>&1; then
    echo "expected a source digest mismatch to fail" >&2
    exit 1
fi

mkdir -p "$fixture_root/link/package"
ln -s /tmp "$fixture_root/link/package/escape"
tar -czf "$fixture_root/link.tar.gz" -C "$fixture_root/link" package
link_digest="$(shasum -a 256 "$fixture_root/link.tar.gz" | awk '{print $1}')"
jq --arg digest "$link_digest" '
  .components |= map(
    .source_url = "https://fixtures.example/source.tar.gz"
    | .sha256 = $digest
  )
' "$real_manifest" > "$fixture_root/link-manifest.json"

if OMNIA_NATIVE_BUILD_MODE=fetch-only \
    OMNIA_TEST_ARCHIVE="$fixture_root/link.tar.gz" \
    PATH="$repo_root/Scripts/Tests/Fixtures:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin" \
    /bin/bash "$builder" "$fixture_root/link-manifest.json" "$fixture_root/link-output" \
    >/dev/null 2>&1; then
    echo "expected an archive containing a symbolic link to fail" >&2
    exit 1
fi
