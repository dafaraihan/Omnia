# macOS Disc Materialization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Materialize bounded unencrypted Blu-ray ISO and Blu-ray directory sources into Omnia's resolver cache and open them through libmpv on macOS, while identifying DVD layouts and reporting the distribution-license boundary truthfully.

**Architecture:** Disc detection is a pure bounded policy over normalized torrent file metadata or an explicitly selected HTTPS ISO. `DiscMaterializer` writes complete verified objects through `ResolverCache`; it never extracts archives or mounts filesystems. A typed `PlaybackInput.disc` maps supported media to mpv's `bd://` URL plus a validated cache-owned device path. DVD structures remain visible but unavailable because the required GPL libraries are excluded from the approved LGPL distribution profile.

**Tech Stack:** Swift actors, URLSession bounded HTTPS download for explicit ISO materialization, local torrent resolver range/file API, ResolverCache, Objective-C libmpv options, libbluray, XCTest.

## Global Constraints

- This plan begins only after local torrent resolving and reproducible native dependencies pass.
- Only unencrypted media is supported; no AACS, BD+, CSS circumvention, key databases, decryption helpers, or disc menus.
- DVD navigation is not included: `libdvdread` and `libdvdnav` are GPL-2.0-or-later and cannot enter the approved LGPL release closure without a separate relicensing decision and design review.
- Never mount an ISO, execute disc content, run BD-J, extract arbitrary archives, or write outside the reserved cache directory.
- A complete size must be known and reservable before materialization starts.
- Direct HTTPS disc materialization requires HTTPS, normal TLS, no URL credentials, bounded redirects, exact header filtering, and explicit user action.
- Torrent files are readable only after libtorrent piece verification.
- Materialized disc data is discardable cache data and follows the existing 5/10/20/50 GB quota and free-space guardrails.

---

### Task 1: Detect supported disc layouts without reading media payloads

**Files:**
- Create: `Omnia/Domain/Playback/DiscMediaDescriptor.swift`
- Create: `Omnia/Domain/Playback/DiscDetectionPolicy.swift`
- Test: `OmniaTests/DiscDetectionPolicyTests.swift`

**Interfaces:**
- Consumes: bounded `[TorrentMediaFile]` or one explicit HTTPS URL plus declared byte size.
- Produces: `DiscDetectionResult.supported(.iso(file))`, `.supported(.bluRayDirectory(root:files:))`, `.unsupportedDVDDirectory(root:)`, `.notDisc`, or `.rejected(reason)`.

- [ ] **Step 1: Write layout and hostility tests**

```swift
func testDetectsBluRayAndDVDDirectoryRoots() {
    XCTAssertEqual(
        policy.detect(files: [file("Movie/BDMV/index.bdmv"), file("Movie/BDMV/STREAM/00001.m2ts")]),
        .supported(.bluRayDirectory(root: "Movie", files: [file("Movie/BDMV/index.bdmv"), file("Movie/BDMV/STREAM/00001.m2ts")]))
    )
    XCTAssertEqual(
        policy.detect(files: [file("Disc/VIDEO_TS/VIDEO_TS.IFO"), file("Disc/VIDEO_TS/VTS_01_1.VOB")]),
        .unsupportedDVDDirectory(root: "Disc")
    )
}
```

Add tests for one ISO, multiple ISOs requiring choice, mixed unrelated roots, traversal, case-insensitive marker names, more than 10,000 files, directory total overflow, and encrypted-marker metadata remaining "unknown encryption" until native open.

- [ ] **Step 2: Run detection tests and witness RED**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' \
  -only-testing:OmniaTests/DiscDetectionPolicyTests test
```

Expected: compile failure because disc types do not exist.

- [ ] **Step 3: Implement pure detection and exact bounds**

```swift
enum DiscMediaDescriptor: Equatable, Sendable {
    case iso(TorrentMediaFile)
    case bluRayDirectory(root: String, files: [TorrentMediaFile])
}

