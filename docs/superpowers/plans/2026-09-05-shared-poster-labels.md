# Shared Poster Labels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every standard movie and series poster a consistent optional title/year/genre label, and remove genre browsing from the Anime page.

**Architecture:** Persist one backward-compatible `showMediaCardLabels` preference, inject it once through SwiftUI’s environment, and let the shared `MediaPoster` and `RankedMediaPoster` components own all label rendering. Centralize explicit poster geometry in `MediaBrowseMetrics`; feature pages continue composing the same shared cards.

**Tech Stack:** Swift 5, SwiftUI, Observation, XCTest, Xcode app targets for macOS and iOS Simulator.

**Spec:** `docs/superpowers/specs/2026-09-05-shared-poster-labels-design.md`

## Global Constraints

- Render the exact `MediaItem.title` without abbreviation, rewriting, or truncation.
- Use native SwiftUI system text styles and semantic foreground colors.
- Keep Continue Watching and specialized episode, upcoming, person, genre, and video cards unchanged.
- Default labels to enabled for new and existing settings payloads.
- Preserve all unrelated dirty-worktree changes and add no dependency.
- Do not stage or commit changes in this shared workspace.

---

### Task 1: Persist the Poster Label Preference

**Files:**
- Modify: `OmniaTests/SettingsPreferencesTests.swift`
- Modify: `Omnia/Domain/Settings/SettingsPreferences.swift`

**Interfaces:**
- Produces: `SettingsPreferences.showMediaCardLabels: Bool`, defaulting to `true` and decoding missing values as `true`.

- [ ] **Step 1: Write failing preference tests**

Add assertions that the default is enabled, a store round trip preserves `false`, and decoding JSON with `showMediaCardLabels` removed restores `true`:

```swift
XCTAssertTrue(SettingsPreferences.default.showMediaCardLabels)

store?.update { $0.showMediaCardLabels = false }
XCTAssertFalse(SettingsPreferencesStore(defaults: defaults).preferences.showMediaCardLabels)

object.removeValue(forKey: "showMediaCardLabels")
let decoded = try JSONDecoder().decode(SettingsPreferences.self, from: data)
XCTAssertTrue(decoded.showMediaCardLabels)
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' -only-testing:OmniaTests/SettingsPreferencesTests test
```

Expected: compilation fails because `showMediaCardLabels` does not exist.

- [ ] **Step 3: Implement backward-compatible persistence**

Add `showMediaCardLabels` to the stored properties, coding keys, memberwise initializer, and `.default`. Decode it with:

```swift
showMediaCardLabels = try container.decodeIfPresent(
    Bool.self,
    forKey: .showMediaCardLabels
) ?? true
```

- [ ] **Step 4: Run tests and verify GREEN**

Run the focused command from Step 2. Expected: all `SettingsPreferencesTests` pass.

### Task 2: Define Shared Poster Metadata and Geometry

**Files:**
- Create: `Omnia/UI/Components/MediaPosterLabel.swift`
- Create: `OmniaTests/MediaPosterLabelTests.swift`
- Modify: `Omnia/UI/Components/MediaBrowseMetrics.swift`

**Interfaces:**
- Produces: `MediaPosterLabelContent.init(item: MediaItem)` with `title: String` and `metadata: String?`.
- Produces: `EnvironmentValues.showsMediaCardLabels: Bool`, default `true`.
- Produces: `MediaPosterLabel`, a shared full-title SwiftUI view.
- Produces: `MediaBrowseMetrics.posterHeight` and explicit shared poster geometry.

- [ ] **Step 1: Write failing label-content tests**

Create tests using literal `MediaItem` fixtures and assert:

```swift
XCTAssertEqual(content.title, "The Full Real Provider Title")
XCTAssertEqual(content.metadata, "2026 · Drama")
XCTAssertEqual(yearOnly.metadata, "2026")
XCTAssertEqual(genreOnly.metadata, "Drama")
XCTAssertNil(neither.metadata)
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' -only-testing:OmniaTests/MediaPosterLabelTests test
```

Expected: compilation fails because `MediaPosterLabelContent` does not exist.

- [ ] **Step 3: Implement label content, environment, and view**

Build metadata only from nonempty trimmed values. Use the first genre and join available values with `" · "`. Render the title without `lineLimit`; choose `.subheadline`, `.caption`, or `.caption2` from title length, then render optional metadata with `.caption` and `.foregroundStyle(.secondary)`.

Define an environment key whose default is `true`, and add explicit geometry:

