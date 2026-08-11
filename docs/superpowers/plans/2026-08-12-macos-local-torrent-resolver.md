# macOS Local Torrent Resolver Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve add-on torrent sources entirely inside the macOS app, stream selected verified bytes to libmpv, and manage peer consent, cache, limits, progress, cancellation, and cleanup.

**Architecture:** A Swift `LocalPlaybackResolver` actor owns the product state machine and delegates torrent transport to an Objective-C++ libtorrent bridge. `ResolverCache` exclusively owns disk paths and quotas. libmpv reads a selected torrent file through an `omnia-torrent://` custom stream callback backed directly by the native engine, avoiding a localhost HTTP server.

**Tech Stack:** Swift actors and AsyncStream, SwiftUI, Objective-C++, libtorrent 2.0.10, Boost 1.90.0, libmpv custom stream callback API, XCTest, macOS App Sandbox.

## Global Constraints

- This plan begins only after the source/track plan and native-dependency plan pass.
- Torrent participation is macOS-only, off until consent version 1 is accepted, and never begins through autoplay.
- No incoming TCP/uTP peer listener, UPnP, NAT-PMP, local peer discovery, background download, or post-playback seeding.
- DHT and bounded HTTPS/UDP tracker hints are allowed only during an explicitly selected active job.
- Cache defaults to 20 GB; choices are 5, 10, 20, and 50 GB; preserve 10% volume capacity and the final 5 GB.
- Active data cannot be evicted; abandoned incomplete data is deleted unless temporary retention is enabled.
- Torrent identifiers, filenames, peer addresses, trackers, signed URLs, and headers never enter ordinary logs or synced data.
- Exact input bounds introduced below are security invariants and require hostile-fixture tests.

---

### Task 1: Parse bounded torrent descriptors from add-on payloads

**Files:**
- Create: `Omnia/Domain/Playback/TorrentSourceDescriptor.swift`
- Modify: `Omnia/Domain/Playback/PlaybackSource.swift`
- Test: `OmniaTests/TorrentSourceDescriptorTests.swift`
- Test: `OmniaTests/StremioAddonClientTests.swift`

**Interfaces:**
- Consumes: `AddonStream.infoHash`, `fileIdx`, `behaviorHints.filename`, and `sources`.
- Produces: `TorrentSourceDescriptor(infoHash:fileIndex:filename:trackers:)` and `AddonStreamCandidate.Delivery.localTorrent(TorrentSourceDescriptor)`.

- [ ] **Step 1: Write hash and tracker validation tests**

```swift
func testNormalizesV1HexAndBoundsTrackerHints() throws {
    let descriptor = try TorrentSourceDescriptor(
        infoHash: String(repeating: "A", count: 40),
        fileIndex: 3,
        filename: "Movie.mkv",
        sources: [
            "tracker:https://tracker.example/announce",
            "tracker:udp://tracker.example:6969/announce",
            "tracker:http://insecure.example/announce",
        ]
    )

    XCTAssertEqual(descriptor.infoHash.canonical, String(repeating: "a", count: 40))
    XCTAssertEqual(descriptor.trackers.map(\.scheme), ["https", "udp"])
}

func testRejectsInvalidHashesAndNegativeFileIndex() {
    XCTAssertThrowsError(try TorrentSourceDescriptor(infoHash: "xyz", fileIndex: -1, filename: nil, sources: []))
}
```

Also cover 32-character base32 v1 and 64-character hexadecimal v2 hashes, a 513-character filename, more than 16 trackers, embedded URL credentials, and tracker strings longer than 2,048 characters.

- [ ] **Step 2: Run the descriptor tests and witness RED**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' \
  -only-testing:OmniaTests/TorrentSourceDescriptorTests test
