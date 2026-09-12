# macOS Timeline Scene Previews Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a timestamp-addressed 16:9 scene preview while hovering the macOS playback timeline without seeking or blocking the visible player.

**Architecture:** Resolve an explicit source storyboard first, an HLS image playlist second, and an isolated on-demand libmpv frame last. A session-owned actor validates and caches preview frames; `PlaybackSession` owns debounce/cancellation and rejects stale-source results; `MacPlaybackChrome` owns only hover coordinates and the bubble. The local generator has its own headless libmpv core and stops on hover exit.

**Tech Stack:** Swift 6 structured concurrency, SwiftUI/AppKit, Foundation URLSession, ImageIO/CoreGraphics, Objective-C libmpv client API, XCTest, Instruments

**Spec:** `docs/superpowers/specs/2026-09-12-macos-playback-track-and-timeline-previews-design.md`

## Global Constraints

- macOS only; do not change iOS playback.
- Preview order is explicit source storyboard, HLS image playlist, then exact-source local generation.
- Never use TMDB artwork or a Stremio metadata thumbnail as a timeline frame.
- Never upload or disclose source URLs, headers, credentials, or viewing activity to a new third party.
- Provider manifests/images require HTTPS, an exact normalized origin, bounded bytes/dimensions, and cancellation.
- Local generation uses a separate low-priority libmpv core and never seeks the primary player.
- Normal mode: 250 ms debounce, one in-flight request, at most 24 frames or 8 MiB in memory.
- Low Power Mode: 500 ms debounce and at most eight frames, still bounded by 8 MiB.
- Stop work on hover exit/player stop; clear memory on source change/player close; do not pre-scan a title.
- Decline local generation for unseekable input.
- Keep the existing slider's drag, keyboard, VoiceOver, and Full Keyboard Access behavior.
- Bubble is 16:9 with timestamp, clamped to the timeline/window; failure quietly falls back to timestamp only.
- Reduce Motion removes preview transitions.
- No new dependency and no hosted deployment.
- Do not stage or commit unrelated dirty-worktree files.

---

### Task 1: Record a reproducible Release baseline

**Files:**
- Read: `PERFORMANCE.md`
- Evidence only: no source changes

**Interfaces:**
- Consumes: current Release app and one local seekable fixture/source.
- Produces: before evidence for hover CPU/energy, dropped frames, memory, and primary-player position.

- [ ] **Step 1: Read the performance policy**

```bash
sed -n '1,260p' PERFORMANCE.md
```

- [ ] **Step 2: Build Release and record the baseline scenario**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -configuration Release \
  -destination 'platform=macOS' build
```

After one untimed warm-up, use Instruments Time Profiler, Allocations, and Energy Log on the same Mac for ten identical runs. Play one fixed local seekable source for 60 seconds and move the pointer across the current timeline for 15 seconds. Record median, p90, range, and variance:

```text
Mac model / macOS / power source / Low Power Mode:
Source identity, duration, resolution, and local/remote:
CPU average and peak during the 15-second timeline interaction:
Main-thread stalls above 16.7 ms:
Memory high-water mark:
Primary-player dropped frames:
Network bytes:
Energy impact:
Primary playback position before/after interaction:
```

The current UI has no preview, so this establishes playback cost and primary-player stability rather than preview latency.

---

### Task 2: Define timestamp mapping, source descriptors, and a bounded LRU cache

**Files:**
- Create: `Omnia/Domain/Playback/PlaybackTimelinePreview.swift`
- Modify: `Omnia/Domain/Playback/PlaybackSource.swift`
- Test: `OmniaTests/PlaybackTimelinePreviewTests.swift`

**Interfaces:**
- Consumes: playback source identity and duration.
- Produces:
  - `PlaybackTimelinePreviewDescriptor`
  - `PlaybackStoryboardDescriptor`
  - `PlaybackStoryboardTile`
  - `PlaybackTimelinePreviewPosition.timestamp(x:width:duration:)`
  - `PlaybackTimelinePreviewCache<Key, Value>` with count/byte limits
  - `PlaybackSource.timelinePreviewDescriptor`

- [ ] **Step 1: Write failing mapping and cache tests**

Create `OmniaTests/PlaybackTimelinePreviewTests.swift`:

```swift
import XCTest
@testable import Omnia

final class PlaybackTimelinePreviewTests: XCTestCase {
    func testHoverTimestampClampsToTimelineBounds() {
        XCTAssertEqual(
            PlaybackTimelinePreviewPosition.timestamp(x: -20, width: 200, duration: 1_000),
            0
        )
        XCTAssertEqual(
            PlaybackTimelinePreviewPosition.timestamp(x: 50, width: 200, duration: 1_000),
            250
        )
        XCTAssertEqual(
            PlaybackTimelinePreviewPosition.timestamp(x: 240, width: 200, duration: 1_000),
            1_000
        )
        XCTAssertNil(
            PlaybackTimelinePreviewPosition.timestamp(x: 50, width: 0, duration: 1_000)
        )
    }

    func testCacheEvictsLeastRecentlyUsedByCount() {
        var cache = PlaybackTimelinePreviewCache<Int, String>(maximumCount: 2, maximumBytes: 100)
        cache.insert("one", for: 1, byteCount: 10)
        cache.insert("two", for: 2, byteCount: 10)
        XCTAssertEqual(cache.value(for: 1), "one")
        cache.insert("three", for: 3, byteCount: 10)

        XCTAssertEqual(cache.value(for: 1), "one")
        XCTAssertNil(cache.value(for: 2))
        XCTAssertEqual(cache.value(for: 3), "three")
    }

    func testCacheEvictsUntilByteLimitAndRejectsOversizedEntry() {
        var cache = PlaybackTimelinePreviewCache<Int, String>(maximumCount: 24, maximumBytes: 20)
        cache.insert("one", for: 1, byteCount: 12)
        cache.insert("two", for: 2, byteCount: 12)
        XCTAssertNil(cache.value(for: 1))
        XCTAssertEqual(cache.value(for: 2), "two")

        cache.insert("oversized", for: 3, byteCount: 21)
        XCTAssertNil(cache.value(for: 3))
    }

    func testLowPowerConfigurationUsesLongerDebounceAndEightFrames() {
        XCTAssertEqual(PlaybackTimelinePreviewConfiguration(isLowPowerModeEnabled: false).debounce, .milliseconds(250))
        XCTAssertEqual(PlaybackTimelinePreviewConfiguration(isLowPowerModeEnabled: false).maximumFrameCount, 24)
        XCTAssertEqual(PlaybackTimelinePreviewConfiguration(isLowPowerModeEnabled: true).debounce, .milliseconds(500))
        XCTAssertEqual(PlaybackTimelinePreviewConfiguration(isLowPowerModeEnabled: true).maximumFrameCount, 8)
    }
}
```

- [ ] **Step 2: Run the test and verify missing types fail compilation**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test \
  -only-testing:OmniaTests/PlaybackTimelinePreviewTests
```

Expected: compilation fails because the preview types do not exist.

- [ ] **Step 3: Implement the pure preview types**

Create `PlaybackTimelinePreview.swift` with:

```swift
import Foundation

nonisolated struct PlaybackStoryboardCrop: Hashable, Sendable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

nonisolated struct PlaybackStoryboardTile: Hashable, Sendable {
    let startTime: Double
    let endTime: Double
    let imageURL: URL
    let crop: PlaybackStoryboardCrop?

    func contains(_ timestamp: Double) -> Bool {
        startTime <= timestamp && timestamp < endTime
    }
}

nonisolated struct PlaybackStoryboardDescriptor: Hashable, Sendable {
    let allowedOriginURL: URL
    let tiles: [PlaybackStoryboardTile]
}

nonisolated enum PlaybackTimelinePreviewDescriptor: Hashable, Sendable {
    case storyboard(PlaybackStoryboardDescriptor)
}

nonisolated struct PlaybackTimelinePreviewConfiguration: Equatable, Sendable {
    static let maximumBytes = 8 * 1_024 * 1_024
    let debounce: Duration
    let maximumFrameCount: Int
    let maximumBytes: Int

    init(isLowPowerModeEnabled: Bool) {
        debounce = isLowPowerModeEnabled ? .milliseconds(500) : .milliseconds(250)
        maximumFrameCount = isLowPowerModeEnabled ? 8 : 24
        maximumBytes = Self.maximumBytes
    }
}

nonisolated enum PlaybackTimelinePreviewPosition {
    static func timestamp(x: Double, width: Double, duration: Double) -> Double? {
        guard width.isFinite, width > 0, duration.isFinite, duration > 0 else { return nil }
        return min(max(x / width, 0), 1) * duration
    }
}

nonisolated struct PlaybackTimelinePreviewCache<Key: Hashable, Value> {
    private struct Entry {
        let value: Value
        let byteCount: Int
        var access: UInt64
    }

    private let maximumCount: Int
    private let maximumBytes: Int
    private var entries: [Key: Entry] = [:]
    private var access: UInt64 = 0
    private var byteCount = 0

    init(maximumCount: Int, maximumBytes: Int) {
        self.maximumCount = max(maximumCount, 1)
        self.maximumBytes = max(maximumBytes, 1)
    }

    mutating func value(for key: Key) -> Value? {
        guard var entry = entries[key] else { return nil }
        access &+= 1
        entry.access = access
        entries[key] = entry
        return entry.value
    }

    mutating func insert(_ value: Value, for key: Key, byteCount: Int) {
        guard byteCount > 0, byteCount <= maximumBytes else { return }
        if let old = entries.removeValue(forKey: key) { self.byteCount -= old.byteCount }
        access &+= 1
        entries[key] = Entry(value: value, byteCount: byteCount, access: access)
        self.byteCount += byteCount
        while entries.count > maximumCount || self.byteCount > maximumBytes {
            guard let oldest = entries.min(by: { $0.value.access < $1.value.access }) else { break }
            self.byteCount -= oldest.value.byteCount
            entries.removeValue(forKey: oldest.key)
        }
    }

    mutating func removeAll() {
        entries.removeAll(keepingCapacity: false)
        byteCount = 0
    }
}
```

Add `let timelinePreviewDescriptor: PlaybackTimelinePreviewDescriptor?` to `PlaybackSource`. Give both production initializers an optional parameter defaulted to `nil`, assign it, and keep every existing call source-compatible:

```swift
init(
    candidate: AddonStreamCandidate,
    url: URL,
    timelinePreviewDescriptor: PlaybackTimelinePreviewDescriptor? = nil
) {
    // existing assignments
    self.timelinePreviewDescriptor = timelinePreviewDescriptor
}
```

Do the same for the local-candidate initializer. Current Stremio candidates pass `nil`; no undocumented behavior-hint field is decoded.

Under the existing `#if DEBUG`, add an internal deterministic constructor for tests:

```swift
init(
    previewID: String,
    url: URL,
    requestHeaders: [String: String] = [:],
    timelinePreviewDescriptor: PlaybackTimelinePreviewDescriptor? = nil
) {
    id = previewID
    addonID = "omnia.tests"
    addonName = "Omnia Tests"
    title = "Test Source"
    detail = nil
    streamIdentifier = previewID
    self.url = url
    self.requestHeaders = requestHeaders
    self.timelinePreviewDescriptor = timelinePreviewDescriptor
}
```

- [ ] **Step 4: Run tests and commit the model slice**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test \
  -only-testing:OmniaTests/PlaybackTimelinePreviewTests
git diff --check
git add Omnia/Domain/Playback/PlaybackTimelinePreview.swift \
  Omnia/Domain/Playback/PlaybackSource.swift \
  OmniaTests/PlaybackTimelinePreviewTests.swift
git commit -m "Define bounded timeline preview models"
```

Expected: tests pass and only the three listed files are committed.

---

### Task 3: Parse and securely load explicit storyboard and HLS image resources

**Files:**
- Modify: `Omnia/Data/Networking/HTTPTransport.swift`
- Create: `Omnia/Data/Playback/HLSImagePlaylist.swift`
- Create: `Omnia/Platform/macOS/StoryboardFrameLoader.swift`
- Test: `OmniaTests/HTTPTransportTests.swift`
- Test: `OmniaTests/HLSImagePlaylistTests.swift`
- Test: `OmniaTests/StoryboardFrameLoaderTests.swift`

**Interfaces:**
- Consumes: `HTTPTransporting`, exact normalized origins, source request headers, HLS text, storyboard tiles.
- Produces:
  - `HTTPRequestPolicy.requestHeaders`
  - `HLSImagePlaylistParser.imagePlaylistURL(data:baseURL:)`
  - `HLSImagePlaylistParser.storyboard(data:playlistURL:allowedOriginURL:)`
  - `PlaybackTimelinePreviewImage`
  - `StoryboardFrameLoader.image(for:descriptor:transport:requestHeaders:)`

- [ ] **Step 1: Write failing request-header policy tests**

In `HTTPTransportTests.swift`, add:

```swift
func testPolicyKeepsBoundedSafeHeadersAndDropsUnsafeOnes() throws {
    let url = try XCTUnwrap(URL(string: "https://media.example/master.m3u8"))
    let origin = try XCTUnwrap(NormalizedOrigin(url: url))
    let policy = HTTPRequestPolicy(
        url: url,
        allowedOrigin: origin,
        timeout: 5,
        maximumResponseBytes: 1_024,
        acceptedContentTypes: ["application/vnd.apple.mpegurl"],
        requestHeaders: [
            "Authorization": "Bearer token",
            "User-Agent": "Omnia",
            "Host": "attacker.example",
            "Range": "bytes=0-10",
            "X-Bad": "one\r\ntwo"
        ]
    )

    XCTAssertEqual(policy.requestHeaders["Authorization"], "Bearer token")
    XCTAssertEqual(policy.requestHeaders["User-Agent"], "Omnia")
    XCTAssertNil(policy.requestHeaders["Host"])
    XCTAssertNil(policy.requestHeaders["Range"])
    XCTAssertNil(policy.requestHeaders["X-Bad"])
}
```

- [ ] **Step 2: Extend `HTTPRequestPolicy` without changing existing callers**

Add a stored property and defaulted initializer parameter:

```swift
let requestHeaders: [String: String]

// initializer parameter
requestHeaders: [String: String] = [:]
```

Normalize it in the initializer:

```swift
let forbidden = Set(["host", "connection", "content-length", "range"])
self.requestHeaders = requestHeaders.reduce(into: [:]) { result, entry in
    let name = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
    let value = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty,
          name.utf8.count <= 256,
          value.utf8.count <= 8_192,
          !forbidden.contains(name.lowercased()),
          !name.contains("\r"), !name.contains("\n"),
          !value.contains("\r"), !value.contains("\n") else { return }
    result[name] = value
}
```

In `HTTPTransport.data(for:)`, apply those values after building the GET request:

```swift
for (name, value) in policy.requestHeaders {
    request.setValue(value, forHTTPHeaderField: name)
}
```

The existing redirect delegate already restricts redirects to the exact `allowedOrigin`.

- [ ] **Step 3: Write failing deterministic HLS parser tests**

Create `HLSImagePlaylistTests.swift` with same-origin and rejection cases:

```swift
func testParsesImageStreamAndTileTimeline() throws {
    let masterURL = try XCTUnwrap(URL(string: "https://media.example/master.m3u8"))
    let master = Data("""
    #EXTM3U
    #EXT-X-IMAGE-STREAM-INF:BANDWIDTH=20000,CODECS="jpeg",RESOLUTION=320x180,URI="images/index.m3u8"
    """.utf8)
    XCTAssertEqual(
        try HLSImagePlaylistParser.imagePlaylistURL(data: master, baseURL: masterURL),
        URL(string: "https://media.example/images/index.m3u8")
    )

    let playlistURL = try XCTUnwrap(URL(string: "https://media.example/images/index.m3u8"))
    let playlist = Data("""
    #EXTM3U
    #EXT-X-TARGETDURATION:10
    #EXTINF:10.0,
    #EXT-X-TILES:RESOLUTION=160x90,LAYOUT=5x2,DURATION=1.0
    sheet-0.jpg
    """.utf8)
    let storyboard = try HLSImagePlaylistParser.storyboard(
        data: playlist,
        playlistURL: playlistURL,
        allowedOriginURL: masterURL
    )

    XCTAssertEqual(storyboard.tiles.count, 10)
    XCTAssertEqual(storyboard.tiles[6].startTime, 6)
    XCTAssertEqual(storyboard.tiles[6].crop, PlaybackStoryboardCrop(x: 160, y: 90, width: 160, height: 90))
}

