# Non-Blocking Playback Track Switching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Change macOS audio and subtitle tracks without blocking the main actor or changing the user's paused state.

**Architecture:** Give each libmpv `aid`/`sid` property write a monotonic request identifier and submit it through `mpv_set_property_async`. The bridge aborts a superseded request of the same kind, publishes only the latest reply, and keeps selected-row truth in the existing observed `aid`, `sid`, and `track-list` snapshot. Swift persists subtitle preference only after the latest request succeeds.

**Tech Stack:** Swift 6, Objective-C++, libmpv client API, AppKit, XCTest

**Spec:** `docs/superpowers/specs/2026-09-12-macos-playback-track-and-timeline-previews-design.md`

## Global Constraints

- macOS only; keep the iOS AVFoundation path unchanged.
- Never call `pause`, toggle pause, or write the `pause` property during track selection.
- A remote audio track may produce an audible buffering gap, but Omnia must continue to report the actual libmpv paused state.
- Selected rows remain derived from observed libmpv state, not optimistic button state.
- A late older request must not win over the newest request of the same kind.
- A failed request retains the last confirmed selection and exposes only a bounded, non-secret playback error.
- Persist subtitle preferences only after the requested `sid` is confirmed.
- Do not alter playback chrome layout or styling.
- Do not stage or commit unrelated dirty-worktree files.

---

### Task 1: Capture the current Release behavior on the local multi-track fixture

**Files:**
- Read: `PERFORMANCE.md`
- Evidence only: no source changes

**Interfaces:**
- Consumes: `OmniaTests/Fixtures/multi-track.mkv` and the current Release build.
- Produces: a before-measurement note containing pause state, position movement, and main-thread track-call duration.

- [ ] **Step 1: Read the repository performance procedure**

```bash
sed -n '1,260p' PERFORMANCE.md
```

- [ ] **Step 2: Record the baseline on the same Mac used for final verification**

Build Release:

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -configuration Release \
  -destination 'platform=macOS' build
```

After one untimed warm-up, run the same scenario ten times in Instruments Time Profiler: launch that exact Release app, play the same source with at least two audio tracks and one subtitle track, and switch audio and subtitles ten times while playback is running. Record the median, p90, and range:

```text
Mac model / macOS:
Source and whether local or remote:
Position advanced during switches (yes/no):
Observed pause icon change (yes/no):
Longest main-thread selectAudioTrack/selectSubtitleTrack sample:
Audible remote-track gap range, if applicable:
```

This is baseline evidence, not a claim that the current implementation pauses.

---

### Task 2: Move explicit track writes onto libmpv's asynchronous API

**Files:**
- Modify: `Omnia/Platform/Playback/MPVPlayerController.h`
- Modify: `Omnia/Platform/Playback/MPVPlayerController.m`
- Test: `OmniaTests/MPVPlaybackIntegrationTests.swift`

**Interfaces:**
- Consumes: libmpv `mpv_set_property_async`, `mpv_abort_async_command`, `MPV_EVENT_SET_PROPERTY_REPLY`, and existing property observation.
- Produces:
  - `selectAudioTrack(id:completion:) -> UInt64`
  - `selectSubtitleTrack(id:completion:) -> UInt64`
  - completion signature `(UInt64, Bool, String?) -> Void`

- [ ] **Step 1: Rewrite the integration test against the asynchronous contract**

In `testLocalMultiTrackFixtureRendersAndSupportsExplicitTrackSelection`, explicitly start playback and wait for position movement before selecting tracks:

```swift
player.play()
waitUntil { player.position > 0.15 }
let positionBeforeSelection = player.position
XCTAssertFalse(player.isPaused)
```

Replace the first audio selection with:

```swift
var audioReplies: [(UInt64, Bool, String?)] = []
let audioRequestID = player.selectAudioTrack(id: secondAudio.trackID) { id, succeeded, message in
    audioReplies.append((id, succeeded, message))
}
waitUntil {
    audioReplies.contains { $0.0 == audioRequestID }
        && player.audioTracks.contains { $0.trackID == secondAudio.trackID && $0.isSelected }
        && player.position > positionBeforeSelection
}
XCTAssertEqual(audioReplies.last?.0, audioRequestID)
XCTAssertEqual(audioReplies.last?.1, true)
XCTAssertNil(audioReplies.last?.2)
XCTAssertFalse(player.isPaused)
```

Use the same completion form for subtitle enable and disable, asserting success and `player.isPaused == false` after each.

Add a latest-request test using the two audio tracks:

```swift
func testLatestAsynchronousAudioSelectionWins() throws {
    let fixtureURL = try XCTUnwrap(
        Bundle(for: Self.self).url(forResource: "multi-track", withExtension: "mkv")
    )
    let graph = makeStartedPlayer(url: fixtureURL)
    defer { retainAndStop(graph) }
    let player = graph.player
    waitUntil { player.audioTracks.count == 2 && player.position > 0.1 }

    let first = try XCTUnwrap(player.audioTracks.first)
    let second = try XCTUnwrap(player.audioTracks.last)
    var latestReply: (UInt64, Bool)?
    _ = player.selectAudioTrack(id: second.trackID) { _, _, _ in }
    let latestID = player.selectAudioTrack(id: first.trackID) { id, succeeded, _ in
        latestReply = (id, succeeded)
    }

    waitUntil {
        latestReply?.0 == latestID
            && latestReply?.1 == true
            && player.audioTracks.contains { $0.trackID == first.trackID && $0.isSelected }
    }
    XCTAssertFalse(player.isPaused)
}
```

Extract the existing window/player setup into these test-private helpers so both tests share the exact teardown contract:

```swift
private struct PlayerGraph {
    let player: OMMpvPlayerController
    let window: NSWindow
}