```

Expected: compile failure because the descriptor does not exist.

- [ ] **Step 3: Implement normalized descriptor parsing**

```swift
struct TorrentSourceDescriptor: Hashable, Sendable {
    let infoHash: TorrentInfoHash
    let fileIndex: Int?
    let filename: String?
    let trackers: [URL]

    init(infoHash: String, fileIndex: Int?, filename: String?, sources: [String]) throws
}

enum TorrentInfoHash: Hashable, Sendable {
    case v1Hex(String)
    case v1Base32(String)
    case v2Hex(String)
    var canonical: String { get }
}
```

Require index `0...100_000`, filename at most 512 UTF-8 bytes after trimming, at most 16 unique tracker URLs, only `https` or `udp`, a host, no user/password/fragment, and maximum URL length 2,048. Change the delivery case to `.localTorrent(TorrentSourceDescriptor)` and update exhaustive switches, labels, deduplication, and existing fixtures.

- [ ] **Step 4: Run source, policy, and descriptor tests**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' \
  -only-testing:OmniaTests/TorrentSourceDescriptorTests \
  -only-testing:OmniaTests/StremioAddonClientTests \
  -only-testing:OmniaTests/PlaybackPolicyTests \
  -only-testing:OmniaTests/PlaybackSourcePresentationTests test
```

Expected: pass; torrent rows remain visible and are not direct-autoplay candidates.

- [ ] **Step 5: Commit the torrent source contract**

```bash
git add Omnia/Domain/Playback/TorrentSourceDescriptor.swift Omnia/Domain/Playback/PlaybackSource.swift OmniaTests/TorrentSourceDescriptorTests.swift OmniaTests/StremioAddonClientTests.swift OmniaTests/PlaybackPolicyTests.swift OmniaTests/PlaybackSourcePresentationTests.swift
git commit -m "Model bounded local torrent sources"
```

### Task 2: Implement resolver cache reservations and eviction

**Files:**
- Create: `Omnia/Data/Playback/ResolverCachePolicy.swift`
- Create: `Omnia/Data/Playback/ResolverCache.swift`
- Test: `OmniaTests/ResolverCacheTests.swift`

**Interfaces:**
- Consumes: app caches root, `ResolverCachePolicy`, injected `VolumeCapacity`, job ID, expected bytes, and clock.
- Produces: `ResolverCache.Reservation`, usage snapshots, LRU eviction, job cleanup, and confirmed global clearing.

- [ ] **Step 1: Write deterministic cache-policy tests**

```swift
func testReservationEvictsInactiveLRUButProtectsActiveJob() async throws {
    let cache = try ResolverCache(
        root: temporaryRoot,
        policy: .init(quotaBytes: 10_000, minimumFreeBytes: 5_000, minimumFreeFraction: 0.10),
        capacity: { .init(totalBytes: 100_000, availableBytes: 12_000) }
    )
    try await cache.recordFixture(jobID: "old", bytes: 4_000, lastAccess: Date(timeIntervalSince1970: 1), active: false)
    try await cache.recordFixture(jobID: "active", bytes: 3_000, lastAccess: Date(timeIntervalSince1970: 2), active: true)

    _ = try await cache.reserve(jobID: "new", expectedBytes: 3_000, now: Date(timeIntervalSince1970: 3))

    XCTAssertFalse(await cache.contains(jobID: "old"))
    XCTAssertTrue(await cache.contains(jobID: "active"))
}
```

Add tests for quota failure before writing, path confinement, duplicate reservation, cancellation cleanup, retained partial data, active clear rejection, and LRU tie-breaking by opaque job ID.

- [ ] **Step 2: Run cache tests and witness RED**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' \
  -only-testing:OmniaTests/ResolverCacheTests test
```

Expected: compile failure because cache types do not exist.

- [ ] **Step 3: Implement the cache actor**

```swift
struct ResolverCachePolicy: Equatable, Sendable {
    static let defaultQuotaBytes: Int64 = 20 * 1_024 * 1_024 * 1_024
    let quotaBytes: Int64
    let minimumFreeBytes: Int64
    let minimumFreeFraction: Double
}

