# Reproducible Native Playback Dependencies Implementation Plan

> **Automated-validation policy:** Follow the repository-root `AGENTS.md`. Instructions below that call for automated test targets, suites, fixtures, or scripts are historical and superseded; use builds, static checks, and focused manual evidence instead.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace distribution reliance on an arbitrary Homebrew libmpv closure with pinned, checksummed, license-reviewed universal macOS artifacts that also provide libtorrent for the local resolver.

**Architecture:** Keep Homebrew as an explicit Debug-only developer fallback. A repository-owned manifest and scripts fetch, verify, build, inspect, and stage a minimal native runtime under derived build output; Xcode embeds only the staged dylibs for Release. Verification rejects unexpected install names, architectures, GPL/nonfree build flags, missing notices, or unsigned nested code.

**Tech Stack:** POSIX shell, Meson/Ninja, CMake, Xcode/clang, mpv 0.41.0, FFmpeg 8.1.2, libtorrent 2.0.10, Boost 1.90.0, libbluray 1.5.0, SPDX 2.3 JSON, codesign, otool, lipo, XCTest/build smoke tests.

## Global Constraints

- Exact versions are mpv 0.41.0, FFmpeg 8.1.2, libtorrent 2.0.10, Boost 1.90.0, and libbluray 1.5.0 unless a new design review changes them.
- Every source archive requires an official HTTPS URL, a committed SHA-256 digest obtained from independently verified release material, a license expression, and provenance notes.
- mpv must build with `-Dgpl=false`; FFmpeg must build with `--disable-gpl --disable-nonfree`.
- Release artifacts support both `arm64` and `x86_64` and use only `@rpath` for bundled non-system libraries.
- LGPL replacement/relink rights, notices, source instructions, and legal review are release blockers.
- Libtorrent is BSD-3-Clause; required Boost components are Boost Software License 1.0.
- `libdvdread` and `libdvdnav` are GPL-2.0-or-later and are excluded from the approved LGPL release profile; this plan does not relicense Omnia.
- This plan does not authorize uploading artifacts, notarizing a release, changing live distribution, or accepting a license on the user's behalf.

---

### Task 1: Create a machine-readable provenance contract

**Files:**
- Create: `NativeDependencies/playback-dependencies.json`
- Create: `NativeDependencies/README.md`
- Create: `Scripts/verify-playback-manifest.sh`
[Historical automated-validation reference removed by repository policy.]

**Interfaces:**
- Consumes: dependency records with `name`, `version`, `source_url`, `sha256`, `license`, `license_url`, and `build_system`.
- Produces: a verifier that exits zero only for complete, HTTPS, pinned, 64-hex-digest records and the exact approved top-level versions.

- [ ] **Step 1: Write the failing shell contract test**

```bash
#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
verifier="$repo_root/Scripts/verify-playback-manifest.sh"
manifest="$repo_root/NativeDependencies/playback-dependencies.json"
"$verifier" "$manifest"
jq -e '.components | map(.name) | contains(["mpv", "ffmpeg", "libtorrent", "boost", "libbluray"])' "$manifest" >/dev/null
```

- [ ] **Step 2: Run the contract test and witness RED**

```bash
[Automated validation command removed by repository policy.]
```

Expected: failure because the manifest and verifier do not exist.

- [ ] **Step 3: Add the manifest schema and verifier**

Generate each record from the verified archive rather than typing a digest:

```bash
source_url='https://github.com/mpv-player/mpv/archive/refs/tags/v0.41.0.tar.gz'
archive_path="$audit_tmp/mpv-0.41.0.tar.gz"
curl --fail --location --proto '=https' --tlsv1.2 "$source_url" --output "$archive_path"
verified_sha256="$(shasum -a 256 "$archive_path" | awk '{print $1}')"
jq -n \
  --arg name mpv \
  --arg version 0.41.0 \
  --arg source_url "$source_url" \
  --arg sha256 "$verified_sha256" \
  --arg license LGPL-2.1-or-later \
  --arg license_url 'https://github.com/mpv-player/mpv/blob/v0.41.0/LICENSE.LGPL' \
  --arg build_system meson \
  '{name:$name,version:$version,source_url:$source_url,sha256:$sha256,license:$license,license_url:$license_url,build_system:$build_system}'
```