@MainActor
private func makeStartedPlayer(url: URL) -> PlayerGraph {
    let player = OMMpvPlayerController(url: url, requestHeaders: [:])
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 480, height: 270),
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    window.alphaValue = 0
    window.contentView = player.videoView
    window.orderFrontRegardless()
    player.startIfNeeded()
    player.play()
    return PlayerGraph(player: player, window: window)
}

@MainActor
private func retainAndStop(_ graph: PlayerGraph) {
    graph.player.stateChangeHandler = nil
    graph.player.stop()
    Self.retainedPlayers.append(graph.player)
    Self.retainedWindows.append(graph.window)
}
```

- [ ] **Step 2: Run the integration tests and verify the API mismatch fails**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test \
  -only-testing:OmniaTests/MPVPlaybackIntegrationTests
```

Expected: compilation fails because the controller has no completion-based selection methods.

- [ ] **Step 3: Declare the completion block and asynchronous methods**

In `MPVPlayerController.h`, add above `OMMpvPlayerController`:

```objc
typedef void (^OMMpvTrackSelectionCompletion)(
    uint64_t requestID,
    BOOL succeeded,
    NSString * _Nullable errorMessage
);
```

Replace the two synchronous declarations with:

```objc
- (uint64_t)selectAudioTrackWithID:(NSInteger)trackID
                        completion:(nullable OMMpvTrackSelectionCompletion)completion
    NS_SWIFT_NAME(selectAudioTrack(id:completion:));
- (uint64_t)selectSubtitleTrackWithID:(nullable NSNumber *)trackID
                           completion:(nullable OMMpvTrackSelectionCompletion)completion
    NS_SWIFT_NAME(selectSubtitleTrack(id:completion:));
```

- [ ] **Step 4: Add bridge-owned request bookkeeping**

In the private Objective-C section, define:

```objc
typedef NS_ENUM(NSInteger, OMMpvTrackSelectionKind) {
    OMMpvTrackSelectionKindAudio,
    OMMpvTrackSelectionKindSubtitle,
};

@interface OMMpvPendingTrackSelection : NSObject
@property (nonatomic) OMMpvTrackSelectionKind kind;
@property (nonatomic, copy, nullable) OMMpvTrackSelectionCompletion completion;
@end

@implementation OMMpvPendingTrackSelection
@end
```

