#!/bin/bash
# iOS stage of build-playback-dependencies.sh (OMNIA_NATIVE_PLATFORM=ios).
# Sourced after the pinned sources are fetched, digest-checked and
# extracted, with the same variables and helpers (manifest, work_directory,
# output_directory, source_root, build_log_failure, copy_license).
#
# Builds the playback closure as static libraries for iPhone and iPad
# devices (arm64) and the simulator (arm64), merges each platform's
# libraries into one archive, and packages them as MPV.xcframework with the
# libmpv headers. Static linking keeps the app free of loose dylibs, which
# iOS apps can't ship. libtorrent, OpenSSL, Boost and libbluray stay
# Mac-only; FFmpeg uses SecureTransport for TLS.

ios_deployment_target="26.0"

# name sdk triple
ios_targets=(
    "iphoneos iphoneos arm64-apple-ios$ios_deployment_target"
    "iphonesimulator iphonesimulator arm64-apple-ios$ios_deployment_target-simulator"
)

ios_configure_environment() {
    local sdk_path="$1"
    local triple="$2"
    local prefix="$3"
    local flags="-target $triple -isysroot $sdk_path"
    export CC=clang
    export CXX=clang++
    export CFLAGS="$flags"
    export CXXFLAGS="$flags"
    export OBJCFLAGS="$flags"
    export CPPFLAGS="-I$prefix/include"
    export LDFLAGS="$flags -L$prefix/lib"
    export PKG_CONFIG_PATH="$prefix/lib/pkgconfig:$prefix/share/pkgconfig"
    export PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig:$prefix/share/pkgconfig"
    unset MACOSX_DEPLOYMENT_TARGET
    export SOURCE_DATE_EPOCH=0
    export ZERO_AR_DATE=1
}

ios_write_cross_file() {
    local file="$1"
    local sdk_path="$2"
    local triple="$3"
    local subsystem="$4"
    local args="['-target', '$triple', '-isysroot', '$sdk_path']"
    cat > "$file" <<INI
[binaries]
c = 'clang'
cpp = 'clang++'
objc = 'clang'
objcpp = 'clang++'
ar = 'ar'
strip = 'strip'
pkg-config = 'pkg-config'

[built-in options]
c_args = $args
cpp_args = $args
objc_args = $args
objcpp_args = $args
c_link_args = $args
cpp_link_args = $args
objc_link_args = $args
objcpp_link_args = $args

[host_machine]
system = 'darwin'
subsystem = '$subsystem'
kernel = 'xnu'
cpu_family = 'aarch64'
cpu = 'arm64'
endian = 'little'

[properties]
needs_exe_wrapper = true
INI
}

ios_meson_build() {
    local component="$1"
    local target="$2"
    local prefix="$3"
    local source="$4"
    shift 4
    local build="$work_directory/Build/$target/$component"
    local log="$work_directory/Logs/$target-$component.log"
    echo "building $component ($target)"
    if ! {
        meson setup "$build" "$source" \
            --prefix="$prefix" --libdir=lib --buildtype=release \
            --default-library=static --wrap-mode=nofallback \
            --cross-file="$work_directory/Build/$target/meson-cross.ini" "$@" &&
            meson compile -C "$build" -j "$build_jobs" &&
            meson install -C "$build"
    } > "$log" 2>&1; then
        build_log_failure "$component ($target)" "$log"
    fi
}