Verify publisher-provided signature/checksum material where available before accepting `verified_sha256`, and have a second reviewer reproduce it. Repeat with the official URLs for FFmpeg 8.1.2, libtorrent 2.0.10, Boost 1.90.0, libbluray 1.5.0, and every selected transitive non-system library before the verifier is allowed to pass.

The verifier uses `jq -e` to enforce required keys, exact top-level versions, HTTPS URLs, unique names, SPDX-like nonempty license expressions, and `^[0-9a-f]{64}$` digests.

- [ ] **Step 4: Run the verifier and witness GREEN**

```bash
[Automated validation command removed by repository policy.]
```

Expected: pass only after independently verified digests and the complete selected closure are recorded.

- [ ] **Step 5: Commit the provenance contract**

```bash
[Historical automated-validation reference removed by repository policy.]
git commit -m "Define native playback dependency provenance"
```

### Task 2: Build and inspect universal native artifacts

**Files:**
- Create: `Scripts/build-playback-dependencies.sh`
- Create: `Scripts/verify-playback-artifacts.sh`
[Historical automated-validation reference removed by repository policy.]
[Historical automated-validation reference removed by repository policy.]

**Interfaces:**
- Consumes: the verified manifest and an explicit output directory argument.
- Produces: staged headers/import libraries plus `Runtime/*.dylib`, license files, build logs, and `build-metadata.json` for `arm64` and `x86_64`.

- [ ] **Step 1: Write failure-fixture tests for artifact verification**

Create disposable fake artifacts and assert rejection for a missing architecture, `/opt/homebrew` install name, missing license, and metadata containing `--enable-gpl`:

```bash
expect_failure missing-architecture
expect_failure homebrew-install-name
expect_failure missing-license
expect_failure gpl-enabled-ffmpeg
```

[Historical automated-validation reference removed by repository policy.]

- [ ] **Step 2: Run the artifact tests and witness RED**

```bash
[Automated validation command removed by repository policy.]
```

Expected: failure because the build and verifier scripts do not exist.

- [ ] **Step 3: Implement deterministic fetch, build, merge, and inspection**

The build script accepts only:

```text
build-playback-dependencies.sh <manifest.json> <output-directory>
```

It creates its own `mktemp -d` working directory, downloads each exact `source_url`, verifies SHA-256 before extraction, rejects archive traversal, and builds each architecture separately with `MACOSX_DEPLOYMENT_TARGET=26.5` and Xcode clang.

Required media configuration includes:

```text
mpv:        -Dgpl=false -Dlibmpv=true -Dcplayer=false
FFmpeg:     --disable-gpl --disable-nonfree --enable-shared --disable-static
libtorrent: BUILD_SHARED_LIBS=ON, Python bindings OFF, tests OFF, examples OFF
```

Disable mpv Lua/JavaScript/downloader integration and any dependency not required by the existing libmpv renderer, embedded subtitles, HTTPS playback, unencrypted Blu-ray input, or torrent engine. Explicitly disable DVD support so GPL `libdvdread`/`libdvdnav` cannot enter the closure. Use `lipo -create` for matching dylibs, rewrite bundled IDs/references to `@rpath`, and record every configure command and source digest in `build-metadata.json`.

The verifier checks `lipo -archs`, `otool -L`, `otool -l`, metadata flags, runtime filenames, duplicate install names, licenses, and absence of absolute Homebrew/user paths.

- [ ] **Step 4: Run fixture tests, then build and verify real artifacts**

```bash
[Automated validation command removed by repository policy.]
native_output="$(mktemp -d)"
/bin/bash Scripts/build-playback-dependencies.sh NativeDependencies/playback-dependencies.json "$native_output"
/bin/bash Scripts/verify-playback-artifacts.sh "$native_output"
```

Expected: hostile fixtures are rejected; the real universal artifact passes. Keep the temporary output outside Git.

- [ ] **Step 5: Commit build tooling, not binaries**

