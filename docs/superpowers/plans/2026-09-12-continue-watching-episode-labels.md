# Continue Watching Episode Labels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show `Reacher · 2022` and `S4 E1 · In the Name of the Mother` on episodic Continue Watching cards, including after an app relaunch.

**Architecture:** Persist the real resume episode title beside the existing resume episode identity, then format the two card lines through a pure presentation value. Keep movie labels and resume targeting unchanged, and omit the episode title when the stored value is absent or blank.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, XCTest

**Spec:** `docs/superpowers/specs/2026-09-12-macos-playback-track-and-timeline-previews-design.md`

## Global Constraints

- This change is macOS-only in presentation, but the shared local-media model must remain source-compatible with the existing app target.
- Series copy is exactly `Title · Year` followed by `S4 E1 · Episode Title`.
- If no trustworthy title is stored, render only `S4 E1`; never synthesize `Episode 1` for the card.
- Movies retain `Movie Title` followed by `2026`.
- Do not change resume targeting, progress calculation, card artwork, navigation, dimensions, fonts, or context-menu behavior.
- Existing version-1 backups and SwiftData records must decode with a `nil` episode title.
- Do not stage or commit unrelated dirty-worktree files.

---

### Task 1: Persist the real resume episode title

**Files:**
- Modify: `Omnia/Domain/Media/MediaItem.swift`
- Modify: `Omnia/Data/Library/LocalMediaModels.swift`
- Modify: `Omnia/Data/Library/LocalMediaStore.swift`
- Modify: `Omnia/App/OmniaStore.swift`
- Modify: `Omnia/Domain/Library/LocalMediaBackupDocument.swift`
- Test: `OmniaTests/LocalMediaStoreTests.swift`
- Test: `OmniaTests/LocalMediaBackupDocumentTests.swift`

**Interfaces:**
- Consumes: `MediaEpisode.title` whenever playback or a watch command selects a resume episode.
- Produces: `MediaItem.resumeEpisodeTitle: String?`, persisted by `LocalMediaRecord.resumeEpisodeTitle` and `SavedMediaItem.resumeEpisodeTitle`.

- [ ] **Step 1: Write failing persistence and compatibility tests**

In `OmniaTests/LocalMediaStoreTests.swift`, extend `testEpisodeResumeContextAndContinueLimitUseLastPlayedOrder` with:

```swift
XCTAssertEqual(seriesSnapshot.item.resumeEpisodeTitle, "Second")
```

Add this test beside the other local-media tests:

```swift
func testClearingCompletedEpisodeRemovesPersistedEpisodeTitle() async throws {
    let store = try LocalMediaStore.inMemory()
    let series = makeItem(id: "series-complete", title: "Series", kind: .series)
    let episode = MediaEpisode(
        id: "episode-8",
        seasonNumber: 3,
        episodeNumber: 8,
        title: "Finale",
        overview: "",
        runtimeMinutes: 42,
        stillURL: nil,
        airDate: nil
    )

    try await store.setWatchlist(series, isIncluded: true, at: .distantPast)
    try await store.recordPlayback(
        for: series,
        episode: episode,
        positionSeconds: 42,
        durationSeconds: 42,
        completionThreshold: 0.95,
        at: .now
    )

    let snapshot = try XCTUnwrap(try await store.snapshot().first)
    XCTAssertNil(snapshot.item.resumeEpisodeTitle)
}
```

In `OmniaTests/LocalMediaBackupDocumentTests.swift`, add:

```swift
func testBackupRoundTripPreservesResumeEpisodeTitle() throws {
    let item = MediaItem(
        id: "series",
        title: "Reacher",
        year: "2022",
        kind: .series,
        overview: "",
        genres: [],
        symbol: "tv",
        artworkColors: [.blue],
        progress: 0.5,
        resumeEpisodeID: "series:4:1",
        resumeSeasonNumber: 4,
        resumeEpisodeNumber: 1,
        resumeEpisodeTitle: "In the Name of the Mother"
    )
    let snapshot = LocalMediaSnapshot(
        item: item,
        isInWatchlist: false,
        savedAt: nil,
        lastPlayedAt: Date(timeIntervalSince1970: 10)
    )

    let encoded = try LocalMediaBackupDocument(snapshots: [snapshot]).encoded()
    let decoded = try LocalMediaBackupDocument.decode(encoded)

    XCTAssertEqual(decoded.records.first?.snapshot.item.resumeEpisodeTitle, "In the Name of the Mother")
}
```

Add this legacy decoding test, which removes the new optional key from otherwise valid version-1 JSON:

```swift
func testVersionOneBackupWithoutResumeEpisodeTitleStillDecodes() throws {
    let snapshot = LocalMediaSnapshot(
        item: makeItem(id: "legacy"),
        isInWatchlist: true,
        savedAt: nil,
        lastPlayedAt: nil
    )
    let encoded = try LocalMediaBackupDocument(snapshots: [snapshot]).encoded()
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    var records = try XCTUnwrap(object["records"] as? [[String: Any]])
    var media = try XCTUnwrap(records[0]["media"] as? [String: Any])
    media.removeValue(forKey: "resumeEpisodeTitle")
    records[0]["media"] = media
    object["records"] = records

    let legacyData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    let decoded = try LocalMediaBackupDocument.decode(legacyData)

    XCTAssertNil(decoded.records[0].snapshot.item.resumeEpisodeTitle)
}
```

