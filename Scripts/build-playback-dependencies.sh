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
manifest="$(cd "$(dirname "$manifest")" && pwd -P)/$(basename "$manifest")"

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
        deployment_target: "26.5",
        architectures: ["arm64", "x86_64"],
        architecture_configuration: {
          arm64: "native-host",
          x86_64: "meson-cross-file"
        },
        build_order: [
          "boost", "openssl", "freetype", "fribidi", "harfbuzz", "libass",
          "libplacebo", "ffmpeg", "libbluray", "libtorrent", "mpv"
        ],
        embedded_components: ["libudfread"],
        build_only_components: ["jinja", "markupsafe", "vulkan-headers"],
        build_flags: {
          openssl: [
            "no-tests", "no-apps", "no-docs", "no-engine", "no-legacy",
            "no-module", "shared"
          ],
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
            "-Dintrospection=disabled", "-Ddocs=disabled", "-Dutilities=disabled",
            "-Dsubset=disabled", "-Draster=disabled", "-Dvector=disabled",
            "-Dgpu=disabled"
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
    local exit_code="$?"
    if [[ "${OMNIA_NATIVE_PRESERVE_WORK_DIRECTORY:-0}" == "1" ]]; then
        echo "native build diagnostics preserved at $work_directory" >&2
        return "$exit_code"
    fi
    case "$work_directory" in
        /tmp/omnia-native-build.*) rm -rf "$work_directory" ;;
    esac
    return "$exit_code"
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

for command_name in meson ninja cmake make clang lipo otool install_name_tool file; do
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "error: required native compilation tool is unavailable: $command_name" >&2
        exit 69
    }
done

deployment_target="26.5"
build_jobs="${OMNIA_NATIVE_BUILD_JOBS:-8}"
[[ "$build_jobs" =~ ^[1-9][0-9]*$ ]] || {
    echo "error: OMNIA_NATIVE_BUILD_JOBS must be a positive integer" >&2
    exit 64
}

source_root() {
    local component="$1"
    local component_directory="$work_directory/Sources/$component"
    local root_count
    local root

    root_count="$(find "$component_directory" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
    [[ "$root_count" == "1" ]] || {
        echo "error: source archive must have exactly one root directory: $component" >&2
        exit 65
    }
    root="$(find "$component_directory" -mindepth 1 -maxdepth 1 -type d -print -quit)"
    printf '%s\n' "$root"
}

build_log_failure() {
    local component="$1"
    local log="$2"
    echo "error: native compilation failed for $component" >&2
    tail -n 80 "$log" >&2 || true
    exit 1
}

configure_environment() {
    local architecture="$1"
    local prefix="$2"

    export CC=clang
    export CXX=clang++
    export CFLAGS="-arch $architecture -mmacosx-version-min=$deployment_target"
    export CXXFLAGS="-arch $architecture -mmacosx-version-min=$deployment_target"
    export CPPFLAGS="-I$prefix/include"
    export LDFLAGS="-arch $architecture -mmacosx-version-min=$deployment_target -L$prefix/lib"
    export PKG_CONFIG_PATH="$prefix/lib/pkgconfig:$prefix/share/pkgconfig"
    export PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig:$prefix/share/pkgconfig"
    export MACOSX_DEPLOYMENT_TARGET="$deployment_target"
    export SOURCE_DATE_EPOCH=0
    export ZERO_AR_DATE=1
}

meson_build() {
    local component="$1"
    local architecture="$2"
    local prefix="$3"
    local source="$4"
    shift 4
    local build="$work_directory/Build/$architecture/$component"
    local log="$work_directory/Logs/$architecture-$component.log"
    echo "building $component ($architecture)"
    if ! {
        if [[ "$architecture" == "x86_64" ]]; then
            meson setup "$build" "$source" \
                --prefix="$prefix" --libdir=lib --buildtype=release \
                --default-library=shared --wrap-mode=nofallback \
                --cross-file="$work_directory/Build/x86_64/meson-cross.ini" "$@"
        else
            meson setup "$build" "$source" \
                --prefix="$prefix" --libdir=lib --buildtype=release \
                --default-library=shared --wrap-mode=nofallback "$@"
        fi &&
            meson compile -C "$build" -j "$build_jobs" &&
            meson install -C "$build"
    } > "$log" 2>&1; then
        build_log_failure "$component ($architecture)" "$log"
    fi
}

