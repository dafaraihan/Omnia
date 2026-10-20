# Settings Capability Overhaul Implementation Plan

> **Automated-validation policy:** Follow the repository-root `AGENTS.md`. Instructions below that call for automated test targets, suites, fixtures, or scripts are historical and superseded; use builds, static checks, and focused manual evidence instead.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the approved Add-ons, local Progress, Video Player, Subtitle Appearance, and Upcoming capabilities as one coherent Omnia release while keeping playback in-app, IntroDB read-only, and all progress/watchlist data local.

**Architecture:** Keep small bounded preferences in a typed `SettingsPreferencesStore`; move durable library, progress, and watchlist state into a local SwiftData store with a verified legacy migration; centralize untrusted HTTP handling; express playback choices through a platform-neutral `PlaybackPolicy`; and adapt that policy to AVPlayer on iPhone/iPad and libmpv on Mac. Settings use native SwiftUI controls and platform presentation rather than duplicating the Fusion layout.

**Tech Stack:** Swift 5, SwiftUI, Observation, SwiftData, AVFoundation, libmpv Objective-C bridge, Uniform Type Identifiers, XCTest, Xcode 26.6 / SDK 26.5; no new third-party dependencies.

## Global Constraints

- Implement the whole plan before release handoff; the numbered tasks are verification boundaries, not user-facing phases.
- Preserve all unrelated staged and unstaged work. Stage and commit only the exact paths named by the active task.
- Do not add Trakt, AniList progress, PublicMetaDB, external-player destinations, subtitle translation, Home preview controls, or manual cache controls.
- IntroDB is a read-only external source for skip-intro timestamps. No upload, edit, account, token, or hosted mutation is authorized.
- Playback remains inside Omnia: AVPlayer on iPhone/iPad and libmpv on Mac. Ordinary Stremio streams must never be relabeled as previews.
- Every visible setting must alter real behavior. Hide or disable unavailable capability with a specific explanation.
- Use system `Form`, `Section`, `NavigationLink`, `Toggle`, `Picker`, `Slider`, `Button`, confirmation dialogs, file import/export, and semantic materials. Do not trace screenshot pixels.
- Treat add-on manifests, streams, subtitles, IntroDB responses, redirects, media URLs, and imported documents as untrusted. Enforce HTTPS, exact normalized origins, redirect policy, byte limits, decode limits, cancellation, bounded timeouts, and redacted errors.
- Never persist stream URLs, request headers, credentials, configured add-on URLs, or private query values in remembered-source records or exported documents.
- Use injected clocks, transports, stores, and deterministic fixtures. Automated tests must not call live add-ons, IntroDB, metadata providers, Supabase, or hosted services.
- Use four-space Swift indentation. Run `git diff --check` before every task commit.

---

### Task 1: Add typed, bounded Settings preferences

**Files:**
- Create: `Omnia/Domain/Settings/SettingsPreferences.swift`
- Create: `Omnia/Data/Settings/SettingsPreferencesStore.swift`
- Test: `OmniaTests/SettingsPreferencesTests.swift`

- [ ] Write failing tests for defaults, Codable round trips, invalid persisted-value recovery, and dependency normalization.

```swift
func testDefaultsMatchApprovedDesign() {
    let value = SettingsPreferences.default

    XCTAssertEqual(value.addonTimeout, .seconds20)
    XCTAssertEqual(value.continueWatchingLimit, .unlimited)
    XCTAssertEqual(value.watchlistMode, .local)
    XCTAssertTrue(value.showUpcoming)
    XCTAssertEqual(value.upcomingLookAhead, .days60)
    XCTAssertTrue(value.showSkipIntro)
    XCTAssertFalse(value.autoSkipIntro)
    XCTAssertFalse(value.autoplayNextEpisode)
    XCTAssertEqual(value.subtitleAppearance, .followSystem)
}

func testDisablingSkipIntroAlsoDisablesAutoSkip() {
    var value = SettingsPreferences.default
    value.autoSkipIntro = true
    value.showSkipIntro = false

    XCTAssertFalse(value.normalized.autoSkipIntro)
}
```

- [ ] Run the focused test and confirm it fails because the types do not exist.

```sh
[Automated validation command removed by repository policy.]
```

