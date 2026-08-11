# Playback Source and Track Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show every add-on source, attempt every direct HTTPS source with libmpv on macOS, and synchronize embedded audio/subtitle tracks from libmpv events.

**Architecture:** Keep add-on candidates complete and classify them for presentation instead of filtering them out. Make libmpv the format authority for macOS direct HTTPS. Add a small immutable Objective-C playback snapshot and drive `PlaybackSession` track state from mpv events, retaining polling only for defensive progress persistence.

**Tech Stack:** SwiftUI, Swift 6 observation and main-actor isolation, Objective-C libmpv client API, XCTest, signed macOS test host.

## Global Constraints

- macOS direct HTTPS accepts extensionless, unknown-extension, and `notWebReady` sources.
- Every returned candidate is visible in exactly one section: direct, resolver-required, external page, or unavailable.
- Torrent candidates continue using the existing resolver row until the local-torrent plan replaces that path.
- External webpages and malformed declarations are visible but are not sent to libmpv.
- Track UI reports loading separately from a confirmed empty track list.
- No new dependency, entitlement, hosted mutation, or mobile-player behavior change.
- Preserve the existing uncommitted `AddonRegistry.swift` and `SkipSegment.swift` warning fixes without staging them in playback commits.

---

### Task 1: Preserve all direct HTTPS candidates

**Files:**
- Modify: `Omnia/Domain/Playback/PlaybackSource.swift`
- Modify: `Omnia/Domain/Playback/PlaybackPolicy.swift`
- Test: `OmniaTests/StremioAddonClientTests.swift`
- Test: `OmniaTests/PlaybackPolicyTests.swift`

**Interfaces:**
- Consumes: `AddonStream`, `AddonStreamBehaviorHints.notWebReady`, `PlaybackAdapter.libmpv`.
- Produces: `AddonStreamCandidate.delivery == .nativeHTTPS(URL)` for every valid direct HTTPS URL and `PlaybackPolicy.isEligible(_:adapter:compatibleOnly:) == true` for every macOS direct HTTPS candidate.

- [ ] **Step 1: Add failing direct-source regressions**

Add these tests using the existing `RecordingTransport` fixture and candidate helper:

```swift
func testNotWebReadyDirectHTTPSRemainsAPlayerCandidate() async throws {
    let data = Data("""
    {"streams":[{"url":"https://media.example/opaque","name":"Remux","behaviorHints":{"notWebReady":true}}]}
    """.utf8)
    let candidates = try await StremioAddonClient.fetchStreamCandidates(
        from: streamAddon(),
        mediaTypes: ["movie"],
        identifiers: ["tt1234567"],
        transport: RecordingTransport(data: data)
    )

    guard case let .nativeHTTPS(url) = try XCTUnwrap(candidates.first).delivery else {
        return XCTFail("Expected direct HTTPS delivery")
    }
    XCTAssertEqual(url.absoluteString, "https://media.example/opaque")
}
```

Add `streamAddon()` by extracting the existing installed-add-on fixture from `testStreamFetchUsesBoundedTransportInsteadOfSharedSession`. Keep the existing named policy regression:

```swift
func testOpaqueHTTPSRemainsEligibleForLibmpvWhenCompatibilityFilterIsEnabled() {
    let opaque = candidate(
        id: "opaque",
        delivery: .nativeHTTPS(URL(string: "https://media.example/play")!)
    )
    XCTAssertTrue(PlaybackPolicy.isEligible(opaque, adapter: .libmpv, compatibleOnly: true))
}
```

- [ ] **Step 2: Run the focused tests and witness RED**

Run:

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' \
  -only-testing:OmniaTests/StremioAddonClientTests/testNotWebReadyDirectHTTPSRemainsAPlayerCandidate \
  -only-testing:OmniaTests/PlaybackPolicyTests/testOpaqueHTTPSRemainsEligibleForLibmpvWhenCompatibilityFilterIsEnabled test