# MoltenVK's static library for iOS and the iOS Simulator, as its
# fetchDependencies would build it, with the same pinned externals as the
# Mac build.
ios_build_moltenvk() {
    local source external log
    source="$(source_root moltenvk)"
    external="$source/External"
    log="$work_directory/Logs/moltenvk-ios.log"
    mkdir -p "$external" "$work_directory/Logs"
    cp -R "$(source_root cereal)" "$external/cereal"
    cp -R "$(source_root moltenvk-vulkan-headers)" "$external/Vulkan-Headers"
    cp -R "$(source_root spirv-cross)" "$external/SPIRV-Cross"
    cp -R "$(source_root moltenvk-spirv-tools)" "$external/SPIRV-Tools"
    mkdir -p "$external/SPIRV-Tools/external"
    cp -R "$(source_root moltenvk-spirv-headers)" "$external/SPIRV-Tools/external/spirv-headers"
    unzip -o -q -d "$external/SPIRV-Tools" "$source/Templates/spirv-tools/build.zip"
    rm -rf "$external/SPIRV-Tools/__MACOSX"
    echo "building moltenvk (iOS and iOS Simulator)"
    if ! (
        cd "$source"
        # As fetchDependencies does: build each platform unpackaged, then
        # package both slices into one xcframework per library.
        for platform in "iOS" "iOS Simulator"; do
            SKIP_PACKAGING=Y xcodebuild -project ExternalDependencies.xcodeproj \
                -scheme ExternalDependencies-iOS -destination "generic/platform=$platform" \
                -configuration Release -derivedDataPath "External/build/Intermediates/$platform" \
                IPHONEOS_DEPLOYMENT_TARGET="$ios_deployment_target" build || exit 1
        done
        PROJECT_DIR="." CONFIGURATION=Release SKIP_PACKAGING="" \
            bash -c '. ./Scripts/create_ext_lib_xcframeworks.sh && . ./Scripts/package_ext_libs_finish.sh' || exit 1
        make ios && make iossim
    ) > "$log" 2>&1; then
        build_log_failure moltenvk "$log"
    fi
    moltenvk_xcframework="$(find "$source/Package/Release/MoltenVK/static" -name 'MoltenVK.xcframework' -print -quit)"
    [[ -n "$moltenvk_xcframework" ]] || {
        echo "error: MoltenVK produced no static iOS xcframework" >&2
        exit 65
    }
    moltenvk_headers="$source/Package/Release/MoltenVK/include"
}

ios_install_moltenvk() {
    local target="$1"
    local prefix="$2"
    local slice
    if [[ "$target" == "iphoneos" ]]; then
        slice="$(find "$moltenvk_xcframework" -maxdepth 1 -type d -name 'ios-arm64' -print -quit)"
    else
        slice="$(find "$moltenvk_xcframework" -maxdepth 1 -type d -name 'ios-*simulator' -print -quit)"
    fi
    [[ -n "$slice" && -f "$slice/libMoltenVK.a" ]] || {
        echo "error: MoltenVK has no $target slice" >&2
        exit 65
    }
    lipo -thin arm64 "$slice/libMoltenVK.a" -output "$prefix/lib/libMoltenVK.a" 2>/dev/null ||
        cp -f "$slice/libMoltenVK.a" "$prefix/lib/libMoltenVK.a"
    cp -R "$moltenvk_headers/." "$prefix/include/"
    mkdir -p "$prefix/lib/pkgconfig"
    cat > "$prefix/lib/pkgconfig/vulkan.pc" <<PC
prefix=$prefix
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: vulkan
Description: MoltenVK, linked statically as the Vulkan implementation
Version: $(jq -r '.components[] | select(.name == "moltenvk-vulkan-headers") | .version' "$manifest")
Libs: -L\${libdir} -lMoltenVK -lc++ -framework Metal -framework QuartzCore -framework IOSurface -framework UIKit -framework Foundation -framework CoreGraphics
Cflags: -I\${includedir}
PC
}

ios_build_shaderc() {
    local target="$1"
    local sdk_path="$2"
    local prefix="$3"
    local source="$work_directory/Build/$target/shaderc-source"
    local build="$work_directory/Build/$target/shaderc"
    local log="$work_directory/Logs/$target-shaderc.log"
    cp -R "$(source_root shaderc)" "$source"
    cp -R "$(source_root glslang)" "$source/third_party/glslang"
    cp -R "$(source_root spirv-tools)" "$source/third_party/spirv-tools"
    cp -R "$(source_root spirv-headers)" "$source/third_party/spirv-headers"
    echo "building shaderc ($target)"
    if ! {
        cmake -S "$source" -B "$build" -G Ninja \
            -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix" \
            -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_SYSTEM_NAME=iOS \
            -DCMAKE_OSX_SYSROOT="$sdk_path" -DCMAKE_OSX_ARCHITECTURES=arm64 \
            -DCMAKE_OSX_DEPLOYMENT_TARGET="$ios_deployment_target" \
            -DSHADERC_SKIP_TESTS=ON -DSHADERC_SKIP_EXAMPLES=ON \
            -DSHADERC_SKIP_EXECUTABLES=ON -DSHADERC_SKIP_COPYRIGHT_CHECK=ON \
            -DSPIRV_SKIP_EXECUTABLES=ON -DSPIRV_SKIP_TESTS=ON \
            -DENABLE_GLSLANG_BINARIES=OFF -DGLSLANG_TESTS=OFF \
            -DBUILD_SHARED_LIBS=OFF &&
            cmake --build "$build" --parallel "$build_jobs" &&
            cmake --install "$build"
    } > "$log" 2>&1; then
        build_log_failure "shaderc ($target)" "$log"
    fi
    mkdir -p "$prefix/lib/pkgconfig"
    cat > "$prefix/lib/pkgconfig/shaderc.pc" <<PC
prefix=$prefix
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: shaderc
Description: shaderc, linked statically with glslang and SPIRV-Tools
Version: $(jq -r '.components[] | select(.name == "shaderc") | .version' "$manifest")
Libs: -L\${libdir} -lshaderc_combined -lc++
Cflags: -I\${includedir}
PC
}