- [ ] Implement explicit `String, Codable, CaseIterable, Sendable` enums for `AddonTimeout`, `BoundedItemLimit`, `UpcomingLookAhead`, `UpNextLeadTime`, `SourceSelectionRetention`, `PreferredLanguage`, `SDHPreference`, and `AnimeAudioPreference`.
- [ ] Implement `SettingsPreferences: Codable, Equatable, Sendable` with the approved defaults and a `normalized` value that enforces dependency rules.
- [ ] Implement a `@MainActor @Observable final class SettingsPreferencesStore` that persists one versioned JSON payload to an injected `UserDefaults`, applies normalization on every mutation, and falls back atomically to defaults after corrupt or unsupported data.

```swift
@MainActor
@Observable
final class SettingsPreferencesStore {
    private let defaults: UserDefaults
    private let storageKey: String

    private(set) var preferences: SettingsPreferences

    init(defaults: UserDefaults = .standard, storageKey: String = "settings-preferences-v1")
    func update(_ transform: (inout SettingsPreferences) -> Void)
    func reset()
}
```

- [ ] Re-run the focused test and inspect the serialized payload to confirm no URL, token, or credential field exists.
- [ ] Run `git diff --check`, stage only the three task files, and commit.

```sh
git add -- Omnia/Domain/Settings/SettingsPreferences.swift Omnia/Data/Settings/SettingsPreferencesStore.swift OmniaTests/SettingsPreferencesTests.swift
git diff --cached --check
git commit -m 'Add bounded Settings preferences'
```

### Task 2: Centralize bounded HTTPS transport

**Files:**
- Create: `Omnia/Data/Networking/HTTPTransport.swift`
- Create: `OmniaTests/HTTPTransportTests.swift`
- Create: `OmniaTests/Fixtures/Networking/valid.json`
- Create: `OmniaTests/Fixtures/Networking/oversized.json`

- [ ] Write failing tests using an injected `URLProtocol` for HTTPS-only requests, exact-origin redirects, cross-origin redirect rejection, timeout propagation, cancellation, content-type validation, maximum body size, and redacted errors.

```swift
func testRejectsCrossOriginRedirect() async {
    let transport = HTTPTransport(session: .stubbed(response: .redirect(
        from: "https://introdb.app/segments",
        to: "https://example.test/segments"
    )))

    do {
        try await transport.data(for: .init(
            url: URL(string: "https://introdb.app/segments")!,
            allowedOrigin: .init(scheme: "https", host: "introdb.app", port: nil),
            timeout: .seconds(20),
            maximumResponseBytes: 256_000,
            acceptedContentTypes: ["application/json"]
        ))
        XCTFail("Expected the cross-origin redirect to be rejected")
    } catch {
        XCTAssertEqual(error as? HTTPTransportError, .redirectRejected)
    }
}
```

- [ ] Run the focused test and confirm the missing transport is the failure.
- [ ] Implement `HTTPTransporting`, `HTTPRequestPolicy`, `NormalizedOrigin`, and `HTTPTransport` as an actor-backed URLSession delegate.
- [ ] Buffer response data incrementally and cancel immediately once the configured limit is exceeded; do not call `URLSession.shared`.
- [ ] Map errors to user-safe cases without embedding the request URL or headers in `LocalizedError` text.
- [ ] Re-run the focused suite, `git diff --check`, and commit only the task paths.

```sh
git add -- Omnia/Data/Networking/HTTPTransport.swift OmniaTests/HTTPTransportTests.swift OmniaTests/Fixtures/Networking
git diff --cached --check
git commit -m 'Add bounded HTTPS transport'
```

### Task 3: Harden add-on fetching and build the Add-on registry

**Files:**
- Modify: `Omnia/Data/Addons/StremioAddonClient.swift`
- Modify: `Omnia/Data/Addons/StremioAddonManifest.swift`
- Modify: `Omnia/App/OmniaStore.swift`
- Create: `Omnia/Data/Addons/AddonRegistry.swift`
- Create: `Omnia/Domain/Addons/AddonBackupDocument.swift`
- Test: `OmniaTests/AddonRegistryTests.swift`
- Test: `OmniaTests/AddonBackupDocumentTests.swift`

- [ ] Write failing tests for manifest validation, preference-driven request timeout, stable ordering, enable/disable, reorder, remove, partial add-on failure, sanitized export, duplicate import, malformed import, private configured-URL exclusion, and cancellation.

```swift
func testExportNeverContainsConfiguredPrivateURL() throws {
    let addon = InstalledAddon.fixture(
        manifestURL: URL(string: "https://addon.test/private-token/manifest.json?key=secret")!
    )
    let result = AddonBackupDocument.exporting([addon])
    let encoded = try JSONEncoder().encode(result.document)
    let text = String(decoding: encoded, as: UTF8.self)

    XCTAssertEqual(result.excludedPrivateCount, 1)
    XCTAssertFalse(text.contains("private-token"))
    XCTAssertFalse(text.contains("secret"))
}
```