func testRejectsNonHTTPSAndCrossOriginHLSResources() throws {
    let httpsBase = try XCTUnwrap(URL(string: "https://media.example/master.m3u8"))
    let nonHTTPS = Data("#EXTM3U\n#EXT-X-IMAGE-STREAM-INF:URI=\"http://media.example/image.m3u8\"".utf8)
    let crossOrigin = Data("#EXTM3U\n#EXT-X-IMAGE-STREAM-INF:URI=\"https://other.example/image.m3u8\"".utf8)

    XCTAssertThrowsError(try HLSImagePlaylistParser.imagePlaylistURL(data: nonHTTPS, baseURL: httpsBase))
    XCTAssertThrowsError(try HLSImagePlaylistParser.imagePlaylistURL(data: crossOrigin, baseURL: httpsBase))
}

func testRejectsMalformedOrUnboundedTileDeclarations() throws {
    let url = try XCTUnwrap(URL(string: "https://media.example/images.m3u8"))
    let tooMany = Data("""
    #EXTM3U
    #EXTINF:10,
    #EXT-X-TILES:RESOLUTION=160x90,LAYOUT=100x100,DURATION=0.001
    sheet.jpg
    """.utf8)
    XCTAssertThrowsError(
        try HLSImagePlaylistParser.storyboard(data: tooMany, playlistURL: url, allowedOriginURL: url)
    )
}
```

- [ ] **Step 4: Implement the bounded HLS parser**

Create `HLSImagePlaylist.swift` with `HLSImagePlaylistError` cases `invalidUTF8`, `missingImagePlaylist`, `insecureURL`, `originRejected`, `malformed`, and `boundsExceeded`.

The parser must enforce these constants:

```swift
static let maximumManifestBytes = 512 * 1_024
static let maximumTiles = 10_000
static let maximumSheetDimension = 8_192
static let maximumTileDimension = 640
```

Parse quoted attribute lists without splitting commas inside quotes. Resolve relative URIs against the manifest URL, require `https`, and require `NormalizedOrigin(url: resolved) == NormalizedOrigin(url: allowedOriginURL)`.

For each image-media segment, pair the preceding `#EXTINF` and `#EXT-X-TILES` with its URI. Convert row-major tile coordinates into `PlaybackStoryboardTile` entries:

```swift
let index = row * columns + column
let start = cumulativeSegmentStart + min(Double(index) * tileDuration, segmentDuration)
let end = min(start + tileDuration, cumulativeSegmentStart + segmentDuration)
let crop = PlaybackStoryboardCrop(
    x: column * tileWidth,
    y: row * tileHeight,
    width: tileWidth,
    height: tileHeight
)
```

Discard zero-length trailing tiles. Reject non-finite/non-positive durations, dimensions outside the constants, layouts above 100 columns or rows, and total tiles above 10,000. This first implementation loads complete bounded JPEG/PNG sheet resources and rejects `#EXT-X-BYTERANGE`; it must not issue implicit unbounded range requests.

- [ ] **Step 5: Write failing image bounds and crop tests**

Create `StoryboardFrameLoaderTests.swift`. Use the test file's fixed 2x1 PNG base64 fixture and a recording `HTTPTransporting` actor:

```swift
private let twoPixelPNG = Data(base64Encoded:
    "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAFElEQVR42mP4z8DwH4QZGBgYGJgAAAwBAf8CBTYAAAAASUVORK5CYII="
)!
```

Assert that a same-origin tile returns an image no larger than 320x180, that the policy uses at most 4 MiB and accepts only `image/jpeg`/`image/png`, and that non-HTTPS/cross-origin descriptors throw before transport is called. Add a decoder test whose stub returns non-image bytes and expect `StoryboardFrameLoaderError.invalidImage`.

Add a transport-failure test so redirects cannot be swallowed into image decoding:

```swift
func testRedirectRejectedStoryboardImageIsRejected() async throws {
    let url = try XCTUnwrap(URL(string: "https://media.example/sheet.jpg"))
    let descriptor = PlaybackStoryboardDescriptor(
        allowedOriginURL: url,
        tiles: [.init(startTime: 0, endTime: 10, imageURL: url, crop: nil)]
    )
    let transport = FailingStoryboardTransport(error: .redirectRejected)

    do {
        _ = try await StoryboardFrameLoader.image(
            for: 1,
            descriptor: descriptor,
            transport: transport,
            requestHeaders: [:]
        )
        XCTFail("Expected redirect rejection")
    } catch {
        XCTAssertEqual(error as? HTTPTransportError, .redirectRejected)
    }
}

private actor FailingStoryboardTransport: HTTPTransporting {
    let error: HTTPTransportError
    init(error: HTTPTransportError) { self.error = error }
    func data(for policy: HTTPRequestPolicy) async throws -> Data { throw error }
}
```

- [ ] **Step 6: Implement bounded image fetch, decode, crop, and downscale**

Create `StoryboardFrameLoader.swift` importing AppKit and ImageIO. Implement:

```swift
struct PlaybackTimelinePreviewImage: @unchecked Sendable {
    let image: NSImage
    let byteCount: Int
}

enum StoryboardFrameLoader {
    static let maximumImageBytes = 4 * 1_024 * 1_024
    static let maximumSourceDimension = 8_192
    static let outputSize = CGSize(width: 320, height: 180)

    static func image(
        for timestamp: Double,
        descriptor: PlaybackStoryboardDescriptor,
        transport: any HTTPTransporting,
        requestHeaders: [String: String]
    ) async throws -> PlaybackTimelinePreviewImage
}
```

Select the tile containing the timestamp, falling back to the last tile only when timestamp equals the descriptor's final end time. Validate descriptor and tile origin before fetching with:

```swift
HTTPRequestPolicy(
    url: tile.imageURL,
    allowedOrigin: allowedOrigin,
    timeout: 8,
    maximumResponseBytes: maximumImageBytes,
    acceptedContentTypes: ["image/jpeg", "image/png"],
    requestHeaders: requestHeaders
)
```

Call `Task.checkCancellation()` before fetch, after fetch, and after decode. Use `CGImageSourceCopyPropertiesAtIndex` to reject width/height over 8,192 before full decode, crop with `cgImage.cropping(to:)`, and draw aspect-fill into a 320x180 bitmap context. Return `PlaybackTimelinePreviewImage(image: NSImage(cgImage:size:), byteCount: 320 * 180 * 4)`; never retain the full source sheet after return.

- [ ] **Step 7: Run security/parser/image tests and commit**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test \
  -only-testing:OmniaTests/HTTPTransportTests \
  -only-testing:OmniaTests/HLSImagePlaylistTests \
  -only-testing:OmniaTests/StoryboardFrameLoaderTests