```bash
[Historical automated-validation reference removed by repository policy.]
git commit -m "Build reproducible native playback artifacts"
```

### Task 3: Integrate staged artifacts into Xcode Release builds

**Files:**
- Modify: `Omnia.xcodeproj/project.pbxproj`
- Replace: `Omnia/Platform/Playback/embed-libmpv.sh`
- Create: `Omnia/Platform/Playback/stage-native-playback.sh`
[Historical automated-validation reference removed by repository policy.]

**Interfaces:**
- Consumes: `OMNIA_NATIVE_PLAYBACK_ROOT` pointing to verified staged artifacts.
- Produces: Release builds linked only to staged headers/libraries; Debug may explicitly fall back to Homebrew with a warning.

- [ ] **Step 1: Write a staging test that rejects fallback in Release**

```bash
if CONFIGURATION=Release PLATFORM_NAME=macosx OMNIA_NATIVE_PLAYBACK_ROOT=/missing \
  /bin/bash Omnia/Platform/Playback/stage-native-playback.sh; then
  exit 1
fi

CONFIGURATION=Debug PLATFORM_NAME=iphonesimulator \
  /bin/bash Omnia/Platform/Playback/stage-native-playback.sh
```

Expected contract: missing Release artifacts fail; non-macOS exits successfully without mutation.

- [ ] **Step 2: Run the staging test and witness RED**

```bash
[Automated validation command removed by repository policy.]
```

Expected: failure because the staging script does not exist.

- [ ] **Step 3: Replace implicit Homebrew linkage**

Set macOS Release `HEADER_SEARCH_PATHS`, `LIBRARY_SEARCH_PATHS`, and run-script input paths from `$(OMNIA_NATIVE_PLAYBACK_ROOT)`. Keep `/opt/homebrew` and `/usr/local` only in Debug conditional settings. Link both `mpv` and `torrent-rasterbar` on macOS.

The staging script copies the verified runtime closure, rewrites only known recorded install names, and signs nested dylibs with `EXPANDED_CODE_SIGN_IDENTITY`. It invokes `verify-playback-artifacts.sh` before copying and never recursively scans arbitrary filesystem roots.

- [ ] **Step 4: Run script tests and Xcode builds**

```bash
[Automated validation command removed by repository policy.]
xcodebuild -project Omnia.xcodeproj -scheme Omnia -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'generic/platform=iOS Simulator' build
```

For Release, set `OMNIA_NATIVE_PLAYBACK_ROOT` to the Task 2 verified output and run the signed macOS build. Expected: no `/opt/homebrew` reference appears in the Release app's `otool -L` closure.

- [ ] **Step 5: Commit Xcode integration**

```bash
[Historical automated-validation reference removed by repository policy.]
git commit -m "Link verified native playback artifacts"
```

### Task 4: Generate notices and an SPDX SBOM

**Files:**
- Create: `Scripts/generate-playback-notices.sh`
- Create: `Scripts/generate-playback-sbom.sh`
- Create: `Omnia/Resources/ThirdPartyNotices.md`
- Create: `NativeDependencies/playback-sbom.spdx.json`
- Modify: `Omnia/Features/Settings/AboutSettingsView.swift`
[Historical automated-validation reference removed by repository policy.]

**Interfaces:**
- Consumes: verified dependency manifest, exact extracted license files, and artifact metadata.
- Produces: human-readable notices, SPDX 2.3 JSON, and an in-app notice destination.

- [ ] **Step 1: Write compliance assertions**

```bash
rg -q 'libtorrent' Omnia/Resources/ThirdPartyNotices.md
rg -q 'FFmpeg' Omnia/Resources/ThirdPartyNotices.md
jq -e '.spdxVersion == "SPDX-2.3"' NativeDependencies/playback-sbom.spdx.json >/dev/null
jq -e '.packages | length > 5' NativeDependencies/playback-sbom.spdx.json >/dev/null
```

- [ ] **Step 2: Run compliance tests and witness RED**

```bash
[Automated validation command removed by repository policy.]
```

Expected: failure because notices and SBOM do not exist.