- [ ] Refactor `StremioAddonClient` to accept `any HTTPTransporting` and `AddonTimeout`; remove `URLSession.shared`; validate manifest identifiers, names, resource counts, catalog counts, and string lengths before constructing `InstalledAddon`.
- [ ] Implement `AddonRegistry` as the sole owner of persisted add-on ordering, enabled state, secure configured manifest URL access, disabled catalogs, and fetch coordination.
- [ ] Keep configured manifest URLs in `KeychainStore`. UserDefaults may contain manifest display metadata and a stable credential reference only.
- [ ] Implement a versioned `UTType` document containing only public, normalized, non-secret manifest references. Exclude entries with user-info, query, fragment, or non-public configuration paths and report the exclusion count before export.
- [ ] Import into a review model first; require an explicit second call to apply accepted entries; preserve existing add-ons on partial failure.
- [ ] Update `OmniaStore` to delegate add-on mutations to the registry without changing existing catalog behavior.
- [ ] Run add-on tests plus the existing source identifier tests.

```sh
[Automated validation command removed by repository policy.]
```

- [ ] Run `git diff --check` and commit only the task paths.

### Task 4: Move local library, progress, and watchlist to SwiftData

**Files:**
- Modify: `Omnia/Domain/Media/MediaItem.swift`
- Modify: `Omnia/App/OmniaStore.swift`
- Create: `Omnia/Data/Library/LocalMediaModels.swift`
- Create: `Omnia/Data/Library/LocalMediaStore.swift`
- Create: `Omnia/Data/Library/LegacyLibraryMigration.swift`
- Test: `OmniaTests/LocalMediaStoreTests.swift`
- Test: `OmniaTests/LegacyLibraryMigrationTests.swift`

- [ ] Write failing in-memory SwiftData tests for saving/removing watchlist items, recording resume state, completion threshold behavior, independent watchlist and progress flags, sort stability, continue-watching limits, clear-progress, and rollback after write failure.
- [ ] Write fixture-driven migration tests for the existing `saved-library` JSON including movie, episode resume, completed, and corrupt records.

```swift
func testLegacyKeyIsRemovedOnlyAfterVerifiedRoundTrip() async throws {
    let defaults = UserDefaults(suiteName: #function)!
    defaults.set(LegacyLibraryFixture.validData, forKey: "saved-library")
    let store = try LocalMediaStore.inMemory()

    try await LegacyLibraryMigration(defaults: defaults, store: store).runIfNeeded()

    XCTAssertEqual(try await store.snapshot(), LegacyLibraryFixture.expectedSnapshot)
    XCTAssertNil(defaults.data(forKey: "saved-library"))
}
```

- [ ] Keep `SavedMediaItem` as the stable Codable migration snapshot but move it beside the local persistence implementation so UI-facing `MediaItem` remains a domain model.
- [ ] Implement SwiftData models with stable media ID, watchlist membership, progress, duration, episode resume context, saved timestamp, and last-played timestamp. Do not store SwiftUI `Color` values.
- [ ] Implement `LocalMediaStore` behind a `LocalMediaStoring` protocol using one `ModelActor`; expose immutable `LocalMediaSnapshot` values to `@MainActor` clients.
- [ ] Make migration idempotent. Insert, fetch, compare normalized snapshots, then remove the legacy key and write a migration marker. Leave legacy data intact on any error or mismatch.
- [ ] Refactor `OmniaStore.library`, `toggleSaved`, and `recordPlayback` to use the local store while keeping published snapshots on the main actor.
- [ ] Run both focused suites twice to prove idempotence, then `git diff --check` and commit only task paths.

### Task 5: Add local data export, import, and destructive clearing

**Files:**
- Create: `Omnia/Domain/Library/LocalMediaBackupDocument.swift`
- Modify: `Omnia/Data/Library/LocalMediaStore.swift`
- Test: `OmniaTests/LocalMediaBackupDocumentTests.swift`
- Test: `OmniaTests/LocalMediaDestructiveActionTests.swift`

- [ ] Write failing tests for versioned export, deterministic ordering, import preview, merge conflicts, replace confirmation state, corrupt input, maximum record count, maximum file size, clear-progress preserving watchlist, and clear-watchlist preserving progress.
- [ ] Implement a document that contains local media identifiers, display metadata, watchlist membership, and resume state only. Reject URLs with credentials and strip request headers or provider secrets by construction.
- [ ] Bound imports to 10 MiB, 10,000 records, 4 KiB per free-text field, and 100 external identifiers per media item.
- [ ] Separate decode/validate, review, and apply operations. Make replace and clear operations require an explicit confirmation token created from the reviewed state.
- [ ] Run the focused suites, `git diff --check`, and commit only task paths.

