# Native playback dependencies

This directory defines the native source inputs allowed for Omnia's macOS
playback work. It intentionally contains no prebuilt binaries.

`playback-dependencies.json` currently records a **provisional pinned closure**
for local macOS development, including build-only source inputs. It is not a
distribution approval: `closure_complete` remains false until independent
provenance, license, reproducibility, and vulnerability review is recorded.
The manifest verifier has two modes:

```sh
# Structural checks for local development; accepts explicitly pending review.
Scripts/verify-playback-manifest.sh --allow-pending-review \
  NativeDependencies/playback-dependencies.json

# Release gate; fails until the complete closure and independent reviews exist.
Scripts/verify-playback-manifest.sh \
  NativeDependencies/playback-dependencies.json
```

Before the release gate may pass, every bundled transitive library must be
listed with its exact source and digest, publisher signatures/checksums must be
validated where available, two clean builders must reproduce the artifacts,
and a named independent reviewer must approve provenance and license evidence.
Legal approval of the LGPL relinking/source-offer strategy is a separate human
gate. See the native dependency implementation plan and `SECURITY.md`.

The intended build profile keeps mpv in LGPL mode (`-Dgpl=false`) and FFmpeg
with both GPL and nonfree components disabled. GPL DVD libraries are excluded;
DVD inputs must remain visible but explicitly unsupported. libbluray covers
only unencrypted Blu-ray content and does not provide decryption keys.

## Local build workflow

The builder accepts only digest-matched HTTPS archives, rejects archives that
escape their extraction root, builds separate arm64 and x86_64 slices, merges
the required runtime closure, rewrites bundled dependencies to `@rpath`, and
verifies every output. Source and artifacts must remain outside the repository.

```sh
source_cache="$(mktemp -d /tmp/omnia-native-source-cache.XXXXXX)"
artifact_root="$(mktemp -d /tmp/omnia-native-artifacts.XXXXXX)"

# Optional: populate and reuse a digest-addressed source cache.
OMNIA_NATIVE_BUILD_MODE=fetch-only \
  OMNIA_NATIVE_SOURCE_CACHE="$source_cache" \
  Scripts/build-playback-dependencies.sh \
  NativeDependencies/playback-dependencies.json "$artifact_root"

# Use a new empty artifact directory for each mode/build.
artifact_root="$(mktemp -d /tmp/omnia-native-artifacts.XXXXXX)"
OMNIA_NATIVE_SOURCE_CACHE="$source_cache" \
  Scripts/build-playback-dependencies.sh \
  NativeDependencies/playback-dependencies.json "$artifact_root"
```

The output includes universal runtime dylibs, headers, exact license texts,
build/source metadata, the pinned manifest, and an SPDX 2.3 JSON SBOM. Release
staging additionally validates the manifest in strict mode, so locally built
artifacts cannot bypass pending independent or legal approval.

## Metal rendering (gpu-next on MoltenVK)

Added 2026-10-27 so libmpv's `gpu-next` output can draw into the player's own
Metal layer, as Nuvio's player does. Settings › Playback › Rendering › Metal
Rendering turns it on (off by default); the player falls back to OpenGL and
records why in Diagnostics when Metal can't start.