struct VolumeCapacity: Equatable, Sendable {
    let totalBytes: Int64
    let availableBytes: Int64
}

struct ResolverCacheUsage: Equatable, Sendable {
    let usedBytes: Int64
    let quotaBytes: Int64
    let activeJobCount: Int
}

actor ResolverCache {
    struct Reservation: Sendable {
        let jobID: String
        let directory: URL
        let expectedBytes: Int64
    }

    func reserve(jobID: String, expectedBytes: Int64, now: Date) throws -> Reservation
    func markActive(jobID: String, _ active: Bool) throws
    func finish(jobID: String, keepPartial: Bool, now: Date) throws
    func usage() throws -> ResolverCacheUsage
    func clearInactive() throws
}
```

Create the production root with `FileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)` plus `Omnia/PlaybackResolver/v1`. Reject job IDs outside `^[A-F0-9-]{36}$`; resolve standardized paths and require the job directory to remain a descendant of the root. Store only an atomic bounded metadata plist and mark the directory excluded from backup.

- [ ] **Step 4: Run cache tests and witness GREEN**

Run the Task 2 test command. Expected: pass without writing outside the test temporary directory.

- [ ] **Step 5: Commit cache ownership**

```bash
git add Omnia/Data/Playback/ResolverCachePolicy.swift Omnia/Data/Playback/ResolverCache.swift OmniaTests/ResolverCacheTests.swift
git commit -m "Add bounded resolver cache ownership"
```

### Task 3: Add local resolver settings and peer consent

**Files:**
- Create: `Omnia/Data/Settings/LocalResolverSettings.swift`
- Modify: `Omnia/Features/Settings/PlaybackResolverSettingsView.swift`
- Modify: `Omnia/Features/Settings/VideoPlayerSettingsView.swift`
- Test: `OmniaTests/LocalResolverSettingsTests.swift`
- Test: `OmniaTests/SettingsPresentationTests.swift`

**Interfaces:**
- Consumes: a dedicated UserDefaults suite and current cache usage.
- Produces: `LocalResolverPreferences`, consent version 1, quota choice, download/upload limits, partial-retention flag, and clear-cache confirmation UI.

- [ ] **Step 1: Write persistence and consent tests**

```swift
func testDefaultsRequireConsentAndUseTwentyGigabyteQuota() {
    let value = LocalResolverPreferences.default
    XCTAssertFalse(value.hasCurrentConsent)
    XCTAssertEqual(value.cacheQuota, .gigabytes20)
    XCTAssertEqual(value.downloadLimitKilobytesPerSecond, 0)
    XCTAssertEqual(value.uploadLimitKilobytesPerSecond, 1_024)
    XCTAssertFalse(value.retainsIncompleteJobs)
}
```

Add round-trip, corrupt-payload recovery, consent revocation, and bounds tests (`0...1_000_000` KiB/s).

- [ ] **Step 2: Run settings tests and witness RED**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' \
  -only-testing:OmniaTests/LocalResolverSettingsTests test
```

Expected: compile failure because local resolver settings do not exist.

- [ ] **Step 3: Implement dedicated local settings and native Form UI**

```swift
struct LocalResolverPreferences: Codable, Equatable, Sendable {
    static let consentVersion = 1
    var acceptedConsentVersion: Int?
    var cacheQuota: ResolverCacheQuota
    var downloadLimitKilobytesPerSecond: Int
    var uploadLimitKilobytesPerSecond: Int
    var retainsIncompleteJobs: Bool
    var hasCurrentConsent: Bool { acceptedConsentVersion == Self.consentVersion }
}

enum ResolverCacheQuota: Int64, Codable, CaseIterable, Sendable {
    case gigabytes5 = 5
    case gigabytes10 = 10
    case gigabytes20 = 20
    case gigabytes50 = 50

    var bytes: Int64 { rawValue * 1_024 * 1_024 * 1_024 }
}

@MainActor
@Observable
final class LocalResolverSettingsStore {
    private(set) var preferences: LocalResolverPreferences
    init(defaults: UserDefaults = .standard)
    func update(_ transform: (inout LocalResolverPreferences) -> Void)
    func acceptConsent()
    func revokeConsent()
}
```

