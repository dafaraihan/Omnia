#!/bin/bash
# Bundles the locally installed development playback runtimes and every
# Homebrew dependency they load. Xcode runs this before signing Omnia, so the copied libraries receive
# the same development/distribution signature as the app instead of tripping
# macOS library validation at the first playback attempt.
set -euo pipefail

[[ "${PLATFORM_NAME:-}" == "macosx" ]] || exit 0

# Scripts/build-dev-libmpv.sh builds libmpv with Omnia's MoltenVK patch, which
# the Metal player needs; Homebrew's libmpv can only draw with OpenGL.
DEV_LIBMPV="${OMNIA_DEV_LIBMPV_CACHE:-$HOME/Library/Caches/Omnia/dev-libmpv}/current/lib/libmpv.2.dylib"
for CANDIDATE in "$DEV_LIBMPV" /opt/homebrew/opt/mpv/lib/libmpv.2.dylib /usr/local/opt/mpv/lib/libmpv.2.dylib; do
    if [[ -f "$CANDIDATE" ]]; then
        MPV_LIBRARY="$CANDIDATE"
        break
    fi
done

if [[ -z "${MPV_LIBRARY:-}" ]]; then
    echo "error: libmpv was not found. Install it with Homebrew: brew install mpv"
    exit 1
fi

for CANDIDATE in /opt/homebrew/opt/libtorrent-rasterbar/lib/libtorrent-rasterbar.dylib /usr/local/opt/libtorrent-rasterbar/lib/libtorrent-rasterbar.dylib; do
    if [[ -f "$CANDIDATE" ]]; then
        TORRENT_LIBRARY="$(otool -D "$CANDIDATE" | awk 'NR == 2 { print $1 }')"
        break
    fi
done

if [[ -z "${TORRENT_LIBRARY:-}" ]]; then
    echo "error: libtorrent-rasterbar was not found. Install it with Homebrew: brew install libtorrent-rasterbar"
    exit 1
fi

APP_ROOT="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
FRAMEWORKS_DIR="${APP_ROOT}/Contents/Frameworks"
MACOS_DIR="${APP_ROOT}/Contents/MacOS"
mkdir -p "$FRAMEWORKS_DIR"
mkdir -p "$MACOS_DIR"

copy_library() {
    local source="$1"
    local destination="$FRAMEWORKS_DIR/$(basename "$source")"
    [[ -f "$destination" ]] || cp -fL "$source" "$destination"
}

# libmpv is always replaced, so switching between the patched and Homebrew
# builds never leaves the other one bundled.
cp -fL "$MPV_LIBRARY" "$FRAMEWORKS_DIR/libmpv.2.dylib"
if [[ "$MPV_LIBRARY" == "$DEV_LIBMPV" ]]; then
    echo "note: bundling the patched libmpv with the Metal (MoltenVK) context"
else
    echo "warning: bundling Homebrew's libmpv, which can only use OpenGL; run Scripts/build-dev-libmpv.sh for Metal"
fi
# Homebrew exposes both full-version and compatibility symlinks. Keep only
# the compatibility install name that the linked executable requests.
find "$FRAMEWORKS_DIR" -maxdepth 1 -type f -name 'libtorrent-rasterbar*.dylib' -delete
copy_library "$TORRENT_LIBRARY"

# Resolve the full dynamic-library closure. Homebrew libraries deliberately
# keep absolute install names, so bundle every non-system dependency first.
did_copy=1
while [[ "$did_copy" == "1" ]]; do
    did_copy=0
    while IFS= read -r binary; do
        while IFS= read -r dependency; do
            case "$dependency" in
                /opt/homebrew/*|/usr/local/*)
                    if [[ -f "$dependency" && ! -f "$FRAMEWORKS_DIR/$(basename "$dependency")" ]]; then
                        copy_library "$dependency"
                        did_copy=1
                    fi
                    ;;
            esac
        done < <(otool -L "$binary" | awk 'NR > 1 { print $1 }')
    done < <(find "$FRAMEWORKS_DIR" -maxdepth 1 -type f -name '*.dylib' -print)
done

# The Vulkan loader finds MoltenVK through an ICD manifest. Homebrew's lives
# outside the sandbox, so bundle MoltenVK with a manifest that points at it;
# the player sets VK_DRIVER_FILES to that manifest before creating mpv.
MOLTENVK_LIBRARY=""
for CANDIDATE in /opt/homebrew/opt/molten-vk/lib/libMoltenVK.dylib /usr/local/opt/molten-vk/lib/libMoltenVK.dylib; do
    if [[ -f "$CANDIDATE" ]]; then
        MOLTENVK_LIBRARY="$CANDIDATE"
        break
    fi
done
ICD_DIRECTORY="${APP_ROOT}/Contents/Resources/vulkan/icd.d"
if [[ -n "$MOLTENVK_LIBRARY" && -f "$FRAMEWORKS_DIR/libvulkan.1.dylib" ]]; then
    cp -fL "$MOLTENVK_LIBRARY" "$FRAMEWORKS_DIR/libMoltenVK.dylib"
    mkdir -p "$ICD_DIRECTORY"
    cat > "$ICD_DIRECTORY/MoltenVK_icd.json" <<'JSON'
{
    "file_format_version": "1.0.0",
    "ICD": {
        "library_path": "../../../Frameworks/libMoltenVK.dylib",
        "api_version": "1.4.0",
        "is_portability_driver": true
    }
}
JSON
else
    rm -rf "$ICD_DIRECTORY" "$FRAMEWORKS_DIR/libMoltenVK.dylib"
fi

# Rewrite all bundled install names to @rpath and then rewrite references in
# every executable/dylib that is part of Omnia's process.
while IFS= read -r binary; do
    install_name_tool -id "@rpath/$(basename "$binary")" "$binary" 2>/dev/null || true
done < <(find "$FRAMEWORKS_DIR" -maxdepth 1 -type f -name '*.dylib' -print)

while IFS= read -r binary; do
    while IFS= read -r dependency; do
        local_name="$(basename "$dependency")"
        if [[ -f "$FRAMEWORKS_DIR/$local_name" ]]; then
            install_name_tool -change "$dependency" "@rpath/$local_name" "$binary" 2>/dev/null || true
        fi
    done < <(otool -L "$binary" | awk 'NR > 1 { print $1 }')
done < <(find "$MACOS_DIR" "$FRAMEWORKS_DIR" -maxdepth 1 -type f -print)

# The app's normal CodeSign phase signs the final wrapper. Sign nested dylibs
# here as well because they are custom build-phase outputs rather than Xcode
# framework targets.
if [[ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" && "${CODE_SIGNING_ALLOWED:-YES}" != "NO" ]]; then
    while IFS= read -r binary; do
        codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --options runtime --timestamp=none "$binary"
    done < <(find "$FRAMEWORKS_DIR" -maxdepth 1 -type f -name '*.dylib' -print)
fi
