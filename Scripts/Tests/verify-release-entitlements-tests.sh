#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
verifier="$repo_root/Scripts/verify-release-entitlements.sh"
entitlements="$repo_root/Omnia.entitlements"
fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT

"$verifier" "$entitlements"

forbidden="$fixture_root/forbidden.plist"
cp "$entitlements" "$forbidden"
plutil -insert 'com\.apple\.security\.cs\.allow-jit' -bool YES "$forbidden"
if "$verifier" "$forbidden" >/dev/null 2>&1; then
    echo "expected allow-jit entitlement to fail" >&2
    exit 1
fi

missing_sandbox="$fixture_root/missing-sandbox.plist"
cp "$entitlements" "$missing_sandbox"
plutil -remove 'com\.apple\.security\.app-sandbox' "$missing_sandbox"
if "$verifier" "$missing_sandbox" >/dev/null 2>&1; then
    echo "expected missing App Sandbox entitlement to fail" >&2
    exit 1
fi