enum DiscDetectionResult: Equatable, Sendable {
    case supported(DiscMediaDescriptor)
    case unsupportedDVDDirectory(root: String)
    case notDisc
    case rejected(DiscDetectionFailure)
}

enum DiscDetectionFailure: Equatable, Sendable {
    case metadataLimitExceeded
    case unsafePath
    case totalSizeExceeded
    case ambiguousLayout
}
```

Require normalized relative paths, regular files only, at most 10,000 entries, total bytes greater than zero and no more than the selected cache quota. Detect `BDMV/index.bdmv` and `VIDEO_TS/VIDEO_TS.IFO` case-insensitively but preserve normalized paths for writes. ISO extension is a ranking signal; the native open probe must confirm Blu-ray. A non-Blu-ray ISO is reported as unsupported under the current LGPL dependency policy.

- [ ] **Step 4: Run detection tests and witness GREEN**

Run the Task 1 command. Expected: pass.

- [ ] **Step 5: Commit disc detection**

```bash
git add Omnia/Domain/Playback/DiscMediaDescriptor.swift Omnia/Domain/Playback/DiscDetectionPolicy.swift OmniaTests/DiscDetectionPolicyTests.swift
git commit -m "Detect bounded disc media layouts"
```

### Task 2: Materialize complete disc objects through cache ownership

**Files:**
- Create: `Omnia/Data/Playback/DiscMaterializer.swift`
- Modify: `Omnia/Data/Playback/ResolverCache.swift`
- Test: `OmniaTests/DiscMaterializerTests.swift`

**Interfaces:**
- Consumes: `DiscMediaDescriptor`, a `DiscByteSource`, cache reservation, progress continuation, and cancellation.
- Produces: `MaterializedDisc(rootURL:kindHint:bytes:)` with every path confined to its reservation.

- [ ] **Step 1: Write materialization, cancellation, and escape tests**

```swift
func testWritesVerifiedDirectoryTreeInsideReservation() async throws {
    let result = try await materializer.materialize(
        .bluRayDirectory(root: "Movie", files: fixtureFiles),
        source: FakeDiscByteSource(contents: fixtureContents)
    )

    XCTAssertTrue(result.rootURL.path.hasPrefix(cacheRoot.path + "/"))
    XCTAssertEqual(try Data(contentsOf: result.rootURL.appending(path: "BDMV/index.bdmv")), fixtureContents[0])
}
```

Add tests for byte-count mismatch, source failure, cancellation during the second file, symlink preexistence, insufficient reservation, atomic completion marker, partial cleanup, and progress never exceeding total.

- [ ] **Step 2: Run materializer tests and witness RED**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' \
  -only-testing:OmniaTests/DiscMaterializerTests test
```

Expected: compile failure because `DiscMaterializer` does not exist.

- [ ] **Step 3: Implement streamed, atomic, confined writes**

```swift
protocol DiscByteSource: Sendable {
    func bytes(for file: TorrentMediaFile) -> AsyncThrowingStream<Data, Error>
}

struct MaterializedDisc: Equatable, Sendable {
    enum KindHint: Equatable, Sendable { case iso, bluRayDirectory }
    let jobID: UUID
    let rootURL: URL
    let kindHint: KindHint
    let bytes: Int64
}

enum DiscMaterializationEvent: Equatable, Sendable {
    case progress(completedBytes: Int64, totalBytes: Int64)
    case ready(MaterializedDisc)
}

actor DiscMaterializer {
    func materialize(
        _ descriptor: DiscMediaDescriptor,
        source: any DiscByteSource
    ) -> AsyncThrowingStream<DiscMaterializationEvent, Error>
}
```

Reserve the complete declared total first. For each file, create parent directories with no links, write to a sibling `.partial` file using `FileHandle`, require exact byte count, call `synchronize`, then atomically rename. Write a final bounded `complete.plist` only after every file succeeds. On failure/cancellation, close handles and apply the resolver's retention policy.

- [ ] **Step 4: Run materializer and cache tests**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' \
  -only-testing:OmniaTests/DiscMaterializerTests \
  -only-testing:OmniaTests/ResolverCacheTests test
