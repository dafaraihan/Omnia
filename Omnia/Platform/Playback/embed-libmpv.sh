#!/bin/bash
# Bundles the locally installed libmpv runtime and every Homebrew dependency it
# loads. Xcode runs this before signing Omnia, so the copied libraries receive
# the same development/distribution signature as the app instead of tripping
# macOS library validation at the first playback attempt.
set -euo pipefail

[[ "${PLATFORM_NAME:-}" == "macosx" ]] || exit 0

for CANDIDATE in /opt/homebrew/opt/mpv/lib/libmpv.2.dylib /usr/local/opt/mpv/lib/libmpv.2.dylib; do
    if [[ -f "$CANDIDATE" ]]; then
        MPV_LIBRARY="$CANDIDATE"
        break
    fi
done

if [[ -z "${MPV_LIBRARY:-}" ]]; then
    echo "error: libmpv was not found. Install it with Homebrew: brew install mpv"
    exit 1
fi

APP_ROOT="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
FRAMEWORKS_DIR="${APP_ROOT}/Contents/Frameworks"
MACOS_DIR="${APP_ROOT}/Contents/MacOS"
mkdir -p "$FRAMEWORKS_DIR"

copy_library() {
    local source="$1"
    local destination="$FRAMEWORKS_DIR/$(basename "$source")"
    [[ -f "$destination" ]] || cp -fL "$source" "$destination"
}

copy_library "$MPV_LIBRARY"

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