### Task 6: Define source compatibility and remembered-source policy

**Files:**
- Modify: `Omnia/Domain/Playback/PlaybackSource.swift`
- Create: `Omnia/Domain/Playback/PlaybackPolicy.swift`
- Create: `Omnia/Data/Playback/RememberedSourceStore.swift`
- Test: `OmniaTests/PlaybackPolicyTests.swift`
- Test: `OmniaTests/RememberedSourceStoreTests.swift`

- [ ] Write failing tests for AVPlayer/libmpv compatibility, compatible-only filtering, external handoff exclusion, remembered-source match, expiration at 24 hours/3 days/1 week, add-on removal, binge-group preference, and prohibition on URL/header persistence.

```swift
struct RememberedSource: Codable, Equatable, Sendable {
    let mediaKey: MediaPlaybackKey
    let addonID: String
    let bingeGroup: String?
    let displayNameFingerprint: String
    let expiresAt: Date
}
```

- [ ] Change `AddonStreamCandidate` so `.externalHandoff` remains decodable for protocol truth but is never eligible, selectable, or presented by Omnia playback.
- [ ] Define adapter capabilities (`avPlayer`, `libmpv`) and derive eligible candidates using extension/container hints plus declared web readiness. Unknown direct HTTPS remains user-selectable on Mac but not auto-selected.
- [ ] Implement `PlaybackPolicy` to choose a remembered candidate first, then a safe compatible candidate only when autoplay-first is enabled, otherwise require source selection.
- [ ] Persist only the stable fields above through an injected clock. Add a test that JSON output contains neither `http` nor a request-header key.
- [ ] Run focused and existing playback-track suites, `git diff --check`, and commit only task paths.

### Task 7: Add the read-only IntroDB client and cache

**Files:**
- Create: `Omnia/Domain/Playback/SkipSegment.swift`
- Create: `Omnia/Data/Playback/IntroDBClient.swift`
- Create: `Omnia/Data/Playback/IntroSegmentCache.swift`
- Create: `OmniaTests/Fixtures/IntroDB/segments-valid.json`
- Create: `OmniaTests/Fixtures/IntroDB/segments-malformed.json`
- Test: `OmniaTests/IntroDBClientTests.swift`
- Test: `OmniaTests/IntroSegmentCacheTests.swift`

- [ ] Write failing tests for exact request construction, required IMDb/season/episode values, HTTPS origin pinning, malformed and oversized payloads, negative/overflowing timestamps, positive cache expiry at seven days, negative cache expiry at one day, offline cached fallback, and cancellation.

```swift
func testBuildsDocumentedReadOnlyRequest() async throws {
    _ = try await client.introSegments(imdbID: "tt1234567", season: 2, episode: 3)

    XCTAssertEqual(transport.lastRequest?.httpMethod, "GET")
    XCTAssertEqual(transport.lastRequest?.url?.absoluteString,
        "https://introdb.app/segments?imdb_id=tt1234567&season=2&episode=3")
}
```

- [ ] Implement only `GET https://introdb.app/segments`; expose no mutation method.
- [ ] Validate exact origin, JSON content type, 256 KiB body limit, at most 32 segments, finite timestamps, `0 <= start < end <= 12 hours`, and known segment types.
- [ ] Cache normalized values locally with injected `ClockProviding`; never log the full media identifier alongside a network error.
- [ ] Run focused suites, `git diff --check`, and commit only task paths.

### Task 8: Add deterministic playback automation state

**Files:**
- Create: `Omnia/Domain/Playback/PlaybackAutomationController.swift`
- Create: `OmniaTests/PlaybackAutomationControllerTests.swift`

- [ ] Write failing pure-state tests for skip-button visibility, one-shot auto-skip, seeking into/out of a segment, disabled skip, Up Next lead time, unknown duration, completion, cancellation, next-episode absence, and autoplay-next disabled.

```swift
func testAutoSkipSeeksOncePerSegment() {
    var controller = PlaybackAutomationController(policy: .fixture(autoSkipIntro: true))

    XCTAssertEqual(controller.update(position: 10, duration: 1_800, segments: [.intro(10...70)]), .seek(to: 70))
    XCTAssertEqual(controller.update(position: 11, duration: 1_800, segments: [.intro(10...70)]), .none)
}
```

