# Apple TV Interactions and Watch State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver Apple-native macOS navigation, media actions, context menus, source selection, and playback chrome backed by durable movie and episode watch state.

**Architecture:** Extend the existing SwiftData local-media record with an optional encoded watch-state value so the migration remains additive. Centralize watch commands in `LocalMediaStore`, expose them through `OmniaStore`, and attach a shared native context-menu component to media cards. Keep visual state in small presentation types while native SwiftUI/AppKit controls own material, focus, menu, and fullscreen behavior.

**Tech Stack:** SwiftUI, AppKit, SwiftData, Observation, XCTest, libmpv bridge

**Spec:** `docs/superpowers/specs/2026-09-07-apple-tv-interactions-watch-state-design.md`

## Global Constraints

- Preserve the existing dirty worktree and do not stage, reset, or rewrite unrelated changes.
- Use current Apple Design Resources, HIG, native Liquid Glass, and SF Symbols.
- macOS and iOS deployment targets are 26.5; no compatibility shim for older SDKs is needed.
- Test-first: every behavior change must have an observed failing test before production code.
- Do not add a dependency or mutate hosted Supabase state.

---

### Task 1: Persistent watch-state domain

**Files:**
- Create: `Omnia/Domain/Library/MediaWatchState.swift`
- Modify: `Omnia/Data/Library/LocalMediaModels.swift`
- Modify: `Omnia/Data/Library/LocalMediaStore.swift`
- Modify: `Omnia/Domain/Library/LocalMediaBackupDocument.swift`
- Test: `OmniaTests/LocalMediaStoreTests.swift`
- Test: `OmniaTests/LocalMediaBackupDocumentTests.swift`

**Interfaces:**
- Produces: `MediaEpisodeKey`, `LocalMediaWatchState`, and `LocalMediaWatchCommand`.
- Produces: `LocalMediaStoring.applyWatchCommand(_:to:episodes:at:) async throws`.
- Produces: `LocalMediaSnapshot.watchState`.

- [ ] **Step 1: Write failing store tests** for movie watched/unwatched, current episode advance/reset, season operations, through-here operations, previous-episode revert, progress removal preserving Library, and idempotence. Each fixture supplies a literal ordered episode list.
- [ ] **Step 2: Run the focused XCTest class** and confirm failures are caused by the missing watch-state API.
- [ ] **Step 3: Add the smallest domain representation**:

```swift
struct MediaEpisodeKey: Codable, Hashable, Sendable {
    let id: String
    let seasonNumber: Int
    let episodeNumber: Int
}

struct LocalMediaWatchState: Codable, Equatable, Sendable {
    var movieWatched: Bool?
    var episodeStates: [MediaEpisodeKey: Bool]
}
```

Implement commands as deterministic transitions over the literal ordered episodes. Store the state in optional `watchStateData` on `LocalMediaRecord`; missing data decodes as an empty state.
- [ ] **Step 4: Run focused tests until green**, then run all local-media backup/destructive tests.

### Task 2: Store-facing media actions and native context menus

**Files:**
- Create: `Omnia/UI/Components/MediaContextMenu.swift`
- Modify: `Omnia/App/OmniaStore.swift`
- Modify: `Omnia/UI/Components/MediaPoster.swift`
- Modify: `Omnia/Features/Home/HomeView.swift`
- Modify: `Omnia/Features/Library/MediaDetailView.swift`
- Modify: `Omnia/UI/Components/HeroActionRow.swift`
- Test: `OmniaTests/MediaContextMenuTests.swift`
- Test: `OmniaTests/OmniaStoreTests.swift`

**Interfaces:**
- Consumes: `LocalMediaWatchCommand` and `LocalMediaStoring.applyWatchCommand`.
- Produces: `MediaContextMenuPresentation.commands(for:placement:)` with literal ordered command values.
- Produces: `OmniaStore.applyWatchCommand(_:to:episodes:)`, `setSaved(_:isIncluded:)`, and `watchState(for:)`.

- [ ] **Step 1: Write failing presentation and store tests** that catch wrong command order, wrong movie/show labels, missing simultaneous add/remove commands, and state refresh after persistence.
- [ ] **Step 2: Run focused tests** and observe expected missing-symbol/API failures.
- [ ] **Step 3: Implement native `.contextMenu` content** with `Label`/SF Symbols and `Divider`; use system selection rather than custom menu backgrounds. Resolve full episode metadata before series bulk commands when the lightweight card does not contain it.
- [x] **Step 4: Add one circular watched-state toggle to the detail hero** beside the existing playback and single circular Library action, keeping the cluster on the same identity-column axis as logo, synopsis, and ratings. Use `eye`/Mark as Watched while unwatched and `eye.slash`/Mark as Unwatched while watched; do not add a second watch control.
- [ ] **Step 5: Run focused tests until green** and manually verify a secondary click opens the native menu.

### Task 3: Shared Liquid Glass interactions and native sidebar