git diff --check
git add Omnia/Data/Networking/HTTPTransport.swift \
  Omnia/Data/Playback/HLSImagePlaylist.swift \
  Omnia/Platform/macOS/StoryboardFrameLoader.swift \
  OmniaTests/HTTPTransportTests.swift \
  OmniaTests/HLSImagePlaylistTests.swift \
  OmniaTests/StoryboardFrameLoaderTests.swift
git commit -m "Load bounded timeline storyboards"
```

Expected: all focused tests pass; no request can leave its exact normalized origin.

---

### Task 4: Build the isolated libmpv frame generator

**Files:**
- Create: `Omnia/Platform/Playback/MPVThumbnailGenerator.h`
- Create: `Omnia/Platform/Playback/MPVThumbnailGenerator.m`
- Modify: `Omnia/Omnia-Bridging-Header.h`
- Test: `OmniaTests/MPVPlaybackIntegrationTests.swift`

**Interfaces:**
- Consumes: validated source URL/headers and libmpv `seekable`, `seek`, `MPV_EVENT_PLAYBACK_RESTART`, and `screenshot-raw`.
- Produces:
  - `OMMpvThumbnailGenerator.init(url:requestHeaders:)`
  - `requestFrame(at:maximumSize:completion:) -> UInt64`
  - `cancelPendingRequest()`
  - `stop()`

- [ ] **Step 1: Write a failing integration test using the deterministic local fixture**

Add to `MPVPlaybackIntegrationTests.swift`:

```swift
@MainActor
func testThumbnailGeneratorReturnsBoundedFrameWithoutPlayerView() throws {
    let fixtureURL = try XCTUnwrap(
        Bundle(for: Self.self).url(forResource: "multi-track", withExtension: "mkv")
    )
    let generator = OMMpvThumbnailGenerator(url: fixtureURL, requestHeaders: [:])
    defer { generator.stop() }
    var result: Result<NSImage, Error>?

    generator.requestFrame(at: 0.5, maximumSize: NSSize(width: 320, height: 180)) { image, error in
        if let image { result = .success(image) }
        else { result = .failure(error ?? NSError(domain: "OmniaTests", code: 1)) }
    }
    waitUntil { result != nil }

    let image = try XCTUnwrap(try result?.get())
    XCTAssertLessThanOrEqual(image.size.width, 320)
    XCTAssertLessThanOrEqual(image.size.height, 180)
}

@MainActor
func testThumbnailGeneratorCancelsSupersededRequest() throws {
    let fixtureURL = try XCTUnwrap(
        Bundle(for: Self.self).url(forResource: "multi-track", withExtension: "mkv")
    )
    let generator = OMMpvThumbnailGenerator(url: fixtureURL, requestHeaders: [:])
    defer { generator.stop() }
    var firstError: Error?
    var secondImage: NSImage?

    _ = generator.requestFrame(at: 0.1, maximumSize: NSSize(width: 320, height: 180)) { _, error in
        firstError = error
    }
    _ = generator.requestFrame(at: 0.8, maximumSize: NSSize(width: 320, height: 180)) { image, _ in
        secondImage = image
    }
    waitUntil { firstError != nil && secondImage != nil }

    XCTAssertEqual((firstError as NSError?)?.domain, "OMMpvThumbnailErrorDomain")
    XCTAssertNotNil(secondImage)
}
```

- [ ] **Step 2: Run integration tests and verify the missing class fails compilation**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test \
  -only-testing:OmniaTests/MPVPlaybackIntegrationTests
```

Expected: compilation fails because `OMMpvThumbnailGenerator` is undefined.

- [ ] **Step 3: Declare the Objective-C API and bridge it to Swift**

In `MPVThumbnailGenerator.h`:

```objc
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^OMMpvThumbnailCompletion)(
    NSImage * _Nullable image,
    NSError * _Nullable error
);

@interface OMMpvThumbnailGenerator : NSObject
- (instancetype)initWithURL:(NSURL *)URL
             requestHeaders:(NSDictionary<NSString *, NSString *> *)requestHeaders
    NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (uint64_t)requestFrameAt:(double)seconds
               maximumSize:(NSSize)maximumSize
                completion:(OMMpvThumbnailCompletion)completion
    NS_SWIFT_NAME(requestFrame(at:maximumSize:completion:));
- (void)cancelPendingRequest;
- (void)stop;
@end

NS_ASSUME_NONNULL_END
```

Import it from `Omnia-Bridging-Header.h`:

```objc
#import "Platform/Playback/MPVThumbnailGenerator.h"
```

- [ ] **Step 4: Initialize one headless, low-priority libmpv core**

In `MPVThumbnailGenerator.m`, own a serial queue with `QOS_CLASS_UTILITY`, an `mpv_handle *`, the copied source URL/headers, a monotonic request ID, one pending completion, and state for file-loaded/seekable/requested timestamp.

On the serial queue configure exactly:

```objc
mpv_set_option_string(mpv, "config", "no");
mpv_set_option_string(mpv, "terminal", "no");
mpv_set_option_string(mpv, "load-scripts", "no");
mpv_set_option_string(mpv, "audio", "no");
mpv_set_option_string(mpv, "ao", "null");
mpv_set_option_string(mpv, "vo", "null");
mpv_set_option_string(mpv, "pause", "yes");
mpv_set_option_string(mpv, "keep-open", "yes");
mpv_set_option_string(mpv, "hwdec", "auto-safe");
mpv_set_option_string(mpv, "hr-seek", "yes");
mpv_set_option_string(mpv, "ytdl", "no");
```

Apply only the already-sanitized source request headers as `http-header-fields`, initialize, install a wakeup callback that dispatches back to the utility queue, then issue `loadfile` for the selected source. The class creates no `NSView`, OpenGL context, audio output, timer, or visible video output.

- [ ] **Step 5: Seek one request and capture `screenshot-raw`**

When `MPV_EVENT_FILE_LOADED` arrives, read `seekable` as `MPV_FORMAT_FLAG`. If false, complete with a fixed `OMMpvThumbnailErrorDomain` error and stop the core. If true and a request is pending, issue:

```objc
const char *seek[] = { "seek", secondsString.UTF8String, "absolute+exact", NULL };
mpv_command_async(_mpv, requestID, seek);
```

After the corresponding seek reply and the next `MPV_EVENT_PLAYBACK_RESTART`, request the frame with `mpv_command_node_async`. Build a node array equivalent to:

```text
["screenshot-raw", "video", "bgra"]
```

On `MPV_EVENT_COMMAND_REPLY`, require a node map containing finite positive `w`, `h`, `stride`, `format == "bgra"`, and byte-array `data`. Reject dimensions above 8,192 and byte counts above 256 MiB before copying. Copy rows while the event node is alive, respecting positive or negative stride, into an `NSBitmapImageRep`, then downscale aspect-fill to the requested maximum size. Dispatch the final completion to the main queue.

Use fixed error descriptions only:

```text
Timeline preview is unavailable for this source.
The preview frame could not be decoded.
Timeline preview was cancelled.
```

- [ ] **Step 6: Make supersession and shutdown deterministic**

`requestFrameAt` increments a generation. Before replacing a prior pending completion, call it once on the main queue with the fixed cancellation error; this ensures Swift continuations always resume. If an async libmpv command is outstanding, call `mpv_abort_async_command` for its request ID. Ignore any later reply whose `reply_userdata` does not equal the current generation.

`cancelPendingRequest` performs the same abort, clears copied frame state, and leaves the initialized core ready only until `stop`. `stop` dispatches synchronously when called off-queue, clears callbacks, calls `mpv_terminate_destroy`, and nils the core. It is idempotent. `dealloc` calls `stop`.

