#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
generator="$repo_root/Scripts/generate-playback-sbom.sh"
manifest="$repo_root/NativeDependencies/playback-dependencies.json"
fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT

metadata="$fixture_root/build-metadata.json"
jq -n '{
  schema_version: 1,
  architectures: ["arm64", "x86_64"],
  artifacts: [{
    path: "Runtime/libmpv.2.dylib",
    sha256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    license_path: "Licenses/mpv.txt"
  }]
}' > "$metadata"

output="$fixture_root/native-playback.spdx.json"
"$generator" "$manifest" "$metadata" "$output"

jq -e --argjson expected_count "$(jq '.components | length' "$manifest")" '
  .spdxVersion == "SPDX-2.3" and
  .dataLicense == "CC0-1.0" and
  .SPDXID == "SPDXRef-DOCUMENT" and
  (.documentNamespace | test("^https://omnia.invalid/spdx/native-playback/sha256-")) and
  (.packages | length == $expected_count) and
  (all(.packages[];
    (.SPDXID | test("^SPDXRef-Package-")) and
    .downloadLocation != "NOASSERTION" and
    .licenseDeclared != "NOASSERTION" and
    (.checksums | any(.algorithm == "SHA256")) and
    .filesAnalyzed == false
  )) and
  ([.packages[].name] | index("mpv") != null) and
  ([.packages[].name] | index("libtorrent") != null) and
  ([.relationships[] |
    select(.spdxElementId == "SPDXRef-Package-libass" and
      .relationshipType == "DEPENDS_ON" and
      .relatedSpdxElement == "SPDXRef-Package-harfbuzz")
  ] | length == 1) and
  ([.relationships[] |
    select(.spdxElementId == "SPDXRef-Package-jinja" and
      .relationshipType == "BUILD_DEPENDENCY_OF" and
      .relatedSpdxElement == "SPDXRef-Package-libplacebo")
  ] | length == 1) and
  (.annotations[0].comment | contains("Runtime/libmpv.2.dylib"))
' "$output" >/dev/null

if rg -q '/Users/|/home/|/tmp/' "$output"; then
    echo "SBOM contains a machine-local path" >&2
    exit 1
fi

bad_metadata="$fixture_root/bad-metadata.json"
jq '.artifacts[0].sha256 = "bad"' "$metadata" > "$bad_metadata"
if "$generator" "$manifest" "$bad_metadata" "$fixture_root/bad.spdx.json" \
    > "$fixture_root/stdout.log" 2> "$fixture_root/stderr.log"; then
    echo "expected malformed artifact metadata to fail" >&2
    exit 1
fi