Replace endpoint/token/host editing with local resolver status, peer disclosure, quota picker, bandwidth fields, current usage, retention toggle, consent revocation, and confirmed cache clearing. Keep legacy endpoint/token keys unread and inert; offer confirmed deletion of the legacy Keychain token without sending it anywhere.

- [ ] **Step 4: Run settings tests and macOS build**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' \
  -only-testing:OmniaTests/LocalResolverSettingsTests \
  -only-testing:OmniaTests/SettingsPresentationTests test
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' build
```

Expected: pass; resolver summary says "Consent required" or "Local resolver ready".

- [ ] **Step 5: Commit local settings**

```bash
git add Omnia/Data/Settings/LocalResolverSettings.swift Omnia/Features/Settings/PlaybackResolverSettingsView.swift Omnia/Features/Settings/VideoPlayerSettingsView.swift OmniaTests/LocalResolverSettingsTests.swift OmniaTests/SettingsPresentationTests.swift
git commit -m "Configure local peer playback safely"
```

### Task 4: Implement deterministic file selection

**Files:**
- Create: `Omnia/Domain/Playback/TorrentFileSelectionPolicy.swift`
- Test: `OmniaTests/TorrentFileSelectionPolicyTests.swift`

**Interfaces:**
- Consumes: `TorrentSourceDescriptor` and bounded `[TorrentMediaFile]`.
- Produces: `.selected(TorrentMediaFile)`, `.requiresChoice([TorrentMediaFile])`, or `.unavailable(reason)`.

- [ ] **Step 1: Write selection-order tests**

```swift
func testUsesIndexThenFilenameThenUniqueLargestVideo() {
    let files = [
        TorrentMediaFile(index: 0, relativePath: "sample.mkv", size: 10),
        TorrentMediaFile(index: 1, relativePath: "Movie.m2ts", size: 1_000),
    ]
    XCTAssertEqual(policy.select(files, preferredIndex: 0, preferredFilename: "Movie.m2ts"), .selected(files[0]))
    XCTAssertEqual(policy.select(files, preferredIndex: nil, preferredFilename: "Movie.m2ts"), .selected(files[1]))
    XCTAssertEqual(policy.select(files, preferredIndex: nil, preferredFilename: nil), .selected(files[1]))
}
```

Add tests for multiple similarly sized episodes requiring choice, traversal/absolute/link rejection, more than 10,000 files, zero-byte files, and stable filename ordering.

- [ ] **Step 2: Run selection tests and witness RED**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' \
  -only-testing:OmniaTests/TorrentFileSelectionPolicyTests test
```

Expected: compile failure because policy types do not exist.

- [ ] **Step 3: Implement pure bounded selection**

Recognize media extensions for ranking only: `mkv`, `mp4`, `m4v`, `mov`, `webm`, `avi`, `ts`, `m2ts`, `mts`, `mpg`, `mpeg`, `vob`, `iso`. Do not use this ranking list to reject a user-selected regular file. Normalize separators and Unicode, compare the final relative path case-insensitively for filename preference, and return at most 200 chooser rows sorted by descending size then path.

Define the exact value and result types:

```swift
struct TorrentMediaFile: Identifiable, Equatable, Hashable, Sendable {
    var id: Int { index }
    let index: Int
    let relativePath: String
    let size: Int64
}

enum TorrentFileSelection: Equatable, Sendable {
    case selected(TorrentMediaFile)
    case requiresChoice([TorrentMediaFile])
    case unavailable(TorrentFileSelectionFailure)
}

enum TorrentFileSelectionFailure: Equatable, Sendable {
    case noRegularFiles
    case metadataLimitExceeded
    case unsafePath
}
```