- [ ] Implement immutable inputs and explicit effects: `.none`, `.presentSkip`, `.dismissSkip`, `.seek(to:)`, `.presentUpNext`, `.resolveNextEpisode`, `.stopAtEnd`.
- [ ] Keep networking and player engines outside this controller so tests remain deterministic.
- [ ] Run focused tests, `git diff --check`, and commit only task paths.

### Task 9: Make PlaybackSession event-driven and policy-aware

**Files:**
- Modify: `Omnia/Platform/Playback/PlaybackSession.swift`
- Modify: `Omnia/Features/Playback/PlaybackViews.swift`
- Create: `Omnia/Platform/Playback/PlaybackCoordinator.swift`
- Test: `OmniaTests/PlaybackCoordinatorTests.swift`

- [ ] Write failing tests with a fake `PlaybackEngine` for start/resume, periodic progress persistence, skip action, Up Next resolution, next-source policy, successful next playback, failure recovery, stop/cancellation, and remembered-source write.
- [ ] Extract a minimal `PlaybackEngine` protocol and adapt AVPlayer/libmpv behind platform implementations. Use engine time/control notifications where available; retain one bounded periodic observer only for progress persistence and overlays.
- [ ] Add `PlaybackContext` containing media, optional episode, ordered episodes, selected source identity, policy, and IntroDB eligibility.
- [ ] Have `PlaybackCoordinator` fetch IntroDB segments concurrently with player preparation, feed time updates into `PlaybackAutomationController`, and resolve the next episode only when needed.
- [ ] Render Skip Intro and Up Next as accessible SwiftUI overlays with labels, keyboard activation, no color-only state, Reduce Motion behavior, loading/error/retry states, and cancel action.
- [ ] Keep the current player playing if next-episode resolution fails; show a recoverable error and preserve the completed progress event.
- [ ] Run focused playback suites, `git diff --check`, and commit only task paths.

### Task 10: Implement AVPlayer audio and subtitle selection

**Files:**
- Modify: `Omnia/Platform/Playback/PlaybackSession.swift`
- Modify: `Omnia/Platform/Playback/NativePlayerView.swift`
- Create: `Omnia/Platform/Playback/AVPlayerMediaSelection.swift`
- Test: `OmniaTests/AVPlayerMediaSelectionTests.swift`

- [ ] Write failing tests for BCP-47 language matching, system language order, fallback, SDH/media-characteristic preference, forced-only avoidance, anime sub/dub rules, missing groups, and stable menu labels.
- [ ] Implement a pure `MediaSelectionPolicy` that ranks normalized `Locale.Language` identifiers and media characteristics without owning AVFoundation objects.
- [ ] Load `.audible` and `.legible` media selection groups asynchronously from `AVAsset`; convert options into `PlaybackTrack` values; apply the ranked option through `AVPlayerItem.select(_:in:)`.
- [ ] Set `appliesMediaSelectionCriteriaAutomatically` consistently: use automatic criteria for Follow System, disable it only when applying Omnia’s explicit choice.
- [ ] Expose the same accessible audio/subtitle menus already available on Mac, with unavailable explanations when the asset has no group.
- [ ] Run focused tests and an iOS Simulator build, then `git diff --check` and commit only task paths.

```sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'generic/platform=iOS Simulator' build
```

### Task 11: Apply language and subtitle policy to libmpv

**Files:**
- Modify: `Omnia/Platform/Playback/MPVPlayerController.h`
- Modify: `Omnia/Platform/Playback/MPVPlayerController.m`
- Modify: `Omnia/Platform/Playback/PlaybackSession.swift`
- Test: `OmniaTests/MPVPlaybackIntegrationTests.swift`
- Test: `OmniaTests/PlaybackTrackTests.swift`

- [ ] Add failing integration assertions for initial audio/subtitle language preferences, SDH preference, track refresh, explicit selection, subtitle disable, and safe handling of an unavailable track ID.
- [ ] Extend the bridge with explicit preferred-language and subtitle-style setters using documented libmpv properties; validate all numeric bounds in Swift before crossing the bridge.
- [ ] Apply policy before playback starts to avoid a visible track switch. Refresh track state from libmpv property events instead of reconstructing it from labels.
- [ ] Keep Objective-C error messages free of URLs and headers.
- [ ] Run the signed macOS integration tests, `git diff --check`, and commit only task paths.

### Task 12: Add bounded external subtitle parsing and custom rendering

