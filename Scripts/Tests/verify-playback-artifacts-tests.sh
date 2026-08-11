#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
verifier="$repo_root/Scripts/verify-playback-artifacts.sh"
fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT

make_fixture() {
    local destination="$1"
    mkdir -p "$destination/Runtime" "$destination/Licenses"
    printf '%s\n' 'fixture license' > "$destination/Licenses/sample.txt"

    clang -dynamiclib -arch arm64 -x c /dev/null \
        -install_name '@rpath/libsample.dylib' \
        -o "$destination/Runtime/libsample-arm64.dylib"
    clang -dynamiclib -arch x86_64 -x c /dev/null \
        -install_name '@rpath/libsample.dylib' \
        -o "$destination/Runtime/libsample-x86_64.dylib"
    lipo -create \
        "$destination/Runtime/libsample-arm64.dylib" \
        "$destination/Runtime/libsample-x86_64.dylib" \
        -output "$destination/Runtime/libsample.dylib"
    rm "$destination/Runtime/libsample-arm64.dylib" \
        "$destination/Runtime/libsample-x86_64.dylib"

    local digest
    digest="$(shasum -a 256 "$destination/Runtime/libsample.dylib" | awk '{print $1}')"
    jq -n --arg digest "$digest" '
      {
        schema_version: 1,
        architectures: ["arm64", "x86_64"],
        build_flags: {
          mpv: ["-Dgpl=false", "-Dlibmpv=true", "-Dcplayer=false"],
          ffmpeg: ["--disable-gpl", "--disable-nonfree"]
        },
        artifacts: [{
          path: "Runtime/libsample.dylib",
          sha256: $digest,
          license_path: "Licenses/sample.txt"
        }]
      }
    ' > "$destination/build-metadata.json"
}

expect_failure() {
    local name="$1"
    local fixture="$fixture_root/$name"
    make_fixture "$fixture"
    "$2" "$fixture"
    local digest
    digest="$(shasum -a 256 "$fixture/Runtime/libsample.dylib" | awk '{print $1}')"
    jq --arg digest "$digest" '.artifacts[0].sha256 = $digest' \
        "$fixture/build-metadata.json" > "$fixture/refreshed.json"
    mv "$fixture/refreshed.json" "$fixture/build-metadata.json"
    if "$verifier" "$fixture" > "$fixture/stdout.log" 2> "$fixture/stderr.log"; then
        echo "expected artifact verification failure: $name" >&2
        exit 1
    fi
    if rg -q '/Users/|/home/' "$fixture/stdout.log" "$fixture/stderr.log"; then
        echo "verifier exposed a user home path: $name" >&2
        exit 1
    fi
}

leave_thin() {
    local fixture="$1"
    clang -dynamiclib -arch arm64 -x c /dev/null \
        -install_name '@rpath/libsample.dylib' \
        -o "$fixture/Runtime/libsample.dylib"
}

add_homebrew_dependency() {
    local fixture="$1"
    install_name_tool -change /usr/lib/libSystem.B.dylib \
        /opt/homebrew/opt/unsafe/lib/libunsafe.dylib \
        "$fixture/Runtime/libsample.dylib"
}

remove_license() {
    local fixture="$1"
    rm "$fixture/Licenses/sample.txt"
}

enable_gpl() {
    local fixture="$1"
    jq '.build_flags.ffmpeg += ["--enable-gpl"]' \
        "$fixture/build-metadata.json" > "$fixture/changed.json"
    mv "$fixture/changed.json" "$fixture/build-metadata.json"
}

expect_failure missing-architecture leave_thin
expect_failure homebrew-install-name add_homebrew_dependency
expect_failure missing-license remove_license
expect_failure gpl-enabled-ffmpeg enable_gpl

valid_fixture="$fixture_root/valid"
make_fixture "$valid_fixture"
"$verifier" "$valid_fixture"