vendor_libplacebo_build_inputs() {
    local libplacebo_source
    libplacebo_source="$(source_root libplacebo)"
    rm -rf "$libplacebo_source/3rdparty/jinja" \
        "$libplacebo_source/3rdparty/markupsafe" \
        "$libplacebo_source/3rdparty/Vulkan-Headers"
    cp -R "$(source_root jinja)" "$libplacebo_source/3rdparty/jinja"
    cp -R "$(source_root markupsafe)" "$libplacebo_source/3rdparty/markupsafe"
    cp -R "$(source_root vulkan-headers)" "$libplacebo_source/3rdparty/Vulkan-Headers"
}

build_architecture() {
    local architecture="$1"
    local prefix="$work_directory/Prefixes/$architecture"
    local build_root="$work_directory/Build/$architecture"
    local log_root="$work_directory/Logs"
    local openssl_source="$build_root/openssl-source"
    local ffmpeg_build="$build_root/ffmpeg"
    local libtorrent_build="$build_root/libtorrent"
    local openssl_target

    mkdir -p "$prefix/include" "$prefix/lib" "$build_root" "$log_root"
    configure_environment "$architecture" "$prefix"

    if [[ "$architecture" == "x86_64" ]]; then
        jq -nr --arg target "$deployment_target" '
          "[binaries]\n" +
          "c = \u0027clang\u0027\n" +
          "cpp = \u0027clang++\u0027\n" +
          "objc = \u0027clang\u0027\n" +
          "objcpp = \u0027clang++\u0027\n" +
          "ar = \u0027ar\u0027\n" +
          "strip = \u0027strip\u0027\n" +
          "pkg-config = \u0027pkg-config\u0027\n\n" +
          "[built-in options]\n" +
          "c_args = [\u0027-arch\u0027, \u0027x86_64\u0027, \u0027-mmacosx-version-min=" + $target + "\u0027]\n" +
          "cpp_args = [\u0027-arch\u0027, \u0027x86_64\u0027, \u0027-mmacosx-version-min=" + $target + "\u0027]\n" +
          "objc_args = [\u0027-arch\u0027, \u0027x86_64\u0027, \u0027-mmacosx-version-min=" + $target + "\u0027]\n" +
          "objcpp_args = [\u0027-arch\u0027, \u0027x86_64\u0027, \u0027-mmacosx-version-min=" + $target + "\u0027]\n" +
          "c_link_args = [\u0027-arch\u0027, \u0027x86_64\u0027, \u0027-mmacosx-version-min=" + $target + "\u0027]\n" +
          "cpp_link_args = [\u0027-arch\u0027, \u0027x86_64\u0027, \u0027-mmacosx-version-min=" + $target + "\u0027]\n\n" +
          "objc_link_args = [\u0027-arch\u0027, \u0027x86_64\u0027, \u0027-mmacosx-version-min=" + $target + "\u0027]\n" +
          "objcpp_link_args = [\u0027-arch\u0027, \u0027x86_64\u0027, \u0027-mmacosx-version-min=" + $target + "\u0027]\n\n" +
          "[host_machine]\n" +
          "system = \u0027darwin\u0027\n" +
          "cpu_family = \u0027x86_64\u0027\n" +
          "cpu = \u0027x86_64\u0027\n" +
          "endian = \u0027little\u0027\n\n" +
          "[properties]\nneeds_exe_wrapper = true\n"
        ' > "$build_root/meson-cross.ini"
    fi

    cp -R "$(source_root boost)/boost" "$prefix/include/boost"

    echo "building openssl ($architecture)"
    cp -R "$(source_root openssl)" "$openssl_source"
    if [[ "$architecture" == "arm64" ]]; then
        openssl_target="darwin64-arm64-cc"
    else
        openssl_target="darwin64-x86_64-cc"
    fi
    if ! {
        cd "$openssl_source"
        ./Configure "$openssl_target" --prefix="$prefix" --libdir=lib \
            no-tests no-apps no-docs no-engine no-legacy no-module shared &&
            make -s -j "$build_jobs" &&
            make -s install_sw
    } > "$log_root/$architecture-openssl.log" 2>&1; then
        build_log_failure "openssl ($architecture)" "$log_root/$architecture-openssl.log"
    fi

    meson_build freetype "$architecture" "$prefix" "$(source_root freetype)" \
        -Dharfbuzz=disabled -Dbrotli=disabled -Dbzip2=disabled \
        -Dpng=disabled -Dzlib=system -Dtests=disabled
    meson_build fribidi "$architecture" "$prefix" "$(source_root fribidi)" \
        -Ddeprecated=false -Ddocs=false -Dbin=false -Dtests=false
    meson_build harfbuzz "$architecture" "$prefix" "$(source_root harfbuzz)" \
        -Dglib=disabled -Dgobject=disabled -Dcairo=disabled -Dchafa=disabled \
        -Dpng=disabled -Dzlib=disabled -Dicu=disabled -Dgraphite=disabled \
        -Dgraphite2=disabled -Dfreetype=enabled -Dcoretext=disabled \
        -Dtests=disabled -Dintrospection=disabled -Ddocs=disabled \
        -Dutilities=disabled -Dsubset=disabled -Draster=disabled \
        -Dvector=disabled -Dgpu=disabled
    meson_build libass "$architecture" "$prefix" "$(source_root libass)" \
        -Dfontconfig=disabled -Ddirectwrite=disabled -Dcoretext=enabled \
        -Dtest=disabled -Dcompare=disabled -Dprofile=disabled \
        -Dfuzz=disabled -Dcheckasm=disabled
    meson_build libplacebo "$architecture" "$prefix" "$(source_root libplacebo)" \
        -Dvulkan=disabled -Dopengl=disabled -Dgl-proc-addr=disabled \
        -Dd3d11=disabled -Dglslang=disabled -Dshaderc=disabled \
        -Dlcms=disabled -Ddovi=disabled -Dlibdovi=disabled \
        -Ddemos=false -Dtests=false -Dbench=false -Dfuzz=false \
        -Dunwind=disabled -Dxxhash=disabled

    mkdir -p "$ffmpeg_build"
    echo "building ffmpeg ($architecture)"
    if ! {
        cd "$ffmpeg_build"
        "$(source_root ffmpeg)/configure" \
            --prefix="$prefix" --arch="$architecture" --cc=clang --cxx=clang++ \
            --disable-gpl --disable-nonfree --disable-programs --disable-doc \
            --disable-debug --disable-autodetect --disable-static --enable-shared \
            --enable-network --enable-securetransport --enable-videotoolbox \
            --enable-audiotoolbox --enable-zlib \
            --extra-cflags="$CFLAGS $CPPFLAGS" \
            --extra-cxxflags="$CXXFLAGS $CPPFLAGS" \
            --extra-ldflags="$LDFLAGS" &&
            make -s -j "$build_jobs" &&
            make -s install
    } > "$log_root/$architecture-ffmpeg.log" 2>&1; then
        build_log_failure "ffmpeg ($architecture)" "$log_root/$architecture-ffmpeg.log"
    fi

    meson_build libbluray "$architecture" "$prefix" "$(source_root libbluray)" \
        --force-fallback-for=libudfread -Denable_docs=false -Denable_tools=false \
        -Denable_devtools=false -Denable_examples=false -Dbdj_jar=disabled \
        -Dfreetype=disabled -Dfontconfig=disabled -Dlibxml2=disabled \
        -Dembed_udfread=true

    echo "building libtorrent ($architecture)"
    if ! {
        cmake -S "$(source_root libtorrent)" -B "$libtorrent_build" -G Ninja \
            -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix" \
            -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_OSX_ARCHITECTURES="$architecture" \
            -DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment_target" \
            -DCMAKE_PREFIX_PATH="$prefix" -DOPENSSL_ROOT_DIR="$prefix" \
            -DBUILD_SHARED_LIBS=ON -Dbuild_tests=OFF -Dbuild_examples=OFF \
            -Dbuild_tools=OFF -Dpython-bindings=OFF -Ddeprecated-functions=OFF \
            -Dlogging=OFF -Di2p=OFF -Ddht=ON -Dencryption=ON \
            -DTORRENT_DISABLE_LOGGING=ON &&
            cmake --build "$libtorrent_build" --parallel "$build_jobs" &&
            cmake --install "$libtorrent_build"
    } > "$log_root/$architecture-libtorrent.log" 2>&1; then
        build_log_failure "libtorrent ($architecture)" "$log_root/$architecture-libtorrent.log"
    fi

    meson_build mpv "$architecture" "$prefix" "$(source_root mpv)" \
        -Dgpl=false -Dlibmpv=true -Dcplayer=false -Dbuild-date=false \
        -Dlua=disabled -Djavascript=disabled -Ddvdnav=disabled -Dcdda=disabled \
        -Ddvbin=disabled -Dcplugins=disabled -Dlibbluray=enabled \
        -Dlibarchive=disabled -Dlibavdevice=disabled -Duchardet=disabled \
        -Dcocoa=disabled -Dmacos-cocoa-cb=disabled \
        -Dmacos-media-player=disabled -Dmacos-touchbar=disabled \
        -Dswift-build=disabled -Dgl=enabled -Dgl-cocoa=disabled \
        -Dtests=false -Dfuzzers=false
}