```

Expected: pass.

- [ ] **Step 5: Commit disc materialization**

```bash
git add Omnia/Data/Playback/DiscMaterializer.swift Omnia/Data/Playback/ResolverCache.swift OmniaTests/DiscMaterializerTests.swift
git commit -m "Materialize disc media in resolver cache"
```

### Task 3: Add explicit HTTPS ISO materialization

**Files:**
- Create: `Omnia/Data/Playback/HTTPSDiscByteSource.swift`
- Modify: `Omnia/Data/Networking/HTTPTransport.swift`
- Test: `OmniaTests/HTTPSDiscByteSourceTests.swift`

**Interfaces:**
- Consumes: direct HTTPS ISO candidate, filtered request headers, URLSession transport, declared or HEAD-discovered size, and cancellation.
- Produces: bounded streamed bytes only after an exact size is known and accepted by cache reservation.

- [ ] **Step 1: Write URL, redirect, and size tests with URLProtocol**

Test: valid HTTPS with Content-Length; missing/invalid length rejection; over-quota rejection before GET; redirect to another origin drops sensitive headers and is rejected unless no credentials are present; HTTP downgrade rejection; more than five redirects; byte count exceeding declared length; cancellation closes the task.

- [ ] **Step 2: Run HTTPS source tests and witness RED**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' \
  -only-testing:OmniaTests/HTTPSDiscByteSourceTests test
```

Expected: compile failure because the byte source does not exist.

- [ ] **Step 3: Implement a dedicated streamed loader**

Do not reuse whole-body `HTTPTransport.data`. Add a bounded streaming abstraction that performs HEAD or a one-byte range probe, requires a positive size no greater than cache availability, then streams GET bytes through `URLSession.AsyncBytes`. Forward only the existing sanitized request headers. Revalidate HTTPS, host, user information, redirect count, and credential retention on every redirect. Abort immediately on size overrun.

- [ ] **Step 4: Run HTTPS and existing transport tests**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' \
  -only-testing:OmniaTests/HTTPSDiscByteSourceTests \
  -only-testing:OmniaTests/HTTPTransportTests test
```

Expected: pass.

- [ ] **Step 5: Commit HTTPS materialization transport**

```bash
git add Omnia/Data/Playback/HTTPSDiscByteSource.swift Omnia/Data/Networking/HTTPTransport.swift OmniaTests/HTTPSDiscByteSourceTests.swift
git commit -m "Stream explicit HTTPS disc images safely"
```

### Task 4: Open typed disc inputs through libmpv

**Files:**
- Modify: `Omnia/Platform/Playback/MPVPlayerController.h`
- Modify: `Omnia/Platform/Playback/MPVPlayerController.m`
- Modify: `Omnia/Platform/Playback/PlaybackSession.swift`
- Test: `OmniaTests/MPVDiscPlaybackIntegrationTests.swift`
- Create: `OmniaTests/Fixtures/Disc/`

**Interfaces:**
- Consumes: `PlaybackInput.disc(MaterializedDisc)`.
- Produces: validated `bd://` load commands, encrypted/unsupported disc failure mapping, and normal track snapshots.

- [ ] **Step 1: Add small unencrypted disc fixture tests**

For a minimal reviewed Blu-ray fixture, initialize the session with `.disc`, wait for file-loaded or a bounded failure, and assert video/audio track discovery. Add an invalid-path test proving a path outside the resolver cache is rejected before mpv.

- [ ] **Step 2: Run disc integration and witness RED**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' \
  -only-testing:OmniaTests/MPVDiscPlaybackIntegrationTests test
```

Expected: compile failure because typed disc input does not exist.

- [ ] **Step 3: Add a typed request and disable interactive disc code**

Extend `PlaybackInput`:

```swift
case disc(MaterializedDisc)
```

Translate Blu-ray directory markers directly to `bd://longest` plus `bluray-device`. For ISO, require a successful libbluray probe before loading; otherwise return "This disc image is not a supported unencrypted Blu-ray." Disable disc menus and BD-J. Validate standardized device paths are descendants of the resolver cache before setting any mpv option. Map encryption-related failures to "Encrypted disc media is not supported" without exposing paths.