- [ ] **Step 4: Run selection tests and witness GREEN**

Run the Task 4 command. Expected: pass.

- [ ] **Step 5: Commit file selection**

```bash
git add Omnia/Domain/Playback/TorrentFileSelectionPolicy.swift OmniaTests/TorrentFileSelectionPolicyTests.swift
git commit -m "Select torrent media files deterministically"
```

### Task 5: Add the libtorrent Objective-C++ engine bridge

**Files:**
- Create: `Omnia/Platform/Playback/LocalTorrentEngine.h`
- Create: `Omnia/Platform/Playback/LocalTorrentEngine.mm`
- Modify: `Omnia/Omnia-Bridging-Header.h`
- Test: `OmniaTests/LocalTorrentEngineIntegrationTests.swift`
- Create: `OmniaTests/Fixtures/Torrent/`

**Interfaces:**
- Consumes: opaque job ID, `TorrentSourceDescriptor`, cache directory, bandwidth/connection limits.
- Produces: metadata/file events, blocking verified range reads, seek reprioritization, progress snapshots, cancellation, and teardown.

- [ ] **Step 1: Add a deterministic local-engine integration test**

Use a tiny generated torrent fixture and a test-only loopback seeder contained in the test process. The test starts one job, waits for metadata, selects the MKV file, reads the first 4 KiB, requests a range near the end, and cancels:

```swift
let engine = OMTorrentEngine(configuration: .testLoopbackOnly)
let events = engine.events(forJobID: jobID)
try engine.startJob(jobID, magnetURI: fixture.magnetURI, cacheDirectory: cacheURL)
let metadata = try await firstMetadata(from: events)
XCTAssertEqual(metadata.files.count, 1)
let first = try engine.read(jobID, fileIndex: 0, offset: 0, length: 4_096)
XCTAssertEqual(first, fixture.prefix)
engine.cancelJob(jobID)
```

No public tracker, DHT node, or peer is contacted in this test.

- [ ] **Step 2: Run the engine test and witness RED**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' \
  -only-testing:OmniaTests/LocalTorrentEngineIntegrationTests test
```

Expected: compile failure because the bridge does not exist.

- [ ] **Step 3: Implement the native engine on one serial queue**

Expose Objective-C value types only:

```objc
@interface OMTorrentEngine : NSObject
- (void)startJobWithID:(NSUUID *)jobID
             magnetURI:(NSString *)magnetURI
        cacheDirectory:(NSURL *)cacheDirectory;