copy_license() {
    local component="$1"
    local relative_path="$2"
    local source
    source="$(source_root "$component")/$relative_path"
    [[ -f "$source" && -s "$source" ]] || {
        echo "error: license file is missing for $component" >&2
        exit 65
    }
    cp "$source" "$output_directory/Licenses/$component.txt"
}

vendor_libplacebo_build_inputs
echo "building native playback dependencies for arm64 and x86_64"
build_architecture arm64
build_architecture x86_64

echo "merging and relocating universal runtime libraries"
mkdir -p "$output_directory/Runtime" "$output_directory/Licenses" \
    "$output_directory/Headers"

runtime_libraries=(
    libass.9.dylib libavcodec.62.dylib libavfilter.11.dylib
    libavformat.62.dylib libavutil.60.dylib libbluray.4.dylib
    libcrypto.3.dylib libfreetype.6.dylib libfribidi.0.dylib
    libharfbuzz.0.dylib libmpv.2.dylib libplacebo.360.dylib
    libssl.3.dylib libswresample.6.dylib libswscale.9.dylib
    libtorrent-rasterbar.2.0.dylib
)

for library in "${runtime_libraries[@]}"; do
    arm64_library="$work_directory/Prefixes/arm64/lib/$library"
    x86_64_library="$work_directory/Prefixes/x86_64/lib/$library"
    output_library="$output_directory/Runtime/$library"
    [[ -f "$arm64_library" && -f "$x86_64_library" ]] || {
        echo "error: expected runtime library is missing: $library" >&2
        exit 65
    }
    lipo -create "$arm64_library" "$x86_64_library" -output "$output_library"
    install_name_tool -id "@rpath/$library" "$output_library"