```

Expected: the `notWebReady` test fails because the candidate is not `.nativeHTTPS`; the policy test fails on an unmodified baseline or documents the already-applied working-tree fix.

- [ ] **Step 3: Remove extension and `notWebReady` vetoes**

Use this delivery precedence in `AddonStreamCandidate.init`:

```swift
if let directURL {
    delivery = .nativeHTTPS(directURL)
} else if let needsResolver {
    delivery = .resolverRequired(infoHash: needsResolver, fileIndex: stream.fileIdx)
} else if let externalURL {
    delivery = .externalHandoff(externalURL)
} else {
    delivery = .unsupported
}
```

Keep compatibility labels descriptive. In `PlaybackPolicy.isEligible`, make `.unknown` eligible whenever `adapter == .libmpv`, independent of `compatibleOnly`.

- [ ] **Step 4: Run focused tests and witness GREEN**

Run the Task 1 command again. Expected: both tests pass.

- [ ] **Step 5: Commit only the source-policy slice**

```bash
git add Omnia/Domain/Playback/PlaybackSource.swift Omnia/Domain/Playback/PlaybackPolicy.swift OmniaTests/StremioAddonClientTests.swift OmniaTests/PlaybackPolicyTests.swift
git commit -m "Show every direct HTTPS playback source"
```

### Task 2: Classify every candidate for source-sheet presentation

**Files:**
- Create: `Omnia/Domain/Playback/PlaybackSourcePresentation.swift`
- Test: `OmniaTests/PlaybackSourcePresentationTests.swift`

**Interfaces:**
- Consumes: `[AddonStreamCandidate]`.
- Produces: `PlaybackSourceSections.init(candidates:)` with `direct`, `resolverRequired`, `external`, and `unavailable` arrays whose concatenated IDs equal the input IDs in input order.

- [ ] **Step 1: Write failing partition tests**

```swift
final class PlaybackSourcePresentationTests: XCTestCase {
    func testEveryCandidateAppearsInExactlyOneSection() {
        let candidates = [
            fixture("direct", .nativeHTTPS(URL(string: "https://media.example/play")!)),
            fixture("torrent", .resolverRequired(infoHash: String(repeating: "a", count: 40), fileIndex: 2)),
            fixture("external", .externalHandoff(URL(string: "https://player.example/watch")!)),
            fixture("bad", .unsupported),
        ]

        let sections = PlaybackSourceSections(candidates: candidates)

        XCTAssertEqual(sections.direct.map(\.id), ["direct"])
        XCTAssertEqual(sections.resolverRequired.map(\.id), ["torrent"])
        XCTAssertEqual(sections.external.map(\.id), ["external"])
        XCTAssertEqual(sections.unavailable.map(\.id), ["bad"])
        XCTAssertEqual(sections.all.map(\.id), candidates.map(\.id))
    }
}
```

Provide a private fixture initializer matching `PlaybackPolicyTests.candidate`.

- [ ] **Step 2: Run the new test and witness RED**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' \
  -only-testing:OmniaTests/PlaybackSourcePresentationTests test
```

Expected: compile failure because `PlaybackSourceSections` does not exist.

- [ ] **Step 3: Add the pure partition model**

```swift
struct PlaybackSourceSections: Equatable, Sendable {
    private let ordered: [AddonStreamCandidate]
    let direct: [AddonStreamCandidate]
    let resolverRequired: [AddonStreamCandidate]
    let external: [AddonStreamCandidate]
    let unavailable: [AddonStreamCandidate]

    init(candidates: [AddonStreamCandidate]) {
        ordered = candidates
        direct = candidates.filter { if case .nativeHTTPS = $0.delivery { true } else { false } }
        resolverRequired = candidates.filter { if case .resolverRequired = $0.delivery { true } else { false } }
        external = candidates.filter { if case .externalHandoff = $0.delivery { true } else { false } }
        unavailable = candidates.filter { if case .unsupported = $0.delivery { true } else { false } }
    }

    var all: [AddonStreamCandidate] { ordered }
}
```

- [ ] **Step 4: Run the partition tests and witness GREEN**

Run the Task 2 command again. Expected: pass.

- [ ] **Step 5: Commit the presentation model**

```bash
git add Omnia/Domain/Playback/PlaybackSourcePresentation.swift OmniaTests/PlaybackSourcePresentationTests.swift
git commit -m "Classify every playback source for presentation"
```

### Task 3: Render all source categories without pre-filtering

**Files:**
- Modify: `Omnia/Features/Playback/PlaybackViews.swift`
- Modify: `Omnia/Domain/Playback/PlaybackSourcePresentation.swift`
- Test: `OmniaTests/PlaybackSourcePresentationTests.swift`

