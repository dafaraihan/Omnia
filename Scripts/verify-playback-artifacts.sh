#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <staged-artifact-directory>" >&2
    exit 64
fi

artifact_root="$1"
metadata="$artifact_root/build-metadata.json"
sbom="$artifact_root/native-playback.spdx.json"

fail() {
    echo "error: native playback artifact verification failed: $1" >&2
    exit 65
}

for command_name in jq shasum lipo otool find rg; do
    command -v "$command_name" >/dev/null 2>&1 || fail "required inspection tool is unavailable"
done

[[ -d "$artifact_root" ]] || fail "artifact directory is missing"
[[ -f "$metadata" ]] || fail "build metadata is missing"
[[ -f "$sbom" ]] || fail "SPDX SBOM is missing"
[[ -d "$artifact_root/Runtime" ]] || fail "runtime directory is missing"

jq -e '
  .schema_version == 1 and
  .architectures == ["arm64", "x86_64"] and
  (.build_flags.mpv | type == "array" and
    index("-Dgpl=false") != null and
    index("-Dlibmpv=true") != null and
    index("-Dcplayer=false") != null) and
  (.build_flags.ffmpeg | type == "array" and
    index("--disable-gpl") != null and
    index("--disable-nonfree") != null) and
  ([.build_flags[][] | ascii_downcase]
    | all(. != "--enable-gpl" and . != "--enable-nonfree" and . != "-dgpl=true")) and
  (.artifacts | type == "array" and length > 0) and
  (all(.artifacts[];
    (.path | type == "string" and test("^Runtime/[A-Za-z0-9][A-Za-z0-9+._-]*\\.dylib$")) and
    (.sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
    (.license_path | type == "string" and test("^Licenses/[A-Za-z0-9][A-Za-z0-9+._-]*$"))
  )) and
  ((.artifacts | map(.path) | unique | length) == (.artifacts | length))
' "$metadata" >/dev/null || fail "metadata is malformed or contains forbidden build flags"

if rg -qi '(/opt/homebrew|/usr/local|/Users/|/home/)' "$metadata"; then
    fail "metadata contains a machine-local path"
fi

jq -e --slurpfile metadata "$metadata" '
  .spdxVersion == "SPDX-2.3" and
  .dataLicense == "CC0-1.0" and
  .SPDXID == "SPDXRef-DOCUMENT" and
  (.documentNamespace | type == "string" and test("^https://")) and
  (.creationInfo.created | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")) and
  (.creationInfo.creators | type == "array" and length > 0) and
  (.packages | type == "array" and length > 0) and
  (all(.packages[];
    (.SPDXID | type == "string" and test("^SPDXRef-Package-")) and
    (.name | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9+._-]*$")) and
    (.versionInfo | type == "string" and length > 0) and
    (.downloadLocation | type == "string" and test("^https://")) and
    .filesAnalyzed == false and
    (.licenseDeclared | type == "string" and . != "NOASSERTION") and
    (.checksums | any(
      .algorithm == "SHA256" and
      (.checksumValue | test("^[0-9a-f]{64}$"))
    ))
  )) and
  ((.packages | map(.SPDXID) | unique | length) == (.packages | length)) and
  (.relationships | type == "array" and length > 0) and
  ([.packages[].SPDXID] as $package_ids |
    all(.relationships[];
      . as $relationship |
      ($relationship.spdxElementId == "SPDXRef-DOCUMENT" or
        ($package_ids | index($relationship.spdxElementId)) != null) and
      ($package_ids | index($relationship.relatedSpdxElement)) != null
    )
  ) and
  (.annotations as $annotations |
    all($metadata[0].artifacts[];
      . as $artifact |
      any($annotations[];
        .comment | contains($artifact.path + " sha256:" + $artifact.sha256)
      )
    )
  )
' "$sbom" >/dev/null || fail "SPDX SBOM is malformed or differs from runtime metadata"

if rg -qi '(/opt/homebrew|/usr/local|/Users/|/home/|/tmp/)' "$sbom"; then
    fail "SPDX SBOM contains a machine-local path"
fi

while IFS= read -r package_name; do
    package_license="$artifact_root/Licenses/$package_name.txt"
    [[ -f "$package_license" && -s "$package_license" ]] || \
        fail "an SPDX package license notice is missing"
    [[ ! -L "$package_license" ]] || \
        fail "symbolic-link SPDX package licenses are forbidden"
done < <(jq -r '.packages[].name' "$sbom")

listed_artifacts="$(mktemp)"
discovered_artifacts="$(mktemp)"
trap 'rm -f "$listed_artifacts" "$discovered_artifacts"' EXIT
jq -r '.artifacts[].path' "$metadata" | LC_ALL=C sort > "$listed_artifacts"
find "$artifact_root/Runtime" -type l -name '*.dylib' -print -quit | grep -q . && \
    fail "symbolic-link runtime libraries are forbidden"
find "$artifact_root/Runtime" -type f -name '*.dylib' -print \
    | sed "s#^$artifact_root/##" \
    | LC_ALL=C sort > "$discovered_artifacts"
cmp -s "$listed_artifacts" "$discovered_artifacts" || fail "runtime library inventory differs from metadata"

while IFS=$'\t' read -r relative_path expected_digest license_path; do
    artifact="$artifact_root/$relative_path"
    license="$artifact_root/$license_path"
    [[ -f "$artifact" ]] || fail "a recorded runtime library is missing"
    [[ ! -L "$artifact" ]] || fail "symbolic-link runtime libraries are forbidden"
    [[ -f "$license" && -s "$license" ]] || fail "a recorded license notice is missing"
    [[ ! -L "$license" ]] || fail "symbolic-link license notices are forbidden"

    actual_digest="$(shasum -a 256 "$artifact" | awk '{print $1}')"
    [[ "$actual_digest" == "$expected_digest" ]] || fail "a runtime library digest does not match metadata"

    architectures="$(lipo -archs "$artifact" | tr ' ' '\n' | LC_ALL=C sort | xargs)"
    [[ "$architectures" == "arm64 x86_64" ]] || fail "a runtime library is not universal arm64/x86_64"

    expected_install_name="@rpath/$(basename "$relative_path")"
    install_names="$(otool -D "$artifact" | rg '^@' | LC_ALL=C sort -u)"
    [[ "$install_names" == "$expected_install_name" ]] || fail "a runtime library has an unexpected install name"

    while IFS= read -r dependency; do
        if [[ "$dependency" == *"architecture"* ]]; then
            continue
        fi
        dependency="${dependency#${dependency%%[![:space:]]*}}"
        dependency="${dependency%% *}"
        case "$dependency" in
            @rpath/*|/usr/lib/*|/System/Library/*) ;;
            *) fail "a runtime library has an unsafe dependency path" ;;
        esac
    done < <(otool -L "$artifact" | tail -n +2)
done < <(jq -r '.artifacts[] | [.path, .sha256, .license_path] | @tsv' "$metadata")

echo "native playback artifacts verified"