Add these ivars to `OMMpvPlayerController`:

```objc
uint64_t _nextTrackSelectionRequestID;
uint64_t _latestAudioTrackSelectionRequestID;
uint64_t _latestSubtitleTrackSelectionRequestID;
NSMutableDictionary<NSNumber *, OMMpvPendingTrackSelection *> *_pendingTrackSelections;
```

Initialize `_nextTrackSelectionRequestID = 100` (property observers use IDs 1-3) and the dictionary in the designated initializer.

Add private helpers:

```objc
- (uint64_t)nextTrackSelectionRequestID;
- (void)abortTrackSelectionRequest:(uint64_t)requestID;
- (void)finishTrackSelectionForEvent:(mpv_event *)event;
```

`nextTrackSelectionRequestID` increments, skips zero, and returns a value not present in `_pendingTrackSelections`.

- [ ] **Step 5: Implement asynchronous `aid` and `sid` writes**

Implement audio selection as:

```objc
- (uint64_t)selectAudioTrackWithID:(NSInteger)trackID
                        completion:(OMMpvTrackSelectionCompletion)completion {
    if (!_mpv || _stopped) {
        if (completion) completion(0, NO, @"Audio track selection is unavailable.");
        return 0;
    }

    [self abortTrackSelectionRequest:_latestAudioTrackSelectionRequestID];
    uint64_t requestID = [self nextTrackSelectionRequestID];
    OMMpvPendingTrackSelection *pending = [OMMpvPendingTrackSelection new];
    pending.kind = OMMpvTrackSelectionKindAudio;
    pending.completion = completion;
    _pendingTrackSelections[@(requestID)] = pending;
    _latestAudioTrackSelectionRequestID = requestID;

    int64_t value = (int64_t)trackID;
    int status = mpv_set_property_async(_mpv, requestID, "aid", MPV_FORMAT_INT64, &value);
    if (status < 0) {
        [self finishTrackSelectionRequest:requestID status:status];
    }
    return requestID;
}
```

Declare and implement `finishTrackSelectionRequest:status:` as a shared private helper. Subtitle selection uses the same flow and `_latestSubtitleTrackSelectionRequestID`; for Off submit the string value through the property API:

```objc
const char *disabled = "no";
int status = mpv_set_property_async(_mpv, requestID, "sid", MPV_FORMAT_STRING, &disabled);
```

For a numeric subtitle ID, submit `MPV_FORMAT_INT64` exactly like audio.

`abortTrackSelectionRequest:` must call `mpv_abort_async_command`, remove the pending entry, and invoke its completion with `NO` and `nil`. It must not set `errorMessage`, because supersession is expected user behavior.

Dispatch every completion asynchronously to the main queue, including immediate libmpv submission failures. This guarantees Swift records the returned request ID before its completion runs.

- [ ] **Step 6: Consume property replies and bound failures**

Add to `drainEvents`:

```objc
case MPV_EVENT_SET_PROPERTY_REPLY:
    [self finishTrackSelectionForEvent:event];
    shouldEmitSnapshot = YES;
    break;
```

The finish helper must remove the pending entry, confirm that its request ID still equals the latest ID for its kind, and then invoke completion. For a negative `event->error`, construct only one of these fixed messages:

```objc
NSString *message = pending.kind == OMMpvTrackSelectionKindAudio
    ? @"The selected audio track could not be activated."
    : @"The selected subtitle track could not be activated.";
```

Set `self.errorMessage = message` only for the latest failed request. On success, clear only a previous track-selection error; do not erase an unrelated playback failure. Late or aborted replies are ignored because their dictionary entry is absent.

In `stop`, abort all outstanding libmpv request IDs, invoke their completions with `NO`/`nil`, empty the dictionary, then destroy the mpv core. Never call a completion after `_mpv` is destroyed.