- [ ] **Step 7: Run integration tests and commit the generator**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test \
  -only-testing:OmniaTests/MPVPlaybackIntegrationTests
git diff --check
git add Omnia/Platform/Playback/MPVThumbnailGenerator.h \
  Omnia/Platform/Playback/MPVThumbnailGenerator.m \
  Omnia/Omnia-Bridging-Header.h \
  OmniaTests/MPVPlaybackIntegrationTests.swift
git commit -m "Generate isolated timeline preview frames"
```

Expected: the frame is bounded, the superseded completion is not published, and no window/video surface is created.

---

### Task 5: Resolve source order and cache one-frame requests

**Files:**
- Create: `Omnia/Platform/macOS/PlaybackTimelinePreviewService.swift`
- Test: `OmniaTests/PlaybackTimelinePreviewServiceTests.swift`

**Interfaces:**
- Consumes: Tasks 2-4 types/loaders plus selected `PlaybackSource`.
- Produces:
  - `PlaybackTimelinePreviewFrame`
  - `PlaybackTimelinePreviewService.frame(at:) async -> PlaybackTimelinePreviewFrame?`
  - `PlaybackTimelinePreviewService.stop()`

- [ ] **Step 1: Write failing source-order, cache, cancellation, and stale-key tests**

Create `PlaybackTimelinePreviewServiceTests.swift` with actor stubs implementing these internal protocols:

```swift
protocol PlaybackStoryboardLoading: Sendable {
    func hlsStoryboard(for source: PlaybackSource) async throws -> PlaybackStoryboardDescriptor?
    func image(at timestamp: Double, descriptor: PlaybackStoryboardDescriptor, source: PlaybackSource) async throws -> PlaybackTimelinePreviewImage
}

protocol PlaybackLocalFrameGenerating: Sendable {
    func image(at timestamp: Double, source: PlaybackSource) async throws -> PlaybackTimelinePreviewImage
    func stop() async
}
```

Add these deterministic tests using `PreviewStoryboardLoaderStub` and `PreviewLocalGeneratorStub` actors that count each call and return injected `PlaybackTimelinePreviewImage` values:

```swift
func testExplicitStoryboardWinsWithoutStartingHLSOrLocalGenerator() async throws {
    let descriptor = makeStoryboard(sourceID: "explicit")
    let source = makeSource(id: "explicit", descriptor: .storyboard(descriptor))
    let storyboard = PreviewStoryboardLoaderStub(hlsDescriptor: makeStoryboard(sourceID: "hls"))
    let local = PreviewLocalGeneratorStub()
    let service = PlaybackTimelinePreviewService(
        source: source,
        configuration: .init(isLowPowerModeEnabled: false),
        storyboardLoader: storyboard,
        localGenerator: local
    )

    let frame = await service.frame(at: 1)

    let hlsRequestCount = await storyboard.hlsRequestCount
    let imageRequestCount = await storyboard.imageRequestCount
    let localRequestCount = await local.imageRequestCount
    XCTAssertEqual(frame?.sourceID, "explicit")
    XCTAssertEqual(hlsRequestCount, 0)
    XCTAssertEqual(imageRequestCount, 1)
    XCTAssertEqual(localRequestCount, 0)
}

func testHLSStoryboardWinsWhenExplicitDescriptorIsAbsent() async throws {
    let source = makeSource(id: "hls", descriptor: nil)
    let storyboard = PreviewStoryboardLoaderStub(hlsDescriptor: makeStoryboard(sourceID: "hls"))
    let local = PreviewLocalGeneratorStub()
    let service = PlaybackTimelinePreviewService(
        source: source,
        configuration: .init(isLowPowerModeEnabled: false),
        storyboardLoader: storyboard,
        localGenerator: local
    )

    let frame = await service.frame(at: 2)
    let hlsRequestCount = await storyboard.hlsRequestCount
    let imageRequestCount = await storyboard.imageRequestCount
    let localRequestCount = await local.imageRequestCount
    XCTAssertNotNil(frame)
    XCTAssertEqual(hlsRequestCount, 1)
    XCTAssertEqual(imageRequestCount, 1)
    XCTAssertEqual(localRequestCount, 0)
}

func testLocalGeneratorRunsWhenStoryboardSourcesAreUnavailable() async throws {
    let source = makeSource(id: "local", descriptor: nil)
    let storyboard = PreviewStoryboardLoaderStub(hlsDescriptor: nil)
    let local = PreviewLocalGeneratorStub()
    let service = PlaybackTimelinePreviewService(
        source: source,
        configuration: .init(isLowPowerModeEnabled: false),
        storyboardLoader: storyboard,
        localGenerator: local
    )

    let frame = await service.frame(at: 3)
    let localRequestCount = await local.imageRequestCount
    XCTAssertNotNil(frame)
    XCTAssertEqual(localRequestCount, 1)
}

func testRepeatedTimestampUsesCachedFrame() async throws {
    let source = makeSource(id: "cache", descriptor: nil)
    let local = PreviewLocalGeneratorStub()
    let service = PlaybackTimelinePreviewService(
        source: source,
        configuration: .init(isLowPowerModeEnabled: false),
        storyboardLoader: PreviewStoryboardLoaderStub(hlsDescriptor: nil),
        localGenerator: local
    )

    _ = await service.frame(at: 120.2)
    _ = await service.frame(at: 120.8)

    let localRequestCount = await local.imageRequestCount
    XCTAssertEqual(localRequestCount, 1)
}

func testCacheKeyIncludesSourceIdentity() {
    XCTAssertNotEqual(
        PlaybackTimelinePreviewCacheKey(sourceID: "a", timestampBucket: 10),
        PlaybackTimelinePreviewCacheKey(sourceID: "b", timestampBucket: 10)
    )
}

func testCancelledRequestDoesNotReturnAFrame() async throws {
    let gate = PreviewGenerationGate()
    let local = PreviewLocalGeneratorStub(gate: gate)
    let service = PlaybackTimelinePreviewService(
        source: makeSource(id: "cancel", descriptor: nil),
        configuration: .init(isLowPowerModeEnabled: false),
        storyboardLoader: PreviewStoryboardLoaderStub(hlsDescriptor: nil),
        localGenerator: local
    )
    let first = Task { await service.frame(at: 10) }
    await gate.waitUntilRequested()
    let second = Task { await service.frame(at: 20) }
    await gate.release()

    let firstValue = await first.value
    let secondValue = await second.value
    XCTAssertNil(firstValue)
    XCTAssertNotNil(secondValue)
}