ios_build_target() {
    local target="$1"
    local sdk="$2"
    local triple="$3"
    local sdk_path prefix build_root log_root subsystem
    sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
    prefix="$work_directory/Prefixes/$target"
    build_root="$work_directory/Build/$target"
    log_root="$work_directory/Logs"
    if [[ "$target" == "iphoneos" ]]; then subsystem="ios"; else subsystem="ios-simulator"; fi

    mkdir -p "$prefix/include" "$prefix/lib/pkgconfig" "$build_root" "$log_root"
    ios_configure_environment "$sdk_path" "$triple" "$prefix"
    ios_write_cross_file "$build_root/meson-cross.ini" "$sdk_path" "$triple" "$subsystem"

    ios_meson_build freetype "$target" "$prefix" "$(source_root freetype)" \
        -Dharfbuzz=disabled -Dbrotli=disabled -Dbzip2=disabled \
        -Dpng=disabled -Dzlib=system -Dtests=disabled
    ios_meson_build fribidi "$target" "$prefix" "$(source_root fribidi)" \
        -Ddeprecated=false -Ddocs=false -Dbin=false -Dtests=false
    ios_meson_build harfbuzz "$target" "$prefix" "$(source_root harfbuzz)" \
        -Dglib=disabled -Dgobject=disabled -Dcairo=disabled -Dchafa=disabled \
        -Dpng=disabled -Dzlib=disabled -Dicu=disabled -Dgraphite=disabled \
        -Dgraphite2=disabled -Dfreetype=enabled -Dcoretext=disabled \
        -Dtests=disabled -Dintrospection=disabled -Ddocs=disabled \
        -Dutilities=disabled -Dsubset=disabled -Draster=disabled \
        -Dvector=disabled -Dgpu=disabled
    ios_meson_build libass "$target" "$prefix" "$(source_root libass)" \
        -Dfontconfig=disabled -Ddirectwrite=disabled -Dcoretext=enabled \
        -Dtest=disabled -Dcompare=disabled -Dprofile=disabled \
        -Dfuzz=disabled -Dcheckasm=disabled -Dasm=disabled
    ios_install_moltenvk "$target" "$prefix"
    ios_build_shaderc "$target" "$sdk_path" "$prefix"
    ios_meson_build libplacebo "$target" "$prefix" "$(source_root libplacebo)" \
        -Dvulkan=enabled -Dvk-proc-addr=enabled -Dopengl=disabled \
        -Dgl-proc-addr=disabled -Dd3d11=disabled -Dglslang=disabled -Dshaderc=enabled \
        -Dlcms=disabled -Ddovi=disabled -Dlibdovi=disabled \
        -Ddemos=false -Dtests=false -Dbench=false -Dfuzz=false \
        -Dunwind=disabled -Dxxhash=disabled

    mkdir -p "$build_root/ffmpeg"
    echo "building ffmpeg ($target)"
    if ! (
        cd "$build_root/ffmpeg"
        "$(source_root ffmpeg)/configure" \
            --prefix="$prefix" --enable-cross-compile --target-os=darwin \
            --arch=arm64 --sysroot="$sdk_path" --cc=clang --cxx=clang++ \
            --disable-gpl --disable-nonfree --disable-programs --disable-doc \
            --disable-debug --disable-autodetect --enable-static --disable-shared \
            --enable-network --enable-securetransport --enable-videotoolbox \
            --enable-audiotoolbox --enable-zlib --enable-pic \
            --extra-cflags="$CFLAGS $CPPFLAGS" \
            --extra-cxxflags="$CXXFLAGS $CPPFLAGS" \
            --extra-ldflags="$LDFLAGS" &&
            make -s -j "$build_jobs" &&
            make -s install
    ) > "$log_root/$target-ffmpeg.log" 2>&1; then
        build_log_failure "ffmpeg ($target)" "$log_root/$target-ffmpeg.log"
    fi

    ios_meson_build mpv "$target" "$prefix" "$(source_root mpv)" \
        -Dgpl=false -Dlibmpv=true -Dcplayer=false -Dbuild-date=false \
        -Dlua=disabled -Djavascript=disabled -Ddvdnav=disabled -Dcdda=disabled \
        -Ddvbin=disabled -Dcplugins=disabled -Dlibbluray=disabled \
        -Dlibarchive=disabled -Dlibavdevice=disabled -Duchardet=disabled \
        -Dcocoa=disabled -Dmacos-cocoa-cb=disabled \
        -Dmacos-media-player=disabled -Dmacos-touchbar=disabled \
        -Dswift-build=disabled -Dgl=disabled -Dgl-cocoa=disabled \
        -Dios-gl=disabled -Dcoreaudio=disabled -Daudiounit=enabled \
        -Dvulkan=enabled -Dmoltenvk=enabled \
        -Dtests=false -Dfuzzers=false

    # One archive per platform, so the app links a single library.
    echo "merging static libraries ($target)"
    local archives=()
    local archive
    for archive in libmpv.a libplacebo.a libshaderc_combined.a libMoltenVK.a \
        libass.a libharfbuzz.a libfribidi.a libfreetype.a \
        libavformat.a libavcodec.a libavfilter.a libswresample.a libswscale.a libavutil.a; do
        [[ -f "$prefix/lib/$archive" ]] || {
            echo "error: expected static library is missing for $target: $archive" >&2
            exit 65
        }
        archives+=("$prefix/lib/$archive")
    done
    mkdir -p "$work_directory/Merged/$target"
    libtool -static -no_warning_for_no_symbols \
        -o "$work_directory/Merged/$target/libmpv-omnia.a" "${archives[@]}"
}