- [ ] **Step 7: Run the integration tests and inspect the bridge diff**

Run the command from Step 2. Expected: PASS, position advances, pause stays false, and the latest audio row is selected.

Then:

```bash
git diff --check
git diff -- Omnia/Platform/Playback/MPVPlayerController.h \
  Omnia/Platform/Playback/MPVPlayerController.m \
  OmniaTests/MPVPlaybackIntegrationTests.swift
```

Confirm there is no call to `mpv_set_property`, `pause`, or `togglePause` in the two explicit selection methods.

- [ ] **Step 8: Commit the bridge slice**

```bash
git add Omnia/Platform/Playback/MPVPlayerController.h \
  Omnia/Platform/Playback/MPVPlayerController.m \
  OmniaTests/MPVPlaybackIntegrationTests.swift
git commit -m "Switch playback tracks asynchronously"
```

---

### Task 3: Confirm selection in `PlaybackSession` before persisting preferences

**Files:**
- Modify: `Omnia/Platform/Playback/PlaybackSession.swift`
- Test: `OmniaTests/PlaybackSessionTests.swift`

**Interfaces:**
- Consumes: completion-based controller methods from Task 2.
- Produces: latest-request filtering and success-only subtitle preference persistence.

- [ ] **Step 1: Add a pure latest-request gate and failing tests**

Add near the other macOS playback helpers in `PlaybackSession.swift`:

```swift
nonisolated struct PlaybackTrackSelectionGate: Equatable {
    private(set) var audioRequestID: UInt64?
    private(set) var subtitleRequestID: UInt64?

    mutating func beginAudio(_ id: UInt64) { audioRequestID = id == 0 ? nil : id }
    mutating func beginSubtitle(_ id: UInt64) { subtitleRequestID = id == 0 ? nil : id }

    mutating func finishAudio(_ id: UInt64) -> Bool {
        guard audioRequestID == id else { return false }
        audioRequestID = nil
        return true
    }

    mutating func finishSubtitle(_ id: UInt64) -> Bool {
        guard subtitleRequestID == id else { return false }
        subtitleRequestID = nil
        return true
    }

    mutating func reset() {
        audioRequestID = nil
        subtitleRequestID = nil
    }
}
```

First write these tests in `PlaybackSessionTests.swift` before adding the type:

```swift
func testTrackSelectionGateRejectsSupersededReply() {
    var gate = PlaybackTrackSelectionGate()
    gate.beginAudio(10)
    gate.beginAudio(11)

    XCTAssertFalse(gate.finishAudio(10))
    XCTAssertTrue(gate.finishAudio(11))
}

func testTrackSelectionGateTracksAudioAndSubtitleIndependently() {
    var gate = PlaybackTrackSelectionGate()
    gate.beginAudio(20)
    gate.beginSubtitle(21)

    XCTAssertTrue(gate.finishSubtitle(21))
    XCTAssertTrue(gate.finishAudio(20))
}
```

- [ ] **Step 2: Run the focused tests and verify failure**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test \
  -only-testing:OmniaTests/PlaybackSessionTests
