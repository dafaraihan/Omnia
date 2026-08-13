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