done

for output_library in "$output_directory"/Runtime/*.dylib; do
    while IFS= read -r dependency; do
        [[ -n "$dependency" ]] || continue
        install_name_tool -change "$dependency" \
            "@rpath/$(basename "$dependency")" "$output_library"
    done < <(otool -L "$output_library" | awk \
        -v build_root="$work_directory/Prefixes/" \
        '$1 ~ "^" build_root {print $1}' | LC_ALL=C sort -u)
done

copy_license mpv LICENSE.LGPL
copy_license ffmpeg COPYING.LGPLv2.1
copy_license libtorrent COPYING
copy_license boost LICENSE_1_0.txt
copy_license libbluray COPYING
copy_license libplacebo LICENSE
copy_license libass COPYING
copy_license freetype docs/FTL.TXT
copy_license fribidi COPYING
copy_license harfbuzz COPYING
copy_license openssl LICENSE.txt
copy_license jinja LICENSE.txt
copy_license markupsafe LICENSE.txt
copy_license vulkan-headers LICENSE.md
cp "$(source_root libbluray)/contrib/libudfread/COPYING" \
    "$output_directory/Licenses/libudfread.txt"

cp -R "$work_directory/Prefixes/arm64/include/." "$output_directory/Headers/"
cp "$manifest" "$output_directory/playback-dependencies.json"

artifact_rows="$work_directory/artifacts.jsonl"
: > "$artifact_rows"
for output_library in "$output_directory"/Runtime/*.dylib; do
    library="$(basename "$output_library")"
    case "$library" in
        libmpv.*) license_component=mpv ;;
        libav*) license_component=ffmpeg ;;
        libtorrent-*) license_component=libtorrent ;;
        libbluray.*) license_component=libbluray ;;
        libplacebo.*) license_component=libplacebo ;;
        libass.*) license_component=libass ;;
        libfreetype.*) license_component=freetype ;;
        libfribidi.*) license_component=fribidi ;;
        libharfbuzz.*) license_component=harfbuzz ;;
        libcrypto.*|libssl.*) license_component=openssl ;;
        *) echo "error: no license mapping for $library" >&2; exit 65 ;;
    esac
    digest="$(shasum -a 256 "$output_library" | awk '{print $1}')"
    jq -cn --arg path "Runtime/$library" --arg sha256 "$digest" \
        --arg license_path "Licenses/$license_component.txt" \
        '{path: $path, sha256: $sha256, license_path: $license_path}' \
        >> "$artifact_rows"
done

jq -s --slurpfile plan "$output_directory/build-plan.json" '
  {
    schema_version: 1,
    architectures: $plan[0].architectures,
    deployment_target: $plan[0].deployment_target,
    build_flags: $plan[0].build_flags,
    artifacts: .
  }
' "$artifact_rows" > "$output_directory/build-metadata.json"

"$script_directory/verify-playback-artifacts.sh" "$output_directory"
echo "native playback universal artifacts built and verified"
