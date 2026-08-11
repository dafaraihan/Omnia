#!/bin/bash
set -euo pipefail

[[ "${PLATFORM_NAME:-}" == "macosx" ]] || exit 0

script_directory="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_directory/../../.." && pwd)"

if [[ "${CONFIGURATION:-Debug}" != "Release" ]]; then
    exec /bin/bash "$script_directory/embed-libmpv.sh"
fi

fail() {
    echo "error: verified native playback artifacts are required for macOS Release builds: $1" >&2
    exit 65
}

native_root="${OMNIA_NATIVE_PLAYBACK_ROOT:-}"
[[ -n "$native_root" && -d "$native_root" ]] || fail "set OMNIA_NATIVE_PLAYBACK_ROOT"
[[ -f "$native_root/playback-dependencies.json" ]] || fail "dependency manifest is missing"
[[ -n "${TARGET_BUILD_DIR:-}" && -n "${WRAPPER_NAME:-}" ]] || fail "Xcode output settings are missing"

/bin/bash "$repo_root/Scripts/verify-playback-manifest.sh" \
    "$native_root/playback-dependencies.json"
/bin/bash "$repo_root/Scripts/verify-playback-artifacts.sh" "$native_root"

frameworks_directory="${TARGET_BUILD_DIR}/${WRAPPER_NAME}/Contents/Frameworks"
mkdir -p "$frameworks_directory"

while IFS= read -r relative_path; do
    source_library="$native_root/$relative_path"
    destination_library="$frameworks_directory/$(basename "$relative_path")"
    cp -f "$source_library" "$destination_library"

    if [[ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" && "${CODE_SIGNING_ALLOWED:-YES}" != "NO" ]]; then
        codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" \
            --options runtime --timestamp=none "$destination_library"
    fi
done < <(jq -r '.artifacts[].path' "$native_root/build-metadata.json")