func testStopClearsCacheAndStopsLocalGenerator() async throws {
    let local = PreviewLocalGeneratorStub()
    let service = PlaybackTimelinePreviewService(
        source: makeSource(id: "stop", descriptor: nil),
        configuration: .init(isLowPowerModeEnabled: false),
        storyboardLoader: PreviewStoryboardLoaderStub(hlsDescriptor: nil),
        localGenerator: local
    )
    _ = await service.frame(at: 1)
    await service.stop()

    let stopCount = await local.stopCount
    let frameAfterStop = await service.frame(at: 1)
    XCTAssertEqual(stopCount, 1)
    XCTAssertNil(frameAfterStop)
}
```

Add these test helpers below the test case. They return a 320x180 image with a 230,400-byte decoded cost and use checked continuations instead of wall-clock sleeps:

```swift
private actor PreviewGenerationGate {
    private var requested = false
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func suspend() async {
        requested = true
        requestWaiters.forEach { $0.resume() }
        requestWaiters.removeAll()
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilRequested() async {
        if requested { return }
        await withCheckedContinuation { requestWaiters.append($0) }
    }

    func release() {
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

private actor PreviewStoryboardLoaderStub: PlaybackStoryboardLoading {
    let hlsDescriptor: PlaybackStoryboardDescriptor?
    private(set) var hlsRequestCount = 0
    private(set) var imageRequestCount = 0

    init(hlsDescriptor: PlaybackStoryboardDescriptor?) {
        self.hlsDescriptor = hlsDescriptor
    }

    func hlsStoryboard(for source: PlaybackSource) async throws -> PlaybackStoryboardDescriptor? {
        hlsRequestCount += 1
        return hlsDescriptor
    }

    func image(
        at timestamp: Double,
        descriptor: PlaybackStoryboardDescriptor,
        source: PlaybackSource
    ) async throws -> PlaybackTimelinePreviewImage {
        imageRequestCount += 1
        return makePreviewImage()
    }
}

private actor PreviewLocalGeneratorStub: PlaybackLocalFrameGenerating {
    private let gate: PreviewGenerationGate?
    private(set) var imageRequestCount = 0
    private(set) var stopCount = 0

    init(gate: PreviewGenerationGate? = nil) { self.gate = gate }

    func image(at timestamp: Double, source: PlaybackSource) async throws -> PlaybackTimelinePreviewImage {
        imageRequestCount += 1
        if imageRequestCount == 1, let gate { await gate.suspend() }
        try Task.checkCancellation()
        return makePreviewImage()
    }

    func stop() async { stopCount += 1 }
}

private func makePreviewImage() -> PlaybackTimelinePreviewImage {
    PlaybackTimelinePreviewImage(
        image: NSImage(size: NSSize(width: 320, height: 180)),
        byteCount: 320 * 180 * 4
    )
}

private func makeStoryboard(sourceID: String) -> PlaybackStoryboardDescriptor {
    let url = URL(string: "https://media.example/\(sourceID).jpg")!
    return PlaybackStoryboardDescriptor(
        allowedOriginURL: url,
        tiles: [.init(startTime: 0, endTime: 60, imageURL: url, crop: nil)]
    )
}

private func makeSource(
    id: String,
    descriptor: PlaybackTimelinePreviewDescriptor?
) -> PlaybackSource {
    PlaybackSource(
        previewID: id,
        url: URL(string: "https://media.example/video.m3u8")!,
        timelinePreviewDescriptor: descriptor
    )
}
```

Before assertions on actor-isolated counters, assign the awaited value to a local, then pass the local to `XCTAssertEqual`; XCTest autoclosures do not accept `await`. Use timestamp cache keys rounded to the descriptor tile start time for storyboard frames and down to whole seconds for local frames.

- [ ] **Step 2: Run the service tests and verify missing types fail**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test \
  -only-testing:OmniaTests/PlaybackTimelinePreviewServiceTests
```

Expected: compilation fails because the service/protocols are undefined.

- [ ] **Step 3: Implement production loader adapters**

In `PlaybackTimelinePreviewService.swift`, import AppKit and define the two protocols exactly as in Step 1.

Implement `DefaultPlaybackStoryboardLoader` so `hlsStoryboard(for:)` returns nil unless the selected URL path extension is `m3u8`. Fetch master and image playlists through `HTTPTransport` with exact source origin, `timeout: 8`, `maximumResponseBytes: 512 * 1_024`, accepted content types `application/vnd.apple.mpegurl`, `application/x-mpegurl`, and `audio/mpegurl`, plus `source.requestHeaders`. Parse them with Task 3 and load frame images with `StoryboardFrameLoader`.

Implement `MPVLocalFrameGenerator` as an actor. Lazily create one `OMMpvThumbnailGenerator` per source ID and bridge its callback through `withTaskCancellationHandler` plus `withCheckedThrowingContinuation`. On cancellation call `cancelPendingRequest`; on `stop`, stop and release the native generator.

- [ ] **Step 4: Implement the actor, ordered fallbacks, and bounded cache**

Define:

```swift
struct PlaybackTimelinePreviewFrame: @unchecked Sendable {
    let sourceID: String
    let timestamp: Double
    let image: NSImage
    let byteCount: Int
}

struct PlaybackTimelinePreviewCacheKey: Hashable, Sendable {
    let sourceID: String
    let timestampBucket: Int
}

actor PlaybackTimelinePreviewService {
    private let source: PlaybackSource
    private let storyboardLoader: any PlaybackStoryboardLoading
    private let localGenerator: any PlaybackLocalFrameGenerating
    private var cache: PlaybackTimelinePreviewCache<PlaybackTimelinePreviewCacheKey, PlaybackTimelinePreviewFrame>
    private var inFlight: Task<PlaybackTimelinePreviewFrame?, Never>?
    private var requestGeneration: UInt64 = 0
    private var stopped = false

    init(
        source: PlaybackSource,
        configuration: PlaybackTimelinePreviewConfiguration,
        storyboardLoader: any PlaybackStoryboardLoading = DefaultPlaybackStoryboardLoader(),
        localGenerator: any PlaybackLocalFrameGenerating = MPVLocalFrameGenerator()
    ) {
        self.source = source
        self.storyboardLoader = storyboardLoader
        self.localGenerator = localGenerator
        cache = .init(
            maximumCount: configuration.maximumFrameCount,
            maximumBytes: configuration.maximumBytes
        )
    }

    func frame(at timestamp: Double) async -> PlaybackTimelinePreviewFrame? {
        guard !stopped, timestamp.isFinite, timestamp >= 0 else { return nil }
        requestGeneration &+= 1
        let generation = requestGeneration
        inFlight?.cancel()
        let task = Task { [source, storyboardLoader, localGenerator] in
            let explicit = source.timelinePreviewDescriptor.flatMap { descriptor -> PlaybackStoryboardDescriptor? in
                guard case let .storyboard(storyboard) = descriptor else { return nil }
                return storyboard
            }
            if let explicit,
               let loaded = try? await storyboardLoader.image(
                   at: timestamp,
                   descriptor: explicit,
                   source: source
               ) {
                return Self.frame(source: source, timestamp: timestamp, loaded: loaded)
            }
            if let hls = try? await storyboardLoader.hlsStoryboard(for: source),
               let loaded = try? await storyboardLoader.image(
                   at: timestamp,
                   descriptor: hls,
                   source: source
               ) {
                return Self.frame(source: source, timestamp: timestamp, loaded: loaded)
            }
            guard let loaded = try? await localGenerator.image(at: timestamp, source: source) else {
                return nil
            }
            return Self.frame(source: source, timestamp: timestamp, loaded: loaded)
        }
        inFlight = task
        guard let result = await task.value,
              !Task.isCancelled,
              !stopped,
              generation == requestGeneration else { return nil }
        let key = PlaybackTimelinePreviewCacheKey(
            sourceID: source.id,
            timestampBucket: Int(result.timestamp.rounded(.down))
        )
        cache.insert(result, for: key, byteCount: result.byteCount)
        return result
    }

    func stop() async {
        stopped = true
        requestGeneration &+= 1
        inFlight?.cancel()
        inFlight = nil
        cache.removeAll()
        await localGenerator.stop()
    }

    private nonisolated static func frame(
        source: PlaybackSource,
        timestamp: Double,
        loaded: PlaybackTimelinePreviewImage
    ) -> PlaybackTimelinePreviewFrame {
        PlaybackTimelinePreviewFrame(
            sourceID: source.id,
            timestamp: timestamp,
            image: loaded.image,
            byteCount: loaded.byteCount
        )
    }
}
```

Before creating the task, query the cache with `PlaybackTimelinePreviewCacheKey(sourceID: source.id, timestampBucket: Int(timestamp.rounded(.down)))` and return a hit immediately. For storyboard sources, choose the matching tile before forming the key and use `Int(tile.startTime * 1_000)` as the bucket so every timestamp in one tile shares its decoded frame. Cache the successfully parsed HLS descriptor after its first resolution using `didResolveHLSStoryboard` plus `resolvedHLSStoryboard`, including the nil result, so each source master is fetched at most once.

Clamp finite positive timestamps, use one internal `Task`, and cancel it before starting another. Resolution order in the implementation above is:

```swift
if let explicitDescriptor {
    return try? await storyboardLoader.image(at: timestamp, descriptor: explicitDescriptor, source: source)
}
if let descriptor = try await storyboardLoader.hlsStoryboard(for: source) {
    return try? await storyboardLoader.image(at: timestamp, descriptor: descriptor, source: source)
}
return try? await localGenerator.image(at: timestamp, source: source)
```

If explicit or HLS loading fails validation/decoding, continue to the next source. If local generation fails or input is unseekable, return `nil`. Never publish or log source URLs, headers, or transport errors.

Compute decoded frame memory as `pixelsWide * pixelsHigh * 4`, insert it into `PlaybackTimelinePreviewCache` using the configuration limits, and hold no full storyboard sheet. `stop()` cancels in-flight work, clears cache/descriptors, and awaits `localGenerator.stop()`.

- [ ] **Step 5: Run tests and commit the service**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test \
  -only-testing:OmniaTests/PlaybackTimelinePreviewServiceTests \
  -only-testing:OmniaTests/HLSImagePlaylistTests \
  -only-testing:OmniaTests/StoryboardFrameLoaderTests \
  -only-testing:OmniaTests/MPVPlaybackIntegrationTests
git diff --check
git add Omnia/Platform/macOS/PlaybackTimelinePreviewService.swift \
  OmniaTests/PlaybackTimelinePreviewServiceTests.swift
git commit -m "Resolve and cache timeline previews"
```

Expected: all source-order and lifecycle tests pass.

---

### Task 6: Own debounce/stale rejection in the session and render supplementary hover UI

**Files:**
- Modify: `Omnia/Platform/Playback/PlaybackSession.swift`
- Modify: `Omnia/Features/Playback/MacPlaybackChrome.swift`
- Modify: `Omnia/Features/Playback/PlaybackViews.swift`
- Test: `OmniaTests/PlaybackSessionTests.swift`
- Test: `OmniaTests/PlaybackChromePresentationTests.swift`

**Interfaces:**
- Consumes: preview service from Task 5 and existing playback duration/timeline slider.
- Produces:
  - `PlaybackSession.timelinePreviewTimestamp`
  - `PlaybackSession.timelinePreviewImage`
  - `PlaybackTimelinePreviewRequestScheduler`
  - `requestTimelinePreview(at:)`
  - `endTimelinePreview()`
  - `MacPlaybackTimelinePreviewLayout.clampedCenter(...)`

- [ ] **Step 1: Write failing pure layout and stale-result tests**

In `PlaybackChromePresentationTests.swift`, add:

```swift
func testTimelinePreviewCenterClampsBubbleInsideAvailableWidth() {
    XCTAssertEqual(
        MacPlaybackTimelinePreviewLayout.clampedCenter(pointerX: 5, bubbleWidth: 192, availableWidth: 600),
        96
    )
    XCTAssertEqual(
        MacPlaybackTimelinePreviewLayout.clampedCenter(pointerX: 300, bubbleWidth: 192, availableWidth: 600),
        300
    )
    XCTAssertEqual(
        MacPlaybackTimelinePreviewLayout.clampedCenter(pointerX: 595, bubbleWidth: 192, availableWidth: 600),
        504
    )
}
```

In `PlaybackSessionTests.swift`, add a pure key check:

```swift
func testTimelinePreviewResultMatchesOnlyItsSource() {
    XCTAssertTrue(PlaybackTimelinePreviewResultKey(sourceID: "a").matches(sourceID: "a"))
    XCTAssertFalse(PlaybackTimelinePreviewResultKey(sourceID: "a").matches(sourceID: "b"))
}
```

Add a deterministic debounce/supersession test:

```swift
@MainActor
func testTimelinePreviewSchedulerPublishesOnlyLatestRequestAfterDebounce() async {
    let sleeper = TimelinePreviewSleeperStub()
    let scheduler = PlaybackTimelinePreviewRequestScheduler { duration in
        try await sleeper.sleep(for: duration)
    }
    var published: [Int] = []

    scheduler.schedule(after: .milliseconds(250)) { published.append(1) }
    await sleeper.waitForRequestCount(1)
    scheduler.schedule(after: .milliseconds(250)) { published.append(2) }
    await sleeper.waitForRequestCount(2)
    await sleeper.releaseAll()
    await Task.yield()

    let durations = await sleeper.requestedDurations
    XCTAssertEqual(published, [2])
    XCTAssertEqual(durations, [.milliseconds(250), .milliseconds(250)])
}
```

Place this test actor below the test case, capturing every wait without using wall-clock delays:

```swift
private actor TimelinePreviewSleeperStub {
    private(set) var requestedDurations: [Duration] = []
    private var sleepContinuations: [CheckedContinuation<Void, Never>] = []
    private var countContinuations: [(Int, CheckedContinuation<Void, Never>)] = []

    func sleep(for duration: Duration) async throws {
        requestedDurations.append(duration)
        resumeSatisfiedCountWaiters()
        await withCheckedContinuation { sleepContinuations.append($0) }
        try Task.checkCancellation()
    }

    func waitForRequestCount(_ count: Int) async {
        if requestedDurations.count >= count { return }
        await withCheckedContinuation { countContinuations.append((count, $0)) }
    }

    func releaseAll() {
        sleepContinuations.forEach { $0.resume() }
        sleepContinuations.removeAll()
    }

    private func resumeSatisfiedCountWaiters() {
        let ready = countContinuations.filter { requestedDurations.count >= $0.0 }
        countContinuations.removeAll { requestedDurations.count >= $0.0 }
        ready.forEach { $0.1.resume() }
    }
}
```

- [ ] **Step 2: Run focused tests and verify missing helpers fail**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test \
  -only-testing:OmniaTests/PlaybackSessionTests \
  -only-testing:OmniaTests/PlaybackChromePresentationTests
```

Expected: compilation fails for the new helper names.

- [ ] **Step 3: Add session-owned preview state and lifecycle**

Add this main-actor scheduler near the session's other small helpers:

```swift
@MainActor
final class PlaybackTimelinePreviewRequestScheduler {
    typealias Sleep = @Sendable (Duration) async throws -> Void

    private let sleep: Sleep
    private var task: Task<Void, Never>?

    init(sleep: @escaping Sleep = { try await Task.sleep(for: $0) }) {
        self.sleep = sleep
    }

    func schedule(
        after delay: Duration,
        operation: @escaping @MainActor () async -> Void
    ) {
        task?.cancel()
        task = Task {
            do {
                try await sleep(delay)
                try Task.checkCancellation()
                await operation()
            } catch {
                return
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
```

Under macOS in `PlaybackSession`, add:

```swift
private(set) var timelinePreviewTimestamp: Double?
private(set) var timelinePreviewImage: NSImage?
@ObservationIgnored private var timelinePreviewService: PlaybackTimelinePreviewService?
@ObservationIgnored private let timelinePreviewScheduler = PlaybackTimelinePreviewRequestScheduler()
```

Add the pure key:

```swift
nonisolated struct PlaybackTimelinePreviewResultKey: Equatable {
    let sourceID: String
    func matches(sourceID: String?) -> Bool { self.sourceID == sourceID }
}
```

Implement request handling:

```swift
func requestTimelinePreview(at timestamp: Double) {
    #if os(macOS)
    guard let source, let durationSeconds, durationSeconds > 0 else { return }
    let clamped = min(max(timestamp, 0), durationSeconds)
    timelinePreviewTimestamp = clamped
    if timelinePreviewService == nil {
        timelinePreviewService = PlaybackTimelinePreviewService(
            source: source,
            configuration: .init(isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled)
        )
    }
    let resultKey = PlaybackTimelinePreviewResultKey(sourceID: source.id)
    let debounce = PlaybackTimelinePreviewConfiguration(
        isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
    ).debounce
    let service = timelinePreviewService
    timelinePreviewScheduler.schedule(after: debounce) { [weak self] in
        guard let frame = await service?.frame(at: clamped) else { return }
        guard !Task.isCancelled, resultKey.matches(sourceID: self?.source?.id) else { return }
        self?.timelinePreviewImage = frame.image
    }
    #endif
}
```

Implement hover end so it clears presentation immediately and stops the preview core:

```swift
func endTimelinePreview() {
    #if os(macOS)
    timelinePreviewScheduler.cancel()
    timelinePreviewTimestamp = nil
    timelinePreviewImage = nil
    let service = timelinePreviewService
    timelinePreviewService = nil
    Task { await service?.stop() }
    #endif
}
```

Call `endTimelinePreview()` before `stop(persisting:)` drops the source and at the beginning of `start(...)` after stopping the prior session. This guarantees source-change invalidation and memory clearing.

- [ ] **Step 4: Add pure bubble clamping**

Near the existing `MacPlayback...Presentation` helpers, add:

```swift
nonisolated enum MacPlaybackTimelinePreviewLayout {
    static func clampedCenter(
        pointerX: CGFloat,
        bubbleWidth: CGFloat,
        availableWidth: CGFloat
    ) -> CGFloat {
        guard availableWidth > 0 else { return 0 }
        let half = min(max(bubbleWidth, 0) / 2, availableWidth / 2)
        return min(max(pointerX, half), availableWidth - half)
    }
}
```

- [ ] **Step 5: Replace only the slider wrapper with a hover-capable timeline view**

In `MacPlaybackChrome`, add `@Environment(\.accessibilityReduceMotion) private var reduceMotion` and `@State private var timelinePointerX: CGFloat?`.

Keep the existing `Slider`, binding, range, tint, accessibility label, disabled state, and `onEditingChanged` closure intact. Wrap it in a `GeometryReader` with the same height and attach `onContinuousHover` directly to the slider so drag gestures remain owned by `Slider`:

```swift
GeometryReader { geometry in
    Slider(
        value: Binding(
            get: { duration > 0 ? position : 0 },
            set: { playback.seek(to: $0) }
        ),
        in: 0 ... max(duration, 0.001),
        onEditingChanged: { isEditing in
            isInteracting = MacPlaybackInteractionPresentation.keepsChromeVisible(
                isEditingControl: isEditing,
                hasPresentedPanel: activePanel != nil
            )
        }
    )
    .tint(.white)
    .accessibilityLabel("Playback position")
    .disabled(duration <= 0)
    .onContinuousHover { phase in
        switch phase {
        case let .active(location):
            guard let timestamp = PlaybackTimelinePreviewPosition.timestamp(
                x: location.x,
                width: geometry.size.width,
                duration: duration
            ) else { return }
            timelinePointerX = location.x
            isInteracting = true
            playback.requestTimelinePreview(at: timestamp)
        case .ended:
            timelinePointerX = nil
            isInteracting = activePanel != nil
            playback.endTimelinePreview()
        }
    }

    if let pointerX = timelinePointerX,
       let timestamp = playback.timelinePreviewTimestamp {
        timelinePreviewBubble(timestamp: timestamp, image: playback.timelinePreviewImage)
            .frame(width: 192)
            .position(
                x: MacPlaybackTimelinePreviewLayout.clampedCenter(
                    pointerX: pointerX,
                    bubbleWidth: 192,
                    availableWidth: geometry.size.width
                ),
                y: -72
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transition(reduceMotion ? .identity : .opacity)
    }
}
.frame(height: 20)
```

Define the supplementary bubble with a fixed 16:9 image region and monospaced timestamp:

```swift
private func timelinePreviewBubble(timestamp: Double, image: NSImage?) -> some View {
    VStack(spacing: 6) {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Color.black.opacity(0.32)
            }
        }
        .frame(width: 176, height: 99)
        .clipped()
        .clipShape(.rect(cornerRadius: 9, style: .continuous))

        Text(PlaybackTimelinePresentation.timeText(timestamp))
            .font(.caption.monospacedDigit().weight(.semibold))
    }
    .padding(8)
    .omniaLiquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), role: .playbackTimeline)
}
```

In `PlaybackViews.swift`, change the existing formatter declaration from `private static func timeText` to `static func timeText`. Keep its implementation unchanged and reuse it in the bubble; do not add a second timestamp formatter.

In `MacPlaybackChrome.onDisappear`, call `playback.endTimelinePreview()` before clearing interaction. The timestamp-only bubble appears immediately; image arrival is the only delayed content.

- [ ] **Step 6: Run focused tests and a Mac build**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test \
  -only-testing:OmniaTests/PlaybackSessionTests \
  -only-testing:OmniaTests/PlaybackChromePresentationTests \
  -only-testing:OmniaTests/PlaybackTimelinePreviewServiceTests
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' build
```

Expected: tests pass and the app builds without changing the slider's accessibility contract.

- [ ] **Step 7: Commit the session/UI slice**

```bash
git diff --check
git add Omnia/Platform/Playback/PlaybackSession.swift \
  Omnia/Features/Playback/MacPlaybackChrome.swift \
  Omnia/Features/Playback/PlaybackViews.swift \
  OmniaTests/PlaybackSessionTests.swift \
  OmniaTests/PlaybackChromePresentationTests.swift
git commit -m "Show timeline previews on hover"
```

---

### Task 7: Full verification, accessibility smoke test, and Release evidence

**Files:**
- Verify: all files changed by this plan

**Interfaces:**
- Consumes: complete preview pipeline.
- Produces: functional, security, accessibility, and same-hardware performance evidence.

- [ ] **Step 1: Run the complete macOS suite**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test
```

Expected: all tests pass.

- [ ] **Step 2: Exercise every runtime state on Mac**

Record these checks in the implementation handoff:

```text
Loading: timestamp bubble appears immediately; image fills after debounce.
Explicit storyboard: selected before HLS/local fallback in the service test.
HLS image playlist: correct scene/tile appears for hovered timestamp.
Local fallback: exact selected source supplies frame; visible player position is unchanged.
Unseekable/error/offline: timestamp remains; playback has no alert or interruption.
Recovery: moving to another time can retry; leaving hover stops work.
Source change/close: bubble disappears and cache/core are released.
Rapid movement: only final debounced request publishes.
Window edges: bubble remains fully visible.
Dragging/keyboard: slider seeking remains unchanged.
Reduce Motion: no preview transition.
VoiceOver/Full Keyboard Access: existing playback-position slider remains the sole required control.
Low Power Mode: 500 ms debounce and no more than eight cached frames.
```

- [ ] **Step 3: Repeat Release measurements from Task 1**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -configuration Release \
  -destination 'platform=macOS' build
```

Repeat ten runs of the identical 60-second playback and 15-second hover scenario on the same Mac/source after one untimed warm-up. Report median, p90, range, and variance; add median and worst preview latency from pointer rest to image appearance. Acceptance requires:

```text
No primary-player seek caused by hover.
No unbounded scan or disk cache.
At most one preview request in flight.
Cache <= 24 frames and <= 8 MiB; Low Power cache <= 8 frames.
No regression in primary-player dropped frames outside recorded variance.
No sustained work after hover exit.
```

Report measured trade-offs. Do not claim faster, smoother, lower-memory, or lower-energy behavior unless these Release results demonstrate it.

- [ ] **Step 4: Review repository scope and warnings**

```bash
git status --short
git diff --check
git log --oneline -8
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' build 2>&1 \
  | rg "warning:|error:" || true
```

Expected: no new warning in a changed file and no unrelated path in this plan's commits.