```

Expected: compilation fails because `PlaybackTrackSelectionGate` is undefined.

- [ ] **Step 3: Add the gate and wire audio completion**

Add the type from Step 1, then add this ignored state to `PlaybackSession` under macOS:

```swift
@ObservationIgnored private var trackSelectionGate = PlaybackTrackSelectionGate()
@ObservationIgnored private var pendingSubtitlePreference: (id: Int?, tracks: [PlaybackTrack])?
```

Implement audio selection without an immediate `refreshState()`:

```swift
func selectAudioTrack(_ id: Int) {
    #if os(macOS)
    guard let player else { return }
    let requestID = player.selectAudioTrack(id: id) { [weak self] completedID, succeeded, message in
        guard let self, self.trackSelectionGate.finishAudio(completedID) else { return }
        if !succeeded, let message { self.playbackError = message }
        self.refreshState()
    }
    if requestID == 0 {
        playbackError = "Audio track selection is unavailable."
    } else {
        trackSelectionGate.beginAudio(requestID)
    }
    #endif
}
```

The selected row continues to update through `apply(_ snapshot:)`.

- [ ] **Step 4: Persist subtitle preference only after latest success**

Implement selection so the property reply only arms persistence; observed track state performs the confirmation:

```swift
func selectSubtitleTrack(_ id: Int?) {
    #if os(macOS)
    guard let player else { return }
    let requestedTracks = subtitleTracks
    let requestID = player.selectSubtitleTrack(id: id.map { NSNumber(value: $0) }) { [weak self] completedID, succeeded, message in
        guard let self, self.trackSelectionGate.finishSubtitle(completedID) else { return }
        if succeeded {
            self.pendingSubtitlePreference = (id, requestedTracks)
            self.confirmPendingSubtitlePreference()
        } else if let message {
            self.pendingSubtitlePreference = nil
            self.playbackError = message
        }
        self.refreshState()
    }
    if requestID == 0 {
        playbackError = "Subtitle track selection is unavailable."
    } else {
        trackSelectionGate.beginSubtitle(requestID)
    }
    #endif
}
```

Add this confirmation helper and call it after assigning `subtitleTracks` in `apply(_ snapshot:)` as well as from the successful completion:

```swift
private func confirmPendingSubtitlePreference() {
    guard let pendingSubtitlePreference else { return }
    let isConfirmed = if let id = pendingSubtitlePreference.id {
        subtitleTracks.contains { $0.id == id && $0.isSelected }
    } else {
        !subtitleTracks.contains(where: \.isSelected)
    }
    guard isConfirmed else { return }
    subtitlePreferencesHandler?(
        .selecting(
            id: pendingSubtitlePreference.id,
            from: pendingSubtitlePreference.tracks,
            style: subtitleStyle
        )
    )
    self.pendingSubtitlePreference = nil
}
```

`PlaybackTrack.id` is the existing integer identifier initialized from `OMMpvTrack.trackID`. Call `trackSelectionGate.reset()` and set `pendingSubtitlePreference = nil` at the start of a new session and in `stop(persisting:)` before dropping the player.

- [ ] **Step 5: Run focused and integration tests**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test \
  -only-testing:OmniaTests/PlaybackSessionTests \
  -only-testing:OmniaTests/MPVPlaybackIntegrationTests
```

Expected: PASS.

- [ ] **Step 6: Commit the session slice**

```bash
git diff --check
git add Omnia/Platform/Playback/PlaybackSession.swift OmniaTests/PlaybackSessionTests.swift
git commit -m "Confirm playback track selections"
```

---

### Task 4: Final functional and performance verification

**Files:**
- Verify: all paths changed by this plan

**Interfaces:**
- Consumes: completed bridge and session slices.
- Produces: full-test evidence and before/after Release measurements.

- [ ] **Step 1: Run the complete macOS suite and build**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test
xcodebuild -project Omnia.xcodeproj -scheme Omnia -configuration Release \
  -destination 'platform=macOS' build
```

Expected: all tests pass and Release build succeeds.

- [ ] **Step 2: Repeat the exact baseline scenario**

Use the same Mac, source, ten runs, and ten-switch sequence from Task 1. Record the same median, p90, variance, and range fields and additionally verify:

```text
Video position advances during every running-state switch.
Pause icon never changes unless the user clicks Pause.
The newest rapidly clicked track becomes selected.
Failed/unavailable selection leaves the prior row selected.
Subtitle preference changes only after confirmed selection.
```

Do not describe the change as faster or lower-energy unless the Release evidence supports that statement.

- [ ] **Step 3: Review final scope**

```bash
git status --short
git diff --check
git log --oneline -4
```

Expected: the plan's commits contain only the bridge, session, and corresponding tests.
