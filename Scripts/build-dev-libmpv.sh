#!/bin/bash
# Builds the Debug libmpv with Omnia's patches (the MoltenVK context that
# lets gpu-next draw into the player's Metal layer) against Homebrew's
# libraries. Homebrew's own libmpv has no such context. Release builds use
# Scripts/build-playback-dependencies.sh instead.
#
# The pinned mpv source is checked against the manifest's digest. Source and
# build stay outside the repository; the result goes to
# ~/Library/Caches/Omnia/dev-libmpv/current, which embed-libmpv.sh prefers
# over Homebrew's libmpv when it exists.
set -euo pipefail

script_directory="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_directory/.." && pwd)"
manifest="$repo_root/NativeDependencies/playback-dependencies.json"
patch_directory="$repo_root/NativeDependencies/patches/mpv"
cache_root="${OMNIA_DEV_LIBMPV_CACHE:-$HOME/Library/Caches/Omnia/dev-libmpv}"

for command_name in brew curl jq shasum tar meson ninja pkg-config git; do
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "error: required tool is unavailable: $command_name" >&2
        exit 69
    }
done

for formula in molten-vk vulkan-loader vulkan-headers libplacebo shaderc ffmpeg libass uchardet libbluray; do
    brew list --versions "$formula" >/dev/null 2>&1 || {
        echo "error: install the Homebrew dependency first: brew install $formula" >&2
        exit 69
    }
done

source_url="$(jq -r '.components[] | select(.name == "mpv") | .source_url' "$manifest")"
source_digest="$(jq -r '.components[] | select(.name == "mpv") | .sha256' "$manifest")"
version="$(jq -r '.components[] | select(.name == "mpv") | .version' "$manifest")"
[[ "$source_url" == https://* && "$source_digest" =~ ^[0-9a-f]{64}$ ]] || {
    echo "error: the manifest has no usable mpv source" >&2
    exit 65
}

# One build per mpv version and patch set.
patch_digest="$(cat "$patch_directory"/*.patch | shasum -a 256 | awk '{ print $1 }')"
build_key="mpv-$version-${patch_digest:0:12}"
install_root="$cache_root/$build_key"
if [[ -f "$install_root/lib/libmpv.2.dylib" ]]; then
    ln -sfn "$install_root" "$cache_root/current"
    echo "Patched libmpv is already built: $install_root"
    exit 0
fi

work_directory="$(mktemp -d /tmp/omnia-dev-libmpv.XXXXXX)"
trap 'rm -rf "$work_directory"' EXIT

echo "Fetching mpv $version…"
curl -fsSL --proto '=https' --tlsv1.2 "$source_url" -o "$work_directory/mpv.tar.gz"
actual_digest="$(shasum -a 256 "$work_directory/mpv.tar.gz" | awk '{ print $1 }')"
[[ "$actual_digest" == "$source_digest" ]] || {
    echo "error: mpv source digest mismatch ($actual_digest)" >&2
    exit 65
}
tar -xzf "$work_directory/mpv.tar.gz" -C "$work_directory"
source_directory="$(find "$work_directory" -mindepth 1 -maxdepth 1 -type d -name 'mpv-*' | head -n 1)"

for patch in "$patch_directory"/*.patch; do
    echo "Applying $(basename "$patch")…"
    git -C "$source_directory" apply "$patch"
done

brew_prefix="$(brew --prefix)"
export PKG_CONFIG_PATH="$brew_prefix/lib/pkgconfig:$brew_prefix/share/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
# mvk_vulkan.h for the MoltenVK context.
export CFLAGS="-I$brew_prefix/opt/molten-vk/include${CFLAGS:+ $CFLAGS}"
export OBJCFLAGS="$CFLAGS"

# Omnia only needs libmpv: no player binary, no scripting (Omnia turns every
# built-in script off, and LuaJIT was killed by the hardened runtime), no
# window or Swift code. OpenGL stays for the render-API fallback.
meson setup "$work_directory/build" "$source_directory" \
    --prefix="$install_root" \
    --buildtype=release \
    -Dbuild-date=false \
    -Dlibmpv=true -Dcplayer=false \
    -Dlua=disabled -Djavascript=disabled \
    -Dlibarchive=disabled -Duchardet=enabled -Dlibbluray=enabled \
    -Dcocoa=disabled -Dswift-build=disabled \
    -Dmacos-cocoa-cb=disabled -Dmacos-media-player=disabled -Dmacos-touchbar=disabled \
    -Dgl=enabled -Dgl-cocoa=disabled \
    -Dvulkan=enabled -Dmoltenvk=enabled \
    -Dmanpage-build=disabled -Dhtml-build=disabled

meson compile -C "$work_directory/build"
meson install -C "$work_directory/build"

ln -sfn "$install_root" "$cache_root/current"
echo "Built patched libmpv: $install_root"