- [ ] **Step 2: Run the focused tests and verify the new assertions fail**

Run:

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test \
  -only-testing:OmniaTests/LocalMediaStoreTests \
  -only-testing:OmniaTests/LocalMediaBackupDocumentTests
```

Expected: compilation fails because `MediaItem` has no `resumeEpisodeTitle` member.

- [ ] **Step 3: Add the optional field to domain and persistence models**

In `MediaItem`, place the new field with the existing resume episode fields, add an initializer parameter defaulted to `nil`, assign it, and copy it anywhere `MediaItem` reconstructs itself:

```swift
var resumeEpisodeTitle: String?

// Initializer parameter
resumeEpisodeTitle: String? = nil,

// Initializer body
self.resumeEpisodeTitle = resumeEpisodeTitle
```

Do not use `resumeEpisode.title` as card evidence when `resumeEpisode` is the fallback object. The fallback deliberately synthesizes `Episode N` for source targeting; presentation must use only `resumeEpisodeTitle`.

In `LocalMediaRecord` add:

```swift
var resumeEpisodeTitle: String?
```

In `SavedMediaItem`, add the optional Codable field, capture it in `init(_:)`, and pass it through `mediaItem`:

```swift
let resumeEpisodeTitle: String?

resumeEpisodeTitle = item.resumeEpisodeTitle

resumeEpisodeTitle: resumeEpisodeTitle,
```

Because the property is optional, synthesized `Decodable` accepts old version-1 JSON where the key is missing. Keep the backup version at `1`.

- [ ] **Step 4: Propagate, preserve, and clear the field at every resume-state mutation**

In `LocalMediaStore`, add the matching assignment beside every existing `resumeEpisodeStillURL` assignment:

```swift
record.resumeEpisodeTitle = episode.title
```

When importing/applying/snapshotting, copy between `item.resumeEpisodeTitle` and `record.resumeEpisodeTitle`. In `encodedBaseItem`, set it to `nil`. In `clearProgress(on:)`, set it to `nil` with the other resume fields.

In `OmniaStore.recordPlaybackInMemory`, set, preserve, and clear it alongside the other resume fields:

```swift
updated.resumeEpisodeTitle = episode.title
updated.resumeEpisodeTitle = existing.resumeEpisodeTitle
updated.resumeEpisodeTitle = nil
```

In `OmniaStore.applyWatchCommandInMemory.setResumeTarget`, set `episode.title` for a selected episode and clear it in the nil branch. Check all occurrences with:

```bash
rg -n "resumeEpisode(StillURL|Number|Title)" Omnia/App/OmniaStore.swift Omnia/Data/Library/LocalMediaStore.swift
```

Every mutation block that handles `resumeEpisodeStillURL` must also handle `resumeEpisodeTitle`.

- [ ] **Step 5: Include the title in backup input validation**

In `LocalMediaBackupRecord.validate()`, include the optional title in the bounded text set:

```swift
let textValues = [item.id, item.title, item.year, item.overview, item.symbol]
    + item.genres
    + [item.resumeEpisodeTitle].compactMap { $0 }
```

This keeps the existing 4,096-byte text bound and introduces no new URL trust boundary.

- [ ] **Step 6: Run persistence tests and commit the data-model slice**

Run the command from Step 2. Expected: PASS.

Then run:

```bash
git diff --check
git add Omnia/Domain/Media/MediaItem.swift \
  Omnia/Data/Library/LocalMediaModels.swift \
  Omnia/Data/Library/LocalMediaStore.swift \
  Omnia/App/OmniaStore.swift \
  Omnia/Domain/Library/LocalMediaBackupDocument.swift \
  OmniaTests/LocalMediaStoreTests.swift \
  OmniaTests/LocalMediaBackupDocumentTests.swift
git commit -m "Persist resume episode titles"
```

Expected: only these paths are committed.

---

### Task 2: Format and render the exact two-line card label

**Files:**
- Modify: `Omnia/UI/Components/ResumeProgressPresentation.swift`
- Modify: `Omnia/Features/Home/HomeView.swift`
- Test: `OmniaTests/ResumeProgressPresentationTests.swift`

**Interfaces:**
- Consumes: `MediaItem.title`, `year`, `kind`, `resumeSeasonNumber`, `resumeEpisodeNumber`, and persisted `resumeEpisodeTitle`.
- Produces: `ContinueWatchingCardPresentation.primaryText`, `secondaryText`, and `accessibilityValue`.

- [ ] **Step 1: Write failing pure presentation tests**

Add to `OmniaTests/ResumeProgressPresentationTests.swift`:

```swift
func testSeriesContinueWatchingCardShowsTitleYearAndExactEpisode() {
    var item = item(
        id: "reacher",
        kind: .series,
        progress: 0.5,
        resumeSeasonNumber: 4,
        resumeEpisodeNumber: 1
    )
    item.resumeEpisodeTitle = "In the Name of the Mother"

    let presentation = ContinueWatchingCardPresentation(item: item)

    XCTAssertEqual(presentation.primaryText, "Title · 2026")
    XCTAssertEqual(presentation.secondaryText, "S4 E1 · In the Name of the Mother")
    XCTAssertEqual(
        presentation.accessibilityValue,
        "2026, season 4, episode 1, In the Name of the Mother"
    )
}