**Patch.** `patches/mpv/0001-player-add-moltenvk-context.patch` comes from
MPVKit (`Sources/BuildScripts/patch/libmpv/`, LGPL-3.0; the file it adds
carries mpv's LGPL-2.1-or-later header). It adds a `moltenvk` Vulkan context
that draws into a `CAMetalLayer` passed as `--wid`. It applies unchanged to the
pinned mpv 0.41.0 source. `.gitattributes` keeps its bytes out of whitespace
checks. `patches/mpv/0002-moltenvk-follow-layer-size.patch` is Omnia's own
change on top of it (same licence as the file it changes): the context
follows the layer's drawable size on every event check, so the picture and
subtitles keep filling it after a resize such as entering full screen.

**New pinned components** (all `pending-independent-review` in the manifest):

| Component | Pin | Licence | Role |
| --- | --- | --- | --- |
| moltenvk | v1.4.2 | Apache-2.0 | Vulkan on Metal; ships as `libMoltenVK.dylib` |
| spirv-cross | MoltenVK's pin | Apache-2.0 | Compiled into MoltenVK |
| cereal | MoltenVK's pin (1.3.2) | BSD-3-Clause | Compiled into MoltenVK |
| moltenvk-vulkan-headers | MoltenVK's pin (1.4.357) | Apache-2.0 | Build-only headers |
| moltenvk-spirv-tools / -headers | MoltenVK's pins | Apache-2.0 / MIT | MoltenVK build inputs |
| shaderc | v2026.4 | Apache-2.0 | libplacebo's GLSL compiler, static |
| glslang | shaderc's pin (16.6.0+) | BSD-3-Clause, MIT, Apache-2.0 and GPL-3.0-or-later with the Bison exception for generated files | Inside shaderc |
| spirv-tools / spirv-headers | shaderc's pins | Apache-2.0 / MIT | Inside shaderc |

glslang's GPL-3.0-or-later part is compatible with Omnia's GPL-3.0 licence, but
the release review must record it because the rest of the closure is kept
LGPL. Revisions come from MoltenVK's `ExternalRevisions/` and shaderc's `DEPS`
at the pinned tags; each archive digest was reproduced locally.

**Build notes.**

- Release (`Scripts/build-playback-dependencies.sh`): applies the patch with
  `patch -p1`, lays MoltenVK's pinned externals out where its
  `fetchDependencies` would (using its bundled pre-generated SPIRV-Tools
  headers), and builds `ExternalDependencies.xcodeproj` then `make macos`.
  This gives one universal `libMoltenVK.dylib`, thinned per architecture.
  MoltenVK is linked directly as Vulkan through a generated `vulkan.pc`, as
  MPVKit does, so no Vulkan loader or driver manifest ships. shaderc is built
  static and linked into libplacebo from `libshaderc_combined.a`. libplacebo
  turns on `vulkan`, `vk-proc-addr` and `shaderc`; mpv turns on `vulkan` and
  `moltenvk`.
- Xcode's build database fails with "disk I/O error" outside the standard
  DerivedData folder in a sandboxed shell, so MoltenVK's derived data goes to
  `~/Library/Developer/Xcode/DerivedData/OmniaNativeMoltenVK`
  (`OMNIA_NATIVE_XCODE_DERIVED_DATA` overrides it).
- Debug (`Scripts/build-dev-libmpv.sh`): builds the pinned, patched mpv
  against Homebrew's libplacebo, shaderc, Vulkan loader and MoltenVK into
  `~/Library/Caches/Omnia/dev-libmpv`. `embed-libmpv.sh` prefers that build
  and bundles `libMoltenVK.dylib` with an ICD manifest for the loader. Without
  it, Debug builds use Homebrew's libmpv and the player stays on OpenGL.
- Reproducibility: not yet checked. No two-builder reproduction has been
  done for the new components, and whether MoltenVK's Xcode build is
  byte-for-byte reproducible is unknown.

## KSPlayer engine (Settings › Player › Advanced › Engine)

Added 2026-11-06 at Dafa's request as a second playback engine behind the
same player UI; mpv stays the default. It lives in the local package
`Packages/OmniaKSEngine`, which builds as `OmniaKSEngine.framework` and is
embedded in the app on iPhone, iPad and Mac. Unlike the closure above it comes
through Swift Package Manager, pinned in `Package.resolved`.

| Component | Pin | Licence | Role |
| --- | --- | --- | --- |
| KSPlayer (`kingslay/KSPlayer`, `GPLv3` branch) | revision `be7f60d3b94a0941c643fe8699113cfce4f08e83` | GPL-3.0 | Player, decoders' glue, PiP, subtitles |
| FFmpegKit (`kingslay/FFmpegKit`) | 6.1.4, revision `c32be9bfb628042737ad3ef622e930c5c7b15954` | GPL-3.0 (bundles FFmpeg 6.1, libass, libplacebo, MoltenVK, dav1d, gnutls, libsmbclient and others under their own licences) | Prebuilt static xcframeworks KSPlayer links |

**Why the GPLv3 branch.** KSPlayer's `main` branch ships its core only as a
prebuilt binary for macOS, the iOS Simulator and tvOS; full source for every
device is the paid LGPL edition. The `GPLv3` branch is the maintained
open-source edition with source for every platform. Only it is used; none of
the paid features are.

**Isolation.** FFmpegKit's FFmpeg 6.1 and Omnia's mpv FFmpeg 8 can't share one
binary: on iPhone and iPad both are static, so the linker would mix them. The
package links KSPlayer and FFmpegKit into its own framework, imports KSPlayer
`@_implementationOnly`, and exports only `_$s13OmniaKSEngine*` Swift symbols
(Xcode also applies the export list to the app link, which keeps `_$s5Omnia*`
and `___debug_*`). `Scripts/remove-static-framework-stubs.sh` deletes the
empty placeholder bundles Xcode copies for FFmpegKit's static frameworks. One
ObjC class (`MVKBlockObserver`, from MoltenVK) exists in both copies; each
image binds its own, and the runtime logs a warning.

**Supply chain.** FFmpegKit's binaries are committed to its Git repository
and built by its author; they have not been rebuilt or reproduced here. The
pins fix the exact commits. Building requires Xcode's Metal Toolchain
(`xcodebuild -downloadComponent MetalToolchain`) for KSPlayer's shaders.

**Release review still needed:** add KSPlayer's and FFmpegKit's licence texts
and FFmpegKit's bundled component notices to the release's licences zip,
record a vulnerability check of FFmpeg 6.1.x and the bundled libraries, and
measure the size change of a Release build.
