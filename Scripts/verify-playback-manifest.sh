#!/bin/bash
set -euo pipefail

usage() {
    echo "usage: $0 [--allow-pending-review] <manifest.json>" >&2
    exit 64
}

allow_pending=false
if [[ "${1:-}" == "--allow-pending-review" ]]; then
    allow_pending=true
    shift
fi

[[ $# -eq 1 ]] || usage
manifest="$1"

command -v jq >/dev/null 2>&1 || {
    echo "error: jq is required to verify native dependency provenance" >&2
    exit 69
}

[[ -f "$manifest" ]] || {
    echo "error: playback dependency manifest was not found" >&2
    exit 66
}

jq -e '
  .schema_version == 1 and
  (.closure_complete | type == "boolean") and
  (.review | type == "object") and
  (.review.status | type == "string" and length > 0) and
  (.components | type == "array" and length >= 5) and
  (all(.components[];
    (.name | type == "string" and test("^[a-z0-9][a-z0-9+._-]*$")) and
    (.version | type == "string" and test("^[0-9]+(\\.[0-9]+)+([-.][A-Za-z0-9.]+)?$")) and
    (.top_level | type == "boolean") and
    (.source_url | type == "string" and test("^https://[^/@]+(/|$)")) and
    (.sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
    (.license | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9.+-]*$")) and
    (.license_url | type == "string" and test("^https://[^/@]+(/|$)")) and
    (.build_system | type == "string" and length > 0) and
    (.verification.status | type == "string" and length > 0) and
    (.verification.publisher_evidence | type == "string" and length > 0)
  )) and
  ((.components | map(.name) | unique | length) == (.components | length)) and
  ([.components[] | select(.top_level) | {key: .name, value: .version}] | from_entries) == {
    "mpv": "0.41.0",
    "ffmpeg": "8.1.2",
    "libtorrent": "2.0.10",
    "boost": "1.90.0",
    "libbluray": "1.5.0"
  }
' "$manifest" >/dev/null || {
    echo "error: playback dependency manifest is incomplete or malformed" >&2
    exit 65
}

if [[ "$allow_pending" == false ]]; then
    jq -e '
      .closure_complete == true and
      .review.status == "approved" and
      (.review.second_reviewer | type == "string" and length > 0) and
      (.review.reviewed_at | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")) and
      all(.components[]; .verification.status == "approved")
    ' "$manifest" >/dev/null || {
        echo "error: native playback inputs are not approved for distribution" >&2
        exit 65
    }
fi

echo "playback dependency manifest verified"