**Files:**
- Modify: `Omnia/UI/Components/OmniaLiquidGlass.swift`
- Modify: `Omnia/App/OmniaRootView.swift`
- Modify: `Omnia/App/AppDestination.swift`
- Modify: `Omnia/Platform/macOS/WindowChrome.swift`
- Modify: `Omnia/Features/Settings/AddonsSettingsView.swift`
- Modify: `Omnia/Features/Library/MediaDetailView.swift`
- Modify: `Omnia/UI/Components/HeroActionRow.swift`
- Test: `OmniaTests/PlaybackChromePresentationTests.swift`
- Test: `OmniaTests/AppDestinationTests.swift`

**Interfaces:**
- Produces: a shared `OmniaGlassInteractionState` whose control role lifts and darkens, panel-row role darkens without lift, and timeline/sidebar-surface role remains static.
- Produces: outlined `AppDestination.symbolName` values.

- [ ] **Step 1: Write failing tests** for role-specific lift/darkening and outlined navigation symbols.
- [ ] **Step 2: Run focused tests** and confirm the old transform/material rules fail.
- [ ] **Step 3: Implement an interactive primitive button style** using `.glassEffect(.clear.interactive(), in:)`, full-shape `contentShape`, pressed configuration, hover state, and Reduce Motion. Do not stack glass on a child label and its parent button.
- [ ] **Step 4: Remove custom sidebar toolbar items and AppKit duplicate-removal code**, allowing the single system sidebar toggle and sidebar surface to render natively.
- [ ] **Step 5: Apply the shared style to hero, Back, Add Add-on, and playback controls**, then run focused tests until green.

### Task 4: Playback panels, subtitle style, and exclusive fullscreen geometry

**Files:**
- Modify: `Omnia/Platform/Playback/PlaybackSession.swift`
- Modify: `Omnia/Platform/Playback/MPVPlayerController.m`
- Modify: `Omnia/Features/Playback/MacPlaybackChrome.swift`
- Test: `OmniaTests/PlaybackSessionTests.swift`
- Test: `OmniaTests/PlaybackChromePresentationTests.swift`
- Test: `OmniaTests/MPVPlaybackIntegrationTests.swift`

**Interfaces:**
- Produces: `PlaybackSubtitleBackground`, plus `shadowOpacity`, `shadowBlurRadius`, and `background` on `PlaybackSubtitleStyle`.
- Produces: `MacPlaybackChromeInsets.top(isExclusiveFullScreen:)`.
- Consumes: libmpv subtitle properties through `setSubtitleStyle`.

- [ ] **Step 1: Write failing tests** for subtitle-value clamping/mapping, panel height with the added controls, full-screen top inset, and timeline/static versus control/interactive roles.
- [ ] **Step 2: Run focused tests** and observe failures from missing fields and mappings.
- [ ] **Step 3: Extend the session and mpv mapping** so shadow opacity/radius and background choices apply live using bounded values supported by the bundled libmpv.
- [ ] **Step 4: Recompose each options panel as one continuous regular glass surface**. Rows have no resting glass or lift and darken only on hover/press. Keep content-sized scrolling bounds.
- [ ] **Step 5: Move top controls to the exclusive-fullscreen safe edge**, retain windowed padding, and ensure slider editing keeps chrome visible.
- [ ] **Step 6: Run playback tests until green** and perform runtime fullscreen, PiP, hit-target, slider, and panel checks.

### Task 5: Continuous-glass source selector

**Files:**
- Modify: `Omnia/Features/Playback/PlaybackViews.swift`
- Test: `OmniaTests/PlaybackSourcePresentationTests.swift`

**Interfaces:**
- Produces: `PlaybackSourceSheetPresentation` role decisions for panel, rows, and filters.

- [ ] **Step 1: Write failing tests** proving source rows and filters use no lift, transparent rest state, and darken for hover/press.
- [ ] **Step 2: Run the focused tests** and observe the previous per-filter/per-row glass treatment fail.
- [ ] **Step 3: Give the macOS sheet one regular glass container** and replace resting row/filter glass with content shapes plus no-lift darkening interaction. Preserve loading, empty, status, retry, resolver, consent, and cancellation behavior.
- [ ] **Step 4: Run focused tests until green** and manually verify source selection remains responsive.

### Task 6: Documentation and full verification

**Files:**
- Modify: `DESIGN.md`
- Modify only if required by new source files: `Omnia.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes every completed task.
- Produces a verified, documented implementation with no hosted changes.

- [ ] **Step 1: Update DESIGN.md** from intended/current-gap language only where runtime and test evidence proves the behavior.
- [ ] **Step 2: Run `xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test`.**
- [ ] **Step 3: Run macOS and generic iOS Simulator builds.**
- [ ] **Step 4: Run `git diff --check` and review only the intended paths**, preserving every unrelated user change.
- [ ] **Step 5: Smoke-test macOS sidebar, detail actions, card context menus, source sheet, playback panels, volume/timeline dragging, PiP, and exclusive fullscreen.**
