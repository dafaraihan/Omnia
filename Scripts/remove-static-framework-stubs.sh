#!/bin/bash
# KSPlayer's FFmpegKit ships static libraries as .framework bundles. Xcode
# copies an empty placeholder for each into the app; the code itself is
# already linked into OmniaKSEngine.framework. A placeholder exports no
# symbols and nothing loads it, and on macOS its flat layout fails
# validation, so it is removed. Frameworks with any exported symbol stay.
set -euo pipefail

frameworks="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
[ -d "$frameworks" ] || exit 0

for bundle in "$frameworks"/*.framework; do
    [ -d "$bundle" ] || continue
    name="$(basename "$bundle" .framework)"
    binary="$bundle/$name"
    [ -f "$bundle/Versions/Current/$name" ] && binary="$bundle/Versions/Current/$name"
    [ -f "$binary" ] || continue
    if [ -z "$(xcrun nm -gU "$binary" 2>/dev/null | head -n 1)" ]; then
        rm -rf "$bundle"
        echo "Removed empty placeholder $name.framework"
    fi
done