- [ ] **Step 3: Generate deterministic compliance artifacts**

Notices must contain component, version, copyright, full required license text, source URL, and relink/source instructions for LGPL components. The SPDX document uses stable `SPDXRef-Package-<normalized-name>` IDs, SHA-256 checksums, declared/concluded licenses, download locations, and `DEPENDS_ON` relationships from Omnia to the complete runtime closure.

Add a native `NavigationLink("Third-Party Software")` in About that renders the bundled notices with selectable text.

- [ ] **Step 4: Regenerate twice and prove determinism**

```bash
/bin/bash Scripts/generate-playback-notices.sh NativeDependencies/playback-dependencies.json Omnia/Resources/ThirdPartyNotices.md
/bin/bash Scripts/generate-playback-sbom.sh NativeDependencies/playback-dependencies.json NativeDependencies/playback-sbom.spdx.json
first="$(shasum -a 256 Omnia/Resources/ThirdPartyNotices.md NativeDependencies/playback-sbom.spdx.json)"
/bin/bash Scripts/generate-playback-notices.sh NativeDependencies/playback-dependencies.json Omnia/Resources/ThirdPartyNotices.md
/bin/bash Scripts/generate-playback-sbom.sh NativeDependencies/playback-dependencies.json NativeDependencies/playback-sbom.spdx.json
second="$(shasum -a 256 Omnia/Resources/ThirdPartyNotices.md NativeDependencies/playback-sbom.spdx.json)"
test "$first" = "$second"
[Automated validation command removed by repository policy.]
```

Expected: identical hashes and passing compliance assertions.

- [ ] **Step 5: Commit compliance outputs**

```bash
[Historical automated-validation reference removed by repository policy.]
git commit -m "Publish native playback licenses and SBOM"
```

### Task 5: Add archive and distribution gates

**Files:**
- Create: `Scripts/verify-playback-archive.sh`
- Create: `.github/workflows/native-playback.yml`
- Modify: `SECURITY.md`
- Modify: `INFRASTRUCTURE.md`
- Modify: `README.md`
[Historical automated-validation reference removed by repository policy.]

**Interfaces:**
- Consumes: a signed `.xcarchive`, manifest, notices, SBOM, and vulnerability scan result.
- Produces: a nonzero release gate for entitlement, signature, closure, license, architecture, provenance, or unreviewed high/critical vulnerability failures.

- [ ] **Step 1: Write archive verifier fixture tests**

Create synthetic metadata fixtures for missing sandbox, unsigned dylib, unexpected GPL metadata, and absent SBOM package. Require each to fail with only the failed check name—not a user path or signing identity—in output.

- [ ] **Step 2: Run verifier tests and witness RED**

```bash
[Automated validation command removed by repository policy.]
```

Expected: failure because the archive verifier does not exist.

- [ ] **Step 3: Implement the release gate and CI workflow**

The verifier runs `codesign --verify --deep --strict`, reads entitlements, verifies App Sandbox/hardened runtime/library validation, walks only the app executable and `Contents/Frameworks`, checks architectures/install names/signatures, correlates every dylib to the SBOM, and rejects unreviewed applicable high/critical scan findings.

The workflow verifies manifest/notices/SBOM on every related change and builds native artifacts on a pinned macOS runner. It uploads no distributable app and uses no signing secret. Update documentation to mark Homebrew Debug-only and list the human legal/notarization/archive approvals still required.

- [ ] **Step 4: Run all tooling and a signed local archive check**

```bash
[Automated validation command removed by repository policy.]
[Automated validation command removed by repository policy.]
[Automated validation command removed by repository policy.]
[Automated validation command removed by repository policy.]
[Automated validation command removed by repository policy.]
git diff --check
```

Create a local archive only with the user's valid identity and explicit `OMNIA_NATIVE_PLAYBACK_ROOT`; do not notarize or upload it. Run `verify-playback-archive.sh` against that archive. Expected: pass with no Homebrew path and no missing SBOM package.

- [ ] **Step 5: Commit release gates**

```bash
[Historical automated-validation reference removed by repository policy.]
git commit -m "Gate native playback distribution"
```
