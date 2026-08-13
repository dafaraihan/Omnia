#!/bin/bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "usage: $0 <manifest.json> <build-metadata.json> <output.spdx.json>" >&2
    exit 64
fi

manifest="$1"
build_metadata="$2"
output="$3"
script_directory="$(cd "$(dirname "$0")" && pwd)"

for command_name in jq shasum awk; do
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "error: required SBOM tool is unavailable: $command_name" >&2
        exit 69
    }
done

"$script_directory/verify-playback-manifest.sh" \
    --allow-pending-review "$manifest" >/dev/null

jq -e '
  .schema_version == 1 and
  .architectures == ["arm64", "x86_64"] and
  (.artifacts | type == "array" and length > 0) and
  all(.artifacts[];
    (.path | type == "string" and test("^Runtime/[A-Za-z0-9][A-Za-z0-9+._-]*\\.dylib$")) and
    (.sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
    (.license_path | type == "string" and test("^Licenses/[A-Za-z0-9][A-Za-z0-9+._-]*$"))
  )
' "$build_metadata" >/dev/null || {
    echo "error: native artifact metadata is malformed" >&2
    exit 65
}

created_at="${OMNIA_SBOM_CREATED_AT:-1970-01-01T00:00:00Z}"
[[ "$created_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || {
    echo "error: OMNIA_SBOM_CREATED_AT must be an SPDX UTC timestamp" >&2
    exit 64
}

manifest_digest="$(shasum -a 256 "$manifest" | awk '{print $1}')"
mkdir -p "$(dirname "$output")"

jq --arg namespace_digest "$manifest_digest" \
    --arg created_at "$created_at" \
    --slurpfile metadata "$build_metadata" '
  def spdx_id($name):
    "SPDXRef-Package-" + ($name | gsub("[^A-Za-z0-9.-]"; "-"));
  def relationship($from; $type; $to):
    {
      spdxElementId: spdx_id($from),
      relationshipType: $type,
      relatedSpdxElement: spdx_id($to)
    };
  {
    spdxVersion: "SPDX-2.3",
    dataLicense: "CC0-1.0",
    SPDXID: "SPDXRef-DOCUMENT",
    name: "Omnia native playback dependency closure",
    documentNamespace: (
      "https://omnia.invalid/spdx/native-playback/sha256-" + $namespace_digest
    ),
    creationInfo: {
      created: $created_at,
      creators: ["Tool: Omnia native playback SBOM generator"]
    },
    packages: [
      .components[] |
      {
        name,
        SPDXID: spdx_id(.name),
        versionInfo: .version,
        downloadLocation: .source_url,
        filesAnalyzed: false,
        licenseConcluded: .license,
        licenseDeclared: .license,
        copyrightText: "NOASSERTION",
        primaryPackagePurpose: "LIBRARY",
        checksums: [{algorithm: "SHA256", checksumValue: .sha256}],
        homepage: .license_url,
        supplier: "NOASSERTION"
      }
    ],
    relationships: (
      ([.components[] | select(.top_level) | {
        spdxElementId: "SPDXRef-DOCUMENT",
        relationshipType: "DESCRIBES",
        relatedSpdxElement: spdx_id(.name)
      }]) +
      [
        relationship("mpv"; "DEPENDS_ON"; "ffmpeg"),
        relationship("mpv"; "DEPENDS_ON"; "libass"),
        relationship("mpv"; "DEPENDS_ON"; "libplacebo"),
        relationship("mpv"; "DEPENDS_ON"; "libbluray"),
        relationship("libass"; "DEPENDS_ON"; "freetype"),
        relationship("libass"; "DEPENDS_ON"; "fribidi"),
        relationship("libass"; "DEPENDS_ON"; "harfbuzz"),
        relationship("harfbuzz"; "DEPENDS_ON"; "freetype"),
        relationship("libtorrent"; "DEPENDS_ON"; "boost"),
        relationship("libtorrent"; "DEPENDS_ON"; "openssl"),
        relationship("libbluray"; "CONTAINS"; "libudfread"),
        relationship("jinja"; "BUILD_DEPENDENCY_OF"; "libplacebo"),
        relationship("markupsafe"; "BUILD_DEPENDENCY_OF"; "libplacebo"),
        relationship("vulkan-headers"; "BUILD_DEPENDENCY_OF"; "libplacebo")
      ]
    ),
    annotations: [{
      annotationDate: $created_at,
      annotationType: "OTHER",
      annotator: "Tool: Omnia native playback SBOM generator",
      comment: (
        "Verified runtime artifacts: " +
        ($metadata[0].artifacts | map(.path + " sha256:" + .sha256) | join(", "))
      )
    }]
  }
' "$manifest" > "$output"

echo "native playback SPDX SBOM generated"