**Files:**
- Create: `Omnia/Domain/Playback/SubtitleAppearance.swift`
- Create: `Omnia/Data/Playback/SubtitleParser.swift`
- Create: `Omnia/Platform/Playback/SubtitleCueTimeline.swift`
- Create: `Omnia/UI/Playback/SubtitleOverlayView.swift`
- Create: `OmniaTests/Fixtures/Subtitles/sample.srt`
- Create: `OmniaTests/Fixtures/Subtitles/sample.vtt`
- Create: `OmniaTests/Fixtures/Subtitles/malformed.srt`
- Test: `OmniaTests/SubtitleAppearanceTests.swift`
- Test: `OmniaTests/SubtitleParserTests.swift`
- Test: `OmniaTests/SubtitleCueTimelineTests.swift`

- [ ] Write failing tests for Follow System, presets, custom bound normalization, reset, SRT/WebVTT timestamps, cue ordering, overlap, malformed input, maximum bytes/cues/line length/duration, cancellation, and timeline lookup.
- [ ] Define semantic subtitle settings: Follow System; Standard, Boxed, Classic, Minimal, Bold; text scale 75–200% in 5% steps; semantic text/outline/background colors; background opacity 0–100% in 5% steps; outline/shadow choices; top/middle/bottom position; leading/center/trailing alignment; horizontal margin 0–15%.
- [ ] Parse only UTF-8 SRT and WebVTT, with a 2 MiB input limit, 10,000 cue limit, 2,000-character cue limit, finite timestamps, and stable sorting. Reject unsupported encodings and styled ASS/SSA overrides instead of silently misrendering them.
- [ ] On iPhone/iPad, use AVFoundation system rendering for Follow System and a SwiftUI overlay only for parsed external SRT/WebVTT cues under an Omnia preset/custom style.
- [ ] On Mac, map validated appearance fields to libmpv subtitle properties. Never pass free-form ASS style text.
- [ ] Respect safe areas, Dynamic Type intent, multiline text, VoiceOver transcript suppression, Reduce Transparency, and Increase Contrast.
- [ ] Run focused suites plus both supported builds, `git diff --check`, and commit only task paths.

### Task 13: Compute Upcoming from local series and metadata

**Files:**
- Create: `Omnia/Domain/Library/UpcomingEpisode.swift`
- Create: `Omnia/Data/Metadata/UpcomingService.swift`
- Create: `OmniaTests/UpcomingServiceTests.swift`
- Create: `OmniaTests/Fixtures/Upcoming/series-details.json`

- [ ] Write failing tests for ISO full dates, date-only values in the injected calendar/time zone, future filtering, boundary inclusion, watched episodes, duplicates, stable ordering, look-ahead options, item limits, empty state, cached partial metadata, offline fallback, and retry.
- [ ] Implement `UpcomingService` with injected clock, calendar, local media store, and metadata client. Query only locally saved series; reuse cached `MediaTitleDetails` before requesting metadata.
- [ ] Treat unparseable or missing air dates as unavailable, not as today. Deduplicate by canonical series/season/episode identity.
- [ ] Return a result containing `items`, `failures`, `isStale`, and `lastUpdated` so Home and Settings can render partial-success and recovery states honestly.
- [ ] Run focused tests, `git diff --check`, and commit only task paths.

### Task 14: Split Settings into native capability pages

**Files:**
- Modify: `Omnia/Features/Settings/SettingsView.swift`
- Create: `Omnia/Features/Settings/AddonsSettingsView.swift`
- Create: `Omnia/Features/Settings/ProgressSettingsView.swift`
- Create: `Omnia/Features/Settings/UpcomingSettingsView.swift`
- Create: `Omnia/Features/Settings/VideoPlayerSettingsView.swift`
- Create: `Omnia/Features/Settings/SubtitleAppearanceSettingsView.swift`
- Create: `Omnia/Features/Settings/SettingsSupportViews.swift`
- Test: `OmniaTests/SettingsPresentationTests.swift`