**Interfaces:**
- Consumes: `PlaybackSourceResolution.candidates`, `PlaybackSourceSections`.
- Produces: source-sheet rows for every candidate and safe action availability per category.

- [ ] **Step 1: Add failing action-state assertions**

Extend `PlaybackSourceSections` with a pure row state and test exact copy:

```swift
XCTAssertEqual(PlaybackSourceRowState(candidate: candidates[0]).action, .playDirect)
XCTAssertEqual(PlaybackSourceRowState(candidate: candidates[1]).action, .resolve)
XCTAssertEqual(PlaybackSourceRowState(candidate: candidates[2]).action, .unavailable("External page—not locally resolved"))
XCTAssertEqual(PlaybackSourceRowState(candidate: candidates[3]).action, .unavailable("Malformed or unsupported source"))
```

The test references the production `PlaybackSourceRowState` interface; do not declare a test-local replacement. The production type added in Step 3 is `Equatable` and `Sendable`, with nested actions `.playDirect`, `.resolve`, and `.unavailable(String)`.

- [ ] **Step 2: Run the presentation tests and witness RED**

Run the Task 2 command. Expected: compile failure because the row-state initializer is missing.

- [ ] **Step 3: Implement row state and update the SwiftUI sheet**

Implement the initializer as an exhaustive `switch candidate.delivery`. In `PlaybackSourceSheet`:

```swift
resolution = result
candidates = result.candidates
```

Delete `isVisibleCandidate` and `incompatibleFormatCandidates`. Derive `PlaybackSourceSections(candidates: filteredCandidates)` once per render and show sections in this order: direct HTTPS, requires resolver, external pages, unavailable. External and unavailable rows are non-buttons with their exact reason. Keep add-on counts based on the complete candidate list.

- [ ] **Step 4: Run presentation and policy tests**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' \
  -only-testing:OmniaTests/PlaybackSourcePresentationTests \
  -only-testing:OmniaTests/PlaybackPolicyTests test
```

Expected: pass.

- [ ] **Step 5: Commit the complete source sheet**

```bash
git add Omnia/Features/Playback/PlaybackViews.swift Omnia/Domain/Playback/PlaybackSourcePresentation.swift OmniaTests/PlaybackSourcePresentationTests.swift
git commit -m "Present every add-on playback source"
```

### Task 4: Add libmpv event snapshots

**Files:**
- Modify: `Omnia/Platform/Playback/MPVPlayerController.h`
- Modify: `Omnia/Platform/Playback/MPVPlayerController.m`
- Modify: `OmniaTests/MPVPlaybackIntegrationTests.swift`

**Interfaces:**
- Consumes: libmpv wakeup callback, `MPV_EVENT_FILE_LOADED`, `MPV_EVENT_END_FILE`, observed `track-list`, `aid`, and `sid` properties.
- Produces: `OMMpvPlaybackSnapshot`, `OMMpvPlayerController.stateChangeHandler`, and `tracksLoading`.

- [ ] **Step 1: Extend the integration test with event expectations**

Before `startIfNeeded`, install a handler and record snapshots on the main actor:

```swift
var snapshots: [OMMpvPlaybackSnapshot] = []
player.stateChangeHandler = { snapshot in snapshots.append(snapshot) }
player.startIfNeeded()

waitUntil {
    snapshots.contains { !$0.tracksLoading && $0.audioTracks.count == 2 && $0.subtitleTracks.count == 1 }
}
XCTAssertTrue(snapshots.contains { $0.audioTracks.count == 2 })
```

After selecting audio/subtitles, assert the handler emits the selected ID.

- [ ] **Step 2: Run the integration test and witness RED**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' \
  -only-testing:OmniaTests/MPVPlaybackIntegrationTests/testLocalMultiTrackFixtureRendersAndSupportsExplicitTrackSelection test
```

Expected: compile failure because the snapshot and handler do not exist.

- [ ] **Step 3: Implement wakeup, property observation, and immutable snapshots**

Add this public shape:

```objc
@interface OMMpvPlaybackSnapshot : NSObject
@property (nonatomic, readonly) NSArray<OMMpvTrack *> *audioTracks;
@property (nonatomic, readonly) NSArray<OMMpvTrack *> *subtitleTracks;
@property (nonatomic, readonly) BOOL tracksLoading;
@property (nonatomic, readonly, nullable) NSString *errorMessage;
@end

@property (nonatomic, copy, nullable) void (^stateChangeHandler)(OMMpvPlaybackSnapshot *snapshot);
```