build_ios_playback() {
    vendor_libplacebo_build_inputs
    apply_source_patches
    ios_build_moltenvk
    local entry name sdk triple
    for entry in "${ios_targets[@]}"; do
        read -r name sdk triple <<< "$entry"
        ios_build_target "$name" "$sdk" "$triple"
    done

    echo "packaging MPV.xcframework"
    mkdir -p "$work_directory/Headers" "$output_directory/Licenses"
    cp -R "$work_directory/Prefixes/iphoneos/include/mpv" "$work_directory/Headers/mpv"
    xcodebuild -create-xcframework \
        -library "$work_directory/Merged/iphoneos/libmpv-omnia.a" -headers "$work_directory/Headers" \
        -library "$work_directory/Merged/iphonesimulator/libmpv-omnia.a" -headers "$work_directory/Headers" \
        -output "$output_directory/MPV.xcframework" > "$work_directory/Logs/xcframework.log" 2>&1 ||
        build_log_failure xcframework "$work_directory/Logs/xcframework.log"

    copy_license mpv LICENSE.LGPL
    copy_license ffmpeg COPYING.LGPLv2.1
    copy_license libplacebo LICENSE
    copy_license libass COPYING
    copy_license freetype docs/FTL.TXT
    copy_license fribidi COPYING
    copy_license harfbuzz COPYING
    copy_license jinja LICENSE.txt
    copy_license markupsafe LICENSE.txt
    copy_license vulkan-headers LICENSE.md
    copy_license moltenvk LICENSE
    copy_license spirv-cross LICENSE
    copy_license cereal LICENSE
    copy_license moltenvk-vulkan-headers LICENSE.md
    copy_license moltenvk-spirv-tools LICENSE
    copy_license moltenvk-spirv-headers LICENSE
    copy_license shaderc LICENSE
    copy_license glslang LICENSE.txt
    copy_license spirv-tools LICENSE
    copy_license spirv-headers LICENSE
    cp "$manifest" "$output_directory/playback-dependencies.json"

    local rows="$work_directory/ios-artifacts.jsonl"
    : > "$rows"
    local library
    while IFS= read -r library; do
        jq -cn --arg path "${library#"$output_directory/"}" \
            --arg sha256 "$(shasum -a 256 "$library" | awk '{print $1}')" \
            '{path: $path, sha256: $sha256}' >> "$rows"
    done < <(find "$output_directory/MPV.xcframework" -name '*.a' | LC_ALL=C sort)
    jq -s --arg target "$ios_deployment_target" '
      {schema_version: 1, platform: "ios", deployment_target: $target,
       slices: ["ios-arm64", "ios-arm64-simulator"], artifacts: .}
    ' "$rows" > "$output_directory/build-metadata.json"
    echo "native playback iOS artifacts built"
}