- [ ] Write failing state-model tests proving every approved setting is present, all excluded capabilities are absent, dependency-disabled rows have explanations, and destructive/import operations cannot execute before confirmation.
- [ ] Replace the monolithic custom Settings surface with a native `Form` root and navigation links for Add-ons, Local Progress, Upcoming, Video Player, Subtitle Appearance, Catalogs, Metadata, Account, and Appearance.
- [ ] Preserve existing functional Catalogs, Metadata, Account, and Appearance controls while moving their declarations into small private sections or support files; do not redesign unrelated behavior.
- [ ] Inject `SettingsPreferencesStore`, `AddonRegistry`, `LocalMediaStore`, and capability information through environment values or explicit initializers. Never create a second store inside a child view.
- [ ] Provide loading, empty, partial-success, offline/error, retry/recovery, disabled, and destructive states where applicable.
- [ ] Use `LabeledContent`, `ContentUnavailableView`, `ProgressView`, `confirmationDialog`, `fileImporter`, and `fileExporter` with concise help text and system symbols.
- [ ] Add searchable terms for “skip intro,” “subtitles,” “up next,” “local progress,” “add-ons,” and “upcoming” without implementing a custom search-results shell.
- [ ] Run focused tests and both builds, `git diff --check`, and commit only task paths.

### Task 15: Finish Add-ons and Local Progress flows

**Files:**
- Modify: `Omnia/Features/Settings/AddonsSettingsView.swift`
- Modify: `Omnia/Features/Settings/ProgressSettingsView.swift`
- Modify: `Omnia/App/OmniaStore.swift`
- Test: `OmniaTests/AddonsSettingsModelTests.swift`
- Test: `OmniaTests/ProgressSettingsModelTests.swift`

- [ ] Write failing tests for add validation/loading/success/error, enabled state, reorder, remove confirmation, capability disclosure, timeout wiring, sanitized export warning, import review/partial success, local watchlist selection, continue limit, export/import review, clear-progress confirmation, and no remote-provider rows.
- [ ] Implement Add-ons rows with icon, name, version, concise description, declared resource/capability chips, enable toggle, reorder accessibility actions, remove confirmation, and per-row failure recovery.
- [ ] Wire the add field to validation and registry install. Disable Add only while empty, invalid, or actively installing; explain HTTPS requirement inline.
- [ ] Wire import/export to the review models from Tasks 3 and 5. Show exactly how many private configured add-ons were excluded before allowing export.
- [ ] Implement Local Progress settings for local-only storage, Continue Watching limit, local Watchlist, export/import, and separately confirmed Clear Progress / Clear Watchlist actions.
- [ ] Confirm that “Trakt,” “AniList,” and “PublicMetaDB” do not occur in these two view files.

```sh
! rg -n 'Trakt|AniList|PublicMetaDB' Omnia/Features/Settings/AddonsSettingsView.swift Omnia/Features/Settings/ProgressSettingsView.swift
```

- [ ] Run focused tests, both builds, `git diff --check`, and commit only task paths.

### Task 16: Finish Video Player and Subtitle Appearance flows

**Files:**
- Modify: `Omnia/Features/Settings/VideoPlayerSettingsView.swift`
- Modify: `Omnia/Features/Settings/SubtitleAppearanceSettingsView.swift`
- Modify: `Omnia/Features/Playback/PlaybackViews.swift`
- Test: `OmniaTests/VideoPlayerSettingsModelTests.swift`
- Test: `OmniaTests/SubtitleAppearanceSettingsModelTests.swift`

- [ ] Write failing tests for every preference binding, dependency state, capability omission, reset confirmation, preset-to-custom transition, live preview semantics, and absence of external player/translation/preview/cache controls.
- [ ] Implement Video Player sections for Skip Intro, auto-skip, autoplay next, Up Next timing, remember selection, retention, autoplay first safe compatible source, direct Continue Watching, compatible-only filtering, audio/fallback language, subtitle/fallback language, SDH, and anime preference.
- [ ] Label the IntroDB row “Intro timestamps: IntroDB” with a link to its terms; provide no account or write action.
- [ ] Implement Subtitle Appearance with a light/dark representative preview, Follow System, five presets, bounded custom controls, platform-capability explanations, and confirmed Reset to Defaults.
- [ ] Use semantic colors and system typography; do not offer free-form fonts, CSS, ASS, or arbitrary numeric text fields.
- [ ] Confirm excluded controls are absent with `rg` and the model tests.
- [ ] Run focused tests, both builds, `git diff --check`, and commit only task paths.

### Task 17: Integrate Upcoming and playback behavior into Home and Detail

**Files:**
- Modify: `Omnia/Features/Home/HomeView.swift`
- Modify: `Omnia/Features/Library/MediaDetailView.swift`
- Modify: `Omnia/Features/Playback/PlaybackViews.swift`
- Modify: `Omnia/App/OmniaStore.swift`
- Test: `OmniaTests/HomeCapabilityTests.swift`
- Test: `OmniaTests/PlaybackEndToEndTests.swift`