```swift
static let posterHeight: CGFloat = posterWidth * 1.5
```

- [ ] **Step 4: Run tests and verify GREEN**

Run the focused command from Step 2. Expected: every label-content test passes.

### Task 3: Apply Labels to Shared Poster Cards

**Files:**
- Modify: `Omnia/UI/Components/MediaPoster.swift`
- Modify: `Omnia/App/OmniaApp.swift`
- Modify: `Omnia/Features/Settings/AppearanceSettingsView.swift`

**Interfaces:**
- Consumes: `SettingsPreferences.showMediaCardLabels`, `EnvironmentValues.showsMediaCardLabels`, `MediaPosterLabel`, and `MediaBrowseMetrics.posterHeight`.
- Produces: standard and ranked cards with identical artwork geometry and preference-controlled labels.

- [ ] **Step 1: Inject the live preference once**

Apply the environment value beside the existing model environments in `OmniaApp.rootContent`:

```swift
.environment(\.showsMediaCardLabels, settings.preferences.showMediaCardLabels)
```

- [ ] **Step 2: Add the native Appearance toggle**

Inject `SettingsPreferencesStore` into `AppearanceSettingsView` and add:

```swift
Toggle(
    "Show Details Under Posters",
    isOn: settings.binding(\.showMediaCardLabels)
)
```

Explain that it controls title, year, and genre below standard posters.

- [ ] **Step 3: Give standard posters fixed artwork and optional labels**

Wrap artwork and `MediaPosterLabel(item:)` in a leading `VStack`. Set poster artwork to explicit shared width and height. Keep the entire visible card inside the existing `NavigationLink`, and do not add a line limit to the title.

- [ ] **Step 4: Give ranked posters the same label composition**

Retain the rank badge overlay, use the identical fixed poster dimensions, and append the same `MediaPosterLabel` only when `showsMediaCardLabels` is enabled.

- [ ] **Step 5: Compile both platforms**

Run:

```sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' build
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'generic/platform=iOS Simulator' build
```

Expected: both commands exit 0.

### Task 4: Remove Anime Genre Browsing

**Files:**
- Modify: `Omnia/Features/Search/AnimeDiscoveryView.swift`

**Interfaces:**
- Consumes: the shared labeled `MediaPoster` automatically.
- Produces: Anime browse beginning directly with catalog shelves, with no Anime genre-directory route.

- [ ] **Step 1: Remove the visible genre link**

Delete the `SectionHeaderLink(title: "Browse Anime by Genre")` block from `animeBrowse`.

- [ ] **Step 2: Remove unreachable private genre code**

Delete `AnimeGenreDirectoryView` and `AnimeGenre`. Remove the unused `genre` parameter from `PagedAnimeCatalogView`, its task identity, and its metadata request so catalog paging calls:

```swift
await metadata.animeCatalogPage(category: category, genre: nil, page: nextPage)
```

- [ ] **Step 3: Verify the source no longer exposes Anime genre browsing**

Run:

```sh
rg -n 'Browse Anime by Genre|AnimeGenreDirectoryView|private enum AnimeGenre' Omnia/Features/Search/AnimeDiscoveryView.swift
```

Expected: no matches.

### Task 5: Full Verification and Review

**Files:**
- Review only all paths changed by Tasks 1–4.

**Interfaces:**
- Consumes: the completed preference, environment, card, and Anime changes.
- Produces: verified macOS and iOS builds with regression coverage.

- [ ] **Step 1: Run the full macOS test suite**

```sh
xcodebuild -quiet -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test
```

Expected: exit 0 with no failed tests.

- [ ] **Step 2: Run fresh platform builds**

```sh
xcodebuild -quiet -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' build
xcodebuild -quiet -project Omnia.xcodeproj -scheme Omnia -destination 'generic/platform=iOS Simulator' build
```

Expected: both commands exit 0.

- [ ] **Step 3: Check diff hygiene**

```sh
git diff --check
git status --short
```

Expected: no whitespace errors; only intended new changes are attributed to this plan while prior user work remains intact.

- [ ] **Step 4: Smoke-test presentation**

On macOS, inspect Home, Discover, Search results, Anime, Library, and one catalog page with the toggle on and off. Confirm fixed 2:3 poster geometry, equal horizontal spacing, full titles, `year · genre`, immediate toggle updates, and unchanged Continue Watching cards. Repeat at compact iPhone Simulator width for grid wrapping and Dynamic Type behavior.
