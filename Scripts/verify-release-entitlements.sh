#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <entitlements.plist>" >&2
    exit 64
fi

entitlements="$1"
[[ -f "$entitlements" ]] || {
    echo "error: release entitlements are missing" >&2
    exit 66
}

plutil -lint "$entitlements" >/dev/null || {
    echo "error: release entitlements are malformed" >&2
    exit 65
}

entitlement_is_true() {
    local key_path="${1//./\\.}"
    [[ "$(plutil -extract "$key_path" raw -o - "$entitlements" 2>/dev/null || true)" == "true" ]]
}

entitlement_is_true com.apple.security.app-sandbox || {
    echo "error: App Sandbox must be enabled" >&2
    exit 65
}

entitlement_is_true com.apple.security.network.client || {
    echo "error: outbound networking must be explicitly declared" >&2
    exit 65
}

for forbidden in \
    com.apple.security.cs.allow-jit \
    com.apple.security.cs.allow-unsigned-executable-memory \
    com.apple.security.cs.disable-executable-page-protection \
    com.apple.security.cs.allow-dyld-environment-variables \
    com.apple.security.cs.disable-library-validation \
    com.apple.security.get-task-allow; do
    if entitlement_is_true "$forbidden"; then
        echo "error: forbidden release entitlement is enabled" >&2
        exit 65
    fi
done

echo "release entitlements verified"