- [ ] Write failing tests for Upcoming visibility/order/limit, empty/offline/partial/retry states, direct Continue Watching routing, remembered-source selection, manual picker fallback, compatible-only filtering, Skip Intro overlay, Up Next overlay, autoplay-next, and next-source failure recovery.
- [ ] Add an Upcoming shelf only when enabled and meaningful. Use existing shelf/card metrics, episode artwork fallback, semantic date text, and a navigation path to the series detail.
- [ ] Route Continue Watching through `PlaybackPolicy`: direct playback only when enabled and a safe eligible source is resolved; otherwise open detail/source selection without hiding the error.
- [ ] Remove external handoff actions and labels from source selection. Preserve resolver-required sources only when the existing authorized in-app resolver can yield an HTTPS playback source.
- [ ] Feed ordered episode context into `PlaybackCoordinator` so Up Next resolves the real next episode and prefers the current `bingeGroup` without persisting its URL.
- [ ] Keep Home preview autoplay and sound controls absent and ensure no ordinary stream request is issued for a decorative Home card.
- [ ] Run focused tests and both builds, `git diff --check`, and commit only task paths.

### Task 18: Use the standard Mac Settings scene

**Files:**
- Modify: `Omnia/App/OmniaApp.swift`
- Modify: `Omnia/App/OmniaRootView.swift`
- Modify: `Omnia/App/AppDestination.swift`
- Modify: `Omnia/Features/Settings/SettingsView.swift`
- Test: `OmniaTests/AppDestinationTests.swift`

- [ ] Write failing tests proving Mac sidebar destinations omit Settings while iPhone/iPad destinations retain it.
- [ ] Add a macOS `Settings` scene that hosts the shared Settings root at a sensible default/minimum size and automatically gains the standard app-menu entry and Command-comma behavior.
- [ ] Remove the duplicate macOS sidebar destination without removing the mobile Settings destination.
- [ ] Verify Mac window resize, toolbar/back navigation, keyboard focus, full-screen behavior, and restoration manually.
- [ ] Run focused tests and both builds, `git diff --check`, and commit only task paths.

### Task 19: Accessibility, platform, security, and release verification

**Files:**
- Modify only if a verification failure requires a scoped fix: files changed in Tasks 1–18
- Create: `docs/superpowers/verification/2026-08-11-settings-capability-overhaul.md`

- [ ] Run the complete signed macOS test suite.

```sh
[Automated validation command removed by repository policy.]
```

- [ ] Build every affected supported destination.

```sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' build
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'generic/platform=iOS Simulator' build
```

- [ ] Run source checks for forbidden product surface and secrets.

```sh
! rg -n 'Trakt|PublicMetaDB|subtitle translation|Translate subtitles|external player|preview sound|Autoplay Home previews|cache mode' Omnia/Features/Settings
! rg -n 'service_role|SUPABASE_SERVICE_ROLE|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY' Omnia OmniaTests
```

- [ ] Run `git diff --check` and inspect `git status --short`, `git diff --stat`, and every changed hunk. Confirm unrelated pre-existing changes remain uncommitted and unchanged by this work.
- [ ] On iPhone, verify portrait/landscape safe areas, Dynamic Type through accessibility sizes, VoiceOver order, local import/export, playback, Skip Intro, Up Next, and subtitle appearance.
- [ ] On iPad, verify Split View/Stage Manager resizing, pointer, hardware keyboard, focus order, file import/export, playback overlays, and Settings navigation.
- [ ] On Mac, verify standard Settings menu/Command-comma, window resizing, Full Keyboard Access, hover, focus, menu commands, full screen, libmpv track selection, Skip Intro, Up Next, and subtitle styling.
- [ ] Across all platforms, verify light/dark appearance, Reduce Motion, Reduce Transparency, Increase Contrast, color-independent status, loading, empty, partial-success, offline/error, retry, disabled, destructive, and cancellation states.
- [ ] Record exact commands, destinations, pass/fail results, manual device gaps, and any performance observations in the verification document. Do not claim Release performance gains without same-device Instruments or XCTest metric evidence.
- [ ] Commit only the verification document and any directly justified verification fixes.

```sh
git add -- docs/superpowers/verification/2026-08-11-settings-capability-overhaul.md
git diff --cached --check
git commit -m 'Verify Settings capability overhaul'
```

## Completion Gate

Do not call the implementation complete until all Tasks 1–19 are checked, the complete test/build commands pass, the platform-specific manual checks are either recorded as passed or explicitly identified as requiring physical-device verification, and the final diff contains no unrelated user work. Hosted Supabase mutations, deployment, archive promotion, and release publication remain outside this plan and require separate explicit authorization.
