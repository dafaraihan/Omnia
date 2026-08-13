#!/bin/bash
set -euo pipefail

usage() {
    echo "usage: $0 <manifest.json> <output-directory>" >&2
    exit 64
}

[[ $# -eq 2 ]] || usage
manifest="$1"
output_directory="$2"
build_mode="${OMNIA_NATIVE_BUILD_MODE:-build}"

case "$build_mode" in
    build|fetch-only|plan-only) ;;
    *)
        echo "error: unsupported native playback build mode" >&2
        exit 64
        ;;
esac

script_directory="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_directory/.." && pwd)"

for command_name in curl jq shasum tar awk mktemp cp; do
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "error: required native build tool is unavailable: $command_name" >&2
        exit 69
    }
done

/bin/bash "$script_directory/verify-playback-manifest.sh" \
    --allow-pending-review "$manifest" >/dev/null

if [[ -e "$output_directory" ]]; then
    [[ -d "$output_directory" ]] || {
        echo "error: native build output must be a directory" >&2
        exit 73
    }
    if find "$output_directory" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
        echo "error: native build output directory must be empty" >&2
        exit 73
    fi
else
    mkdir -p "$output_directory"
fi

output_directory="$(cd "$output_directory" && pwd -P)"
case "$output_directory" in
    /|"$repo_root"|"$repo_root"/*)
        echo "error: native artifacts must be staged outside the repository" >&2
        exit 73
        ;;
esac

source_cache="${OMNIA_NATIVE_SOURCE_CACHE:-}"
if [[ -n "$source_cache" ]]; then
    [[ -d "$source_cache" && ! -L "$source_cache" ]] || {
        echo "error: native source cache must be a directory" >&2
        exit 73
    }
    source_cache="$(cd "$source_cache" && pwd -P)"
    case "$source_cache" in
        /|"$repo_root"|"$repo_root"/*)
            echo "error: native source cache must be outside the repository" >&2
            exit 73
            ;;
    esac
fi

write_build_plan() {
    jq -n '
      {
        schema_version: 1,
        architectures: ["arm64", "x86_64"],
        build_order: [
          "boost", "openssl", "freetype", "fribidi", "harfbuzz", "libass",
          "libplacebo", "ffmpeg", "libbluray", "libtorrent", "mpv"
        ],
        embedded_components: ["libudfread"],
        build_only_components: ["jinja", "markupsafe", "vulkan-headers"],
        build_flags: {
          openssl: ["no-tests", "no-apps", "no-docs", "shared"],
          freetype: [
            "-Dharfbuzz=disabled", "-Dbrotli=disabled", "-Dbzip2=disabled",
            "-Dpng=disabled", "-Dzlib=system", "-Dtests=disabled"
          ],
          fribidi: ["-Ddeprecated=false", "-Ddocs=false", "-Dbin=false", "-Dtests=false"],
          harfbuzz: [
            "-Dglib=disabled", "-Dgobject=disabled", "-Dcairo=disabled",
            "-Dchafa=disabled", "-Dpng=disabled", "-Dzlib=disabled",
            "-Dicu=disabled", "-Dgraphite=disabled", "-Dgraphite2=disabled",
            "-Dfreetype=enabled", "-Dcoretext=disabled", "-Dtests=disabled",
            "-Dintrospection=disabled", "-Ddocs=disabled", "-Dutilities=disabled"
          ],
          libass: [
            "-Dfontconfig=disabled", "-Ddirectwrite=disabled", "-Dcoretext=enabled",
            "-Dtest=disabled", "-Dcompare=disabled", "-Dprofile=disabled",
            "-Dfuzz=disabled", "-Dcheckasm=disabled"
          ],
          libplacebo: [
            "-Dvulkan=disabled", "-Dopengl=disabled", "-Dgl-proc-addr=disabled",
            "-Dd3d11=disabled", "-Dglslang=disabled", "-Dshaderc=disabled",
            "-Dlcms=disabled", "-Ddovi=disabled", "-Dlibdovi=disabled",
            "-Ddemos=false", "-Dtests=false", "-Dbench=false", "-Dfuzz=false",
            "-Dunwind=disabled", "-Dxxhash=disabled"
          ],
          ffmpeg: [
            "--disable-gpl", "--disable-nonfree", "--disable-programs",
            "--disable-doc", "--disable-debug", "--disable-autodetect",
            "--disable-static", "--enable-shared", "--enable-network",
            "--enable-securetransport", "--enable-videotoolbox",
            "--enable-audiotoolbox", "--enable-zlib"
          ],
          libbluray: [
            "--force-fallback-for=libudfread",
            "-Denable_docs=false", "-Denable_tools=false", "-Denable_devtools=false",
            "-Denable_examples=false", "-Dbdj_jar=disabled", "-Dfreetype=disabled",
            "-Dfontconfig=disabled", "-Dlibxml2=disabled", "-Dembed_udfread=true"
          ],
          libtorrent: [
            "BUILD_SHARED_LIBS=ON", "build_tests=OFF", "build_examples=OFF",
            "build_tools=OFF", "python-bindings=OFF", "deprecated-functions=OFF",
            "logging=OFF", "i2p=OFF", "dht=ON", "encryption=ON",
            "TORRENT_DISABLE_LOGGING=ON"
          ],
          mpv: [
            "-Dgpl=false", "-Dlibmpv=true", "-Dcplayer=false", "-Dbuild-date=false",
            "-Dlua=disabled", "-Djavascript=disabled", "-Ddvdnav=disabled",
            "-Dcdda=disabled", "-Ddvbin=disabled", "-Dcplugins=disabled",
            "-Dlibbluray=enabled", "-Dlibarchive=disabled", "-Dlibavdevice=disabled",
            "-Duchardet=disabled", "-Dcocoa=disabled", "-Dmacos-cocoa-cb=disabled",
            "-Dmacos-media-player=disabled", "-Dmacos-touchbar=disabled",
            "-Dswift-build=disabled", "-Dgl=enabled", "-Dgl-cocoa=disabled",
            "-Dtests=false", "-Dfuzzers=false"
          ]
        }
      }
    ' > "$output_directory/build-plan.json"
}

write_build_plan

if [[ "$build_mode" == "plan-only" ]]; then
    echo "native playback build plan generated"
    exit 0
fi

work_directory="$(mktemp -d /tmp/omnia-native-build.XXXXXX)"
cleanup() {
    case "$work_directory" in
        /tmp/omnia-native-build.*) rm -rf "$work_directory" ;;
    esac
}
trap cleanup EXIT

mkdir -p "$work_directory/Downloads" "$work_directory/Sources"

archive_is_confined() {
    local archive="$1"
    tar -tf "$archive" | awk -F/ '
      /^\// { invalid = 1 }
      {
        for (field_index = 1; field_index <= NF; field_index++) {
          if ($field_index == "..") invalid = 1
        }
      }
      END { exit invalid ? 1 : 0 }
    ' || return 1

    tar -tvf "$archive" | awk '
      substr($1, 1, 1) == "h" { invalid = 1 }
      substr($1, 1, 1) == "l" {
        separator = " -> "
        separator_index = index($0, separator)
        if (separator_index == 0) {
          invalid = 1
          next
        }
        target = substr($0, separator_index + length(separator))
        if (target ~ /^\//) invalid = 1
        target_count = split(target, target_parts, "/")
        for (target_index = 1; target_index <= target_count; target_index++) {
          if (target_parts[target_index] == "..") invalid = 1
        }
      }
      END { exit invalid ? 1 : 0 }
    ' || return 1
}

while IFS=$'\t' read -r name version source_url expected_digest; do
    archive="$work_directory/Downloads/$name.archive"
    source_directory="$work_directory/Sources/$name"
    mkdir -p "$source_directory"

    cached_archive="${source_cache:+$source_cache/$expected_digest}"
    if [[ -n "$cached_archive" && -f "$cached_archive" && ! -L "$cached_archive" ]]; then
        cp "$cached_archive" "$archive"
    else
        curl --fail --location --proto '=https' --tlsv1.2 \
            --connect-timeout 15 --max-time 300 \
            --speed-limit 1 --speed-time 30 \
            --retry 2 --retry-connrefused \
            "$source_url" --output "$archive"
    fi

    actual_digest="$(shasum -a 256 "$archive" | awk '{print $1}')"
    if [[ "$actual_digest" != "$expected_digest" ]]; then
        echo "error: source digest mismatch for $name" >&2
        exit 65
    fi

    if ! archive_is_confined "$archive"; then
        echo "error: source archive is not confined for $name" >&2
        exit 65
    fi

    tar -xf "$archive" -C "$source_directory"

    if [[ -z "$(find "$source_directory" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
        echo "error: source archive is empty for $name" >&2
        exit 65
    fi
done < <(jq -r '.components[] | [.name, .version, .source_url, .sha256] | @tsv' "$manifest")

jq '{
  schema_version: 1,
  components: [.components[] | {name, version, sha256}]
}' "$manifest" > "$output_directory/source-metadata.json"

if [[ "$build_mode" == "fetch-only" ]]; then
    echo "native playback sources fetched and verified"
    exit 0
fi

echo "error: native compilation is not available yet" >&2
exit 69