- (NSArray<OMTorrentFile *> *)filesForJobID:(NSUUID *)jobID error:(NSError **)error;
- (NSData *)readJobID:(NSUUID *)jobID fileIndex:(NSInteger)fileIndex offset:(int64_t)offset length:(NSUInteger)length error:(NSError **)error;
- (void)reprioritizeJobID:(NSUUID *)jobID fileIndex:(NSInteger)fileIndex offset:(int64_t)offset lookAhead:(NSUInteger)lookAhead;
- (void)cancelJobID:(NSUUID *)jobID;
@end
```

Also expose `OMTorrentEngineConfiguration` with production values and a test-only `+testLoopbackOnly` factory compiled under `DEBUG`. The test factory disables DHT and trackers and accepts only the fixture seeder's loopback endpoint.

Configure libtorrent with incoming TCP/uTP, UPnP, NAT-PMP, and LSD disabled; DHT enabled only for non-test jobs; explicit connection, peer, disk, memory, upload, and download limits; and an alert mask containing only required status/storage/error events. Build magnet parameters from the validated hash and trackers. Piece reads wait on a condition variable with cancellation and a 30-second read deadline, return only hash-verified pieces, and prioritize the requested range plus 32 MiB look-ahead. Never log alert messages verbatim.

- [ ] **Step 4: Run the engine integration test and inspect sandbox behavior**

Run the Task 5 command. Expected: pass using only loopback fixture traffic, with cancellation completing within one second and all files confined to the temporary cache root.

- [ ] **Step 5: Commit the native engine**

```bash
git add Omnia/Platform/Playback/LocalTorrentEngine.h Omnia/Platform/Playback/LocalTorrentEngine.mm Omnia/Omnia-Bridging-Header.h OmniaTests/LocalTorrentEngineIntegrationTests.swift OmniaTests/Fixtures/Torrent
git commit -m "Add bounded local torrent engine"
```

### Task 6: Build the resolver actor and state machine

**Files:**
- Create: `Omnia/Platform/Playback/LocalPlaybackResolver.swift`
- Test: `OmniaTests/LocalPlaybackResolverTests.swift`

**Interfaces:**
- Consumes: `TorrentSourceDescriptor`, `ResolverCache`, `TorrentFileSelectionPolicy`, local settings, and `TorrentEngineProtocol` adapter.
- Produces: `LocalResolutionState`, `ResolvedTorrentSource`, file-choice continuation, cancellation, and cleanup.

- [ ] **Step 1: Write fake-engine state transition tests**

```swift
func testResolveMovesThroughMetadataChoiceBufferAndReady() async throws {
    let engine = FakeTorrentEngine(events: [.metadata(files), .buffered(bytes: 8_388_608)])
    let resolver = LocalPlaybackResolver(engine: engine, cache: cache, preferences: consentedPreferences)

    let states = resolver.states
    await resolver.start(candidate)
    await resolver.selectFile(files[1])

    XCTAssertEqual(try await collect(states), [
        .readingMetadata,
        .selectingFile(files),
        .buffering(downloadedBytes: 8_388_608, requiredBytes: 8_388_608),
        .ready(ResolvedTorrentSource(jobID: engine.jobID, file: files[1])),
    ])
}
```

Add tests for consent missing, storage reservation failure, metadata timeout at 30 seconds, cancellation, engine error redaction, one-active-job enforcement, and abandoned partial cleanup.

- [ ] **Step 2: Run resolver tests and witness RED**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' \
  -only-testing:OmniaTests/LocalPlaybackResolverTests test
```

Expected: compile failure because resolver types do not exist.

- [ ] **Step 3: Implement actor isolation and dependency protocols**

```swift
enum LocalResolutionState: Equatable, Sendable {
    case idle
    case readingMetadata
    case selectingFile([TorrentMediaFile])
    case buffering(downloadedBytes: Int64, requiredBytes: Int64)
    case ready(ResolvedTorrentSource)
    case failed(LocalResolverFailure)
    case cancelled
}

enum TorrentEngineEvent: Equatable, Sendable {
    case metadata([TorrentMediaFile])
    case progress(downloadedBytes: Int64, totalBytes: Int64?)
    case failed(TorrentEngineFailure)
    case cancelled
}

enum TorrentEngineFailure: Equatable, Sendable {
    case invalidMetadata
    case metadataLimitExceeded
    case readTimedOut
    case hashCheckFailed
    case networkUnavailable
    case internalFailure
}

enum LocalResolverFailure: Equatable, Sendable {
    case consentRequired
    case invalidSource
    case metadataTimedOut
    case storageFull
    case noPlayableFile
    case networkUnavailable
    case engineFailed
}

actor LocalPlaybackResolver {
    nonisolated let states: AsyncStream<LocalResolutionState>
    func start(_ candidate: AddonStreamCandidate) async
    func selectFile(_ file: TorrentMediaFile) async
    func cancel() async
    func stop(keepPartial: Bool) async
}
```

Define the neighboring types in the same file so the stream-registration task uses one stable contract:

```swift
struct ResolvedTorrentSource: Equatable, Sendable {
    let jobID: UUID
    let file: TorrentMediaFile
    var playbackURL: URL { URL(string: "omnia-torrent://\(jobID.uuidString)")! }
}

protocol TorrentEngineProtocol: Sendable {
    func events(for jobID: UUID) -> AsyncThrowingStream<TorrentEngineEvent, Error>
    func start(jobID: UUID, descriptor: TorrentSourceDescriptor, cacheDirectory: URL) async throws
    func select(jobID: UUID, file: TorrentMediaFile) async throws
    func cancel(jobID: UUID) async
}
```

A Swift actor adapter around `OMTorrentEngine` conforms to `TorrentEngineProtocol`; the Objective-C++ object itself is never declared `Sendable`. Use protocols for cache, clock, and UUID generation so tests contain no sleeps or network. Emit bounded failure enums, not native error strings. State tests consume `states.prefix(4)` so the assertion cannot wait forever on the long-lived stream.

- [ ] **Step 4: Run resolver tests and witness GREEN**

Run the Task 6 command. Expected: pass.

- [ ] **Step 5: Commit resolver orchestration**

```bash
git add Omnia/Platform/Playback/LocalPlaybackResolver.swift OmniaTests/LocalPlaybackResolverTests.swift
git commit -m "Coordinate local torrent resolution"
```

### Task 7: Register the custom libmpv torrent stream

**Files:**
- Modify: `Omnia/Platform/Playback/MPVPlayerController.h`
- Modify: `Omnia/Platform/Playback/MPVPlayerController.m`
- Modify: `Omnia/Platform/Playback/PlaybackSession.swift`
- Test: `OmniaTests/MPVPlaybackIntegrationTests.swift`

**Interfaces:**
- Consumes: `ResolvedTorrentSource`, `OMTorrentEngine`, and opaque `omnia-torrent://<UUID>` URLs.
- Produces: libmpv open/read/seek/size/close callbacks and `PlaybackSession.start(...resolvedTorrent:)`.

- [ ] **Step 1: Add a custom-stream mpv integration test**

Create a test byte-stream provider backed by the existing multi-track MKV fixture, initialize the controller with `omnia-torrent://<UUID>`, and assert rendered frame plus two audio/one subtitle tracks. Seek once and assert the provider received the new offset.

- [ ] **Step 2: Run the custom-stream test and witness RED**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' \
  -only-testing:OmniaTests/MPVPlaybackIntegrationTests test
```

Expected: compile failure because the stream-provider initializer does not exist.

- [ ] **Step 3: Register safe read-only callbacks before mpv initialization**

Add this protocol and extend the controller initializer with an optional provider:

```objc
@protocol OMMpvByteStreamProvider <NSObject>
- (int64_t)sizeForJobID:(NSUUID *)jobID error:(NSError **)error;
- (NSInteger)readJobID:(NSUUID *)jobID offset:(int64_t)offset buffer:(void *)buffer length:(NSUInteger)length error:(NSError **)error;
- (void)seekJobID:(NSUUID *)jobID offset:(int64_t)offset;
- (void)closeJobID:(NSUUID *)jobID;
@end
```

When the URL scheme is `omnia-torrent`, validate that the host is a UUID, register `mpv_stream_cb_add_ro` before `mpv_initialize`, and attach a per-open cookie containing only provider/job/file handles. Map cancellation/timeouts to mpv errors, cap a single read request at 4 MiB, and release cookies exactly once.

Add a main-actor `PlaybackInput` Swift enum so direct HTTPS and resolved torrent sources share session startup without converting torrent data into HTTPS:

```swift
enum PlaybackInput {
    case direct(PlaybackSource)
    case resolvedTorrent(ResolvedTorrentSource, provider: OMMpvByteStreamProvider)
}
```

`PlaybackSession.start` switches over the input and creates `OMMpvPlayerController` with the direct URL/headers or the opaque torrent URL/provider. Mobile compilation includes only `.direct` and does not import Objective-C torrent types.

- [ ] **Step 4: Run mpv integration and resolver tests**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' \
  -only-testing:OmniaTests/MPVPlaybackIntegrationTests \
  -only-testing:OmniaTests/LocalPlaybackResolverTests \
  -only-testing:OmniaTests/LocalTorrentEngineIntegrationTests test
```