After `mpv_initialize`, observe `track-list`, `aid`, and `sid`. Install `mpv_set_wakeup_callback`; the C callback dispatches to the main queue and calls `drainEvents`. `drainEvents` loops `mpv_wait_event(_mpv, 0)` until `MPV_EVENT_NONE`, sets loading false on `FILE_LOADED`, translates `END_FILE` errors without including the URL, and emits one snapshot after relevant events. Clear the wakeup callback and handler before destroying mpv.

- [ ] **Step 4: Run the signed integration test and witness GREEN**

Run the Task 4 command again. Expected: pass with at least one loaded multi-track snapshot and selection snapshots.

- [ ] **Step 5: Commit the mpv event bridge**

```bash
git add Omnia/Platform/Playback/MPVPlayerController.h Omnia/Platform/Playback/MPVPlayerController.m OmniaTests/MPVPlaybackIntegrationTests.swift
git commit -m "Publish libmpv track state from events"
```

### Task 5: Drive player menus from snapshots

**Files:**
- Modify: `Omnia/Platform/Playback/PlaybackSession.swift`
- Modify: `Omnia/Features/Playback/PlaybackViews.swift`
- Test: `OmniaTests/PlaybackTrackTests.swift`

**Interfaces:**
- Consumes: `OMMpvPlaybackSnapshot` and `stateChangeHandler` from Task 4.
- Produces: `PlaybackSession.areTracksLoading`, event-driven `audioTracks`, event-driven `subtitleTracks`, and explicit menu empty/loading copy.

- [ ] **Step 1: Add track-presentation tests**

Add a pure presentation enum to `PlaybackTrack.swift` and test it:

```swift
XCTAssertEqual(PlaybackTrackAvailability(isLoading: true, tracks: []), .loading)
XCTAssertEqual(PlaybackTrackAvailability(isLoading: false, tracks: []), .empty)
XCTAssertEqual(
    PlaybackTrackAvailability(isLoading: false, tracks: [
        PlaybackTrack(id: 1, title: nil, language: nil, codec: "aac", isSelected: true)
    ]),
    .available
)
```

- [ ] **Step 2: Run the track tests and witness RED**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' \
  -only-testing:OmniaTests/PlaybackTrackTests test
```

Expected: compile failure because `PlaybackTrackAvailability` does not exist.

- [ ] **Step 3: Wire snapshots into the session and menus**

Implement:

```swift
enum PlaybackTrackAvailability: Equatable, Sendable {
    case loading
    case empty
    case available

    init(isLoading: Bool, tracks: [PlaybackTrack]) {
        self = isLoading ? .loading : (tracks.isEmpty ? .empty : .available)
    }
}
```

In `PlaybackSession.start`, assign `mpv.stateChangeHandler = { [weak self] snapshot in self?.apply(snapshot) }`. `apply` maps tracks and error state on the main actor. Set `areTracksLoading = true` before mounting and false from the loaded snapshot. Clear the handler in `stop`.

Keep the 250 ms task for time/progress only; remove track-list polling from `refreshState`. In the audio and subtitle menus show `ProgressView("Tracks still loading")`, `Text("No audio tracks")`, or `Text("No embedded subtitles")` based on availability, then the existing rows for `.available`.

- [ ] **Step 4: Run all playback tests and both builds**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' \
  -only-testing:OmniaTests/PlaybackPolicyTests \
  -only-testing:OmniaTests/PlaybackSourcePresentationTests \
  -only-testing:OmniaTests/PlaybackTrackTests \
  -only-testing:OmniaTests/MPVPlaybackIntegrationTests test
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'generic/platform=iOS Simulator' build
git diff --check
```

Expected: all tests and builds pass; diff check prints nothing.

- [ ] **Step 5: Commit and review the immediate fix**

```bash
git add Omnia/Domain/Playback/PlaybackTrack.swift Omnia/Platform/Playback/PlaybackSession.swift Omnia/Features/Playback/PlaybackViews.swift OmniaTests/PlaybackTrackTests.swift
git commit -m "Synchronize embedded playback tracks"
git status --short
```

Expected: only unrelated pre-existing paths remain modified.