- [ ] **Step 4: Run disc and multi-track integration tests**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' \
  -only-testing:OmniaTests/MPVDiscPlaybackIntegrationTests \
  -only-testing:OmniaTests/MPVPlaybackIntegrationTests test
```

Expected: unencrypted fixture loads, invalid path is rejected, existing MKV playback remains green.

- [ ] **Step 5: Commit typed disc playback**

```bash
git add Omnia/Platform/Playback/MPVPlayerController.h Omnia/Platform/Playback/MPVPlayerController.m Omnia/Platform/Playback/PlaybackSession.swift OmniaTests/MPVDiscPlaybackIntegrationTests.swift OmniaTests/Fixtures/Disc
git commit -m "Open materialized discs with libmpv"
```

### Task 5: Integrate disc preparation states and final verification

**Files:**
- Modify: `Omnia/Platform/Playback/LocalPlaybackResolver.swift`
- Modify: `Omnia/Features/Playback/PlaybackViews.swift`
- Modify: `DESIGN.md`
- Modify: `SECURITY.md`
- Modify: `README.md`
- Test: `OmniaTests/LocalPlaybackResolverTests.swift`
- Test: `OmniaTests/PlaybackSourcePresentationTests.swift`

**Interfaces:**
- Consumes: disc detection, materialization progress, cache failures, and typed playback input.
- Produces: explicit "Prepare Disc" action and detecting/materializing/ready/failure/cancel UI states.

- [ ] **Step 1: Add state and copy tests**

Assert `.detectingDisc`, `.materializingDisc(completedBytes:totalBytes:)`, `.failed(.encryptedDisc)`, `.failed(.storageFull)`, and `.ready(.disc)` map to exact accessible copy. Assert HTTPS ISO does not auto-materialize and a normal direct HTTPS MKV remains an immediate Play action.

- [ ] **Step 2: Run presentation/resolver tests and witness RED**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' \
  -only-testing:OmniaTests/LocalPlaybackResolverTests \
  -only-testing:OmniaTests/PlaybackSourcePresentationTests test
```

Expected: failure because disc states are absent.

- [ ] **Step 3: Add explicit preparation and cancellation UI**

Extend the resolver contracts before wiring the view:

```swift
// New LocalResolutionState cases
case detectingDisc
case materializingDisc(completedBytes: Int64, totalBytes: Int64)

// New LocalResolverFailure cases
case unsupportedDisc
case encryptedDisc
```

Offer "Prepare Disc" only for a detected torrent Blu-ray layout or an explicitly identified HTTPS ISO with known reservable size. Show DVD layouts as unavailable with the GPL dependency explanation. Show size and cache impact before starting. Keep Cancel active during every file; on success call `PlaybackSession.start` with `.disc`. On failure retain other source rows and expose retry/cleanup. Document unencrypted-only, no-menu, no-BD-J, no-DRM limits.

- [ ] **Step 4: Run full tests, builds, hygiene, and smoke checks**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'generic/platform=iOS Simulator' build
/bin/bash Scripts/verify-playback-manifest.sh NativeDependencies/playback-dependencies.json
git diff --check
git status --short
```

Smoke-test unencrypted Blu-ray ISO/directory preparation, DVD unavailable copy, cancel, insufficient storage, cleanup, audio/subtitle tracks, keyboard, VoiceOver, resizing, and full screen. Confirm no AACS/BD+/CSS helper or GPL DVD library appears in the app closure or SBOM.

- [ ] **Step 5: Commit the disc flow**

```bash
git add Omnia/Platform/Playback/LocalPlaybackResolver.swift Omnia/Features/Playback/PlaybackViews.swift DESIGN.md SECURITY.md README.md OmniaTests/LocalPlaybackResolverTests.swift OmniaTests/PlaybackSourcePresentationTests.swift
git commit -m "Prepare unencrypted disc media locally"
```