Expected: pass; stream seek reaches the provider and embedded tracks populate.

- [ ] **Step 5: Commit the libmpv stream bridge**

```bash
git add Omnia/Platform/Playback/MPVPlayerController.h Omnia/Platform/Playback/MPVPlayerController.m Omnia/Platform/Playback/PlaybackSession.swift OmniaTests/MPVPlaybackIntegrationTests.swift
git commit -m "Stream verified torrent bytes into libmpv"
```

### Task 8: Integrate resolver UI, cancellation, and final security evidence

**Files:**
- Modify: `Omnia/App/OmniaApp.swift`
- Modify: `Omnia/Features/Playback/PlaybackViews.swift`
- Modify: `Omnia/Features/Settings/PlaybackResolverSettingsView.swift`
- Modify: `SECURITY.md`
- Modify: `DESIGN.md`
- Modify: `README.md`
- Test: `OmniaTests/PlaybackSourcePresentationTests.swift`
- Test: `OmniaTests/LocalPlaybackResolverTests.swift`

**Interfaces:**
- Consumes: local resolver state stream, file selection, cache usage, and `PlaybackInput.resolvedTorrent`.
- Produces: consent, metadata, chooser, buffering, progress, cancel, retry, storage-full, offline, and failure states in the source sheet.

- [ ] **Step 1: Add presentation-state tests**

Test exact accessible labels for `.readingMetadata`, `.selectingFile`, `.buffering`, `.failed(.storageFull)`, and `.cancelled`. Assert peer-to-peer rows cannot invoke resolve while consent is absent and direct rows remain usable during a torrent failure.

- [ ] **Step 2: Run presentation tests and witness RED**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' \
  -only-testing:OmniaTests/PlaybackSourcePresentationTests \
  -only-testing:OmniaTests/LocalPlaybackResolverTests test
```

Expected: failure because local resolver presentation states are not mapped.

- [ ] **Step 3: Compose one resolver and implement all UI states**

Create `ResolverCache`, `LocalResolverSettingsStore`, and `LocalPlaybackResolver` at the app root on macOS. A local torrent row presents first-use consent, then starts metadata. Present a native file chooser for `.selectingFile`; show determinate progress when totals exist; retain Cancel during every active state; call `playback.start` only from `.ready`. Stop and clean the resolver when playback closes or another source starts.

Update security and design documentation with the exact network, storage, consent, IP exposure, upload, cancellation, and no-background behavior. Remove copy claiming that Omnia has no peer transport, replacing it with the truthful opt-in macOS scope.

- [ ] **Step 4: Run the complete macOS suite, mobile build, and hygiene checks**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'generic/platform=iOS Simulator' build
git diff --check
git status --short
```

Then smoke-test on macOS: consent decline/accept/revoke, metadata timeout, multiple-file choice, initial buffering, forward/back seek, track menus, cancellation, cache full, offline retry, close cleanup, window resize, full screen, keyboard, VoiceOver, Reduce Motion, and Increase Contrast.

- [ ] **Step 5: Commit the complete local resolver flow**

```bash
git add Omnia/App/OmniaApp.swift Omnia/Features/Playback/PlaybackViews.swift Omnia/Features/Settings/PlaybackResolverSettingsView.swift SECURITY.md DESIGN.md README.md OmniaTests/PlaybackSourcePresentationTests.swift OmniaTests/LocalPlaybackResolverTests.swift
git commit -m "Resolve torrent playback locally on macOS"
```