func testSeriesContinueWatchingCardOmitsMissingOrBlankEpisodeTitle() {
    var item = item(
        id: "series",
        kind: .series,
        progress: 0.5,
        resumeSeasonNumber: 4,
        resumeEpisodeNumber: 1
    )

    XCTAssertEqual(ContinueWatchingCardPresentation(item: item).secondaryText, "S4 E1")

    item.resumeEpisodeTitle = "  \n "
    XCTAssertEqual(ContinueWatchingCardPresentation(item: item).secondaryText, "S4 E1")
}

func testMovieContinueWatchingCardKeepsCurrentTwoLines() {
    let presentation = ContinueWatchingCardPresentation(
        item: item(id: "movie", kind: .movie, progress: 0.5)
    )

    XCTAssertEqual(presentation.primaryText, "Title")
    XCTAssertEqual(presentation.secondaryText, "2026")
    XCTAssertEqual(presentation.accessibilityValue, "2026")
}
```

- [ ] **Step 2: Run the presentation tests and verify failure**

Run:

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test \
  -only-testing:OmniaTests/ResumeProgressPresentationTests
```

Expected: compilation fails because `ContinueWatchingCardPresentation` is undefined.

- [ ] **Step 3: Implement the pure formatter**

Add below `ResumeProgressPresentation` in `ResumeProgressPresentation.swift`:

```swift
nonisolated struct ContinueWatchingCardPresentation: Equatable {
    let primaryText: String
    let secondaryText: String
    let accessibilityValue: String

    init(item: MediaItem) {
        guard item.kind == .series,
              let season = item.resumeSeasonNumber,
              let episode = item.resumeEpisodeNumber else {
            primaryText = item.title
            secondaryText = item.year
            accessibilityValue = item.year
            return
        }

        primaryText = "\(item.title) · \(item.year)"
        let identifier = "S\(season) E\(episode)"
        let trimmedEpisodeTitle = item.resumeEpisodeTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let episodeTitle = trimmedEpisodeTitle.flatMap { $0.isEmpty ? nil : $0 }
        secondaryText = episodeTitle.map { "\(identifier) · \($0)" } ?? identifier
        accessibilityValue = [
            item.year,
            "season \(season)",
            "episode \(episode)",
            episodeTitle
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}
```

- [ ] **Step 4: Replace only the two text values on the Continue Watching card**

In `ContinueWatchingCard`, add:

```swift
private var cardPresentation: ContinueWatchingCardPresentation {
    ContinueWatchingCardPresentation(item: item)
}
```

Replace the below-artwork label values, preserving all existing modifiers:

```swift
Text(cardPresentation.primaryText)
    .font(.headline)
    .foregroundStyle(.primary)
    .lineLimit(1)
Text(cardPresentation.secondaryText)
    .font(.subheadline.weight(.medium))
    .foregroundStyle(.secondary)
    .lineLimit(1)
```

Keep the progress overlay (`S2E4 • 45m left`) unchanged. Update the card's accessibility value to:

```swift
.accessibilityValue(cardPresentation.accessibilityValue)
```

- [ ] **Step 5: Run focused tests and commit the presentation slice**

Run the command from Step 2. Expected: PASS.

Then:

```bash
git diff --check
git add Omnia/UI/Components/ResumeProgressPresentation.swift \
  Omnia/Features/Home/HomeView.swift \
  OmniaTests/ResumeProgressPresentationTests.swift
git commit -m "Show resume episode on Continue Watching cards"
```

---

### Task 3: Verify compatibility and the macOS UI

**Files:**
- Verify: all files changed in Tasks 1-2

**Interfaces:**
- Consumes: completed data-model and presentation slices.
- Produces: macOS build/test and manual UI evidence.

- [ ] **Step 1: Run the complete macOS test suite**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test
```

Expected: all tests pass, including legacy backup decoding.

- [ ] **Step 2: Build the macOS app**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' build
```

Expected: `** BUILD SUCCEEDED **` with no new warnings in changed files.

- [ ] **Step 3: Smoke-test the exact card states**

On Mac, record these results in the implementation handoff:

```text
Series with title: Reacher · 2022 / S4 E1 · In the Name of the Mother
Series without title: Reacher · 2022 / S4 E1
Movie: Movie Title / 2026
Relaunch: the series episode title remains present
VoiceOver: announces year, season, episode, and real episode title
```

Confirm card size, artwork, progress overlay, click behavior, context menu, dark appearance, keyboard focus, and Reduce Motion are unchanged.

- [ ] **Step 4: Review the final scoped diff**

```bash
git status --short
git diff --check
git log --oneline -3
```

Expected: no uncommitted changes from this plan and no unrelated paths in its two commits.
