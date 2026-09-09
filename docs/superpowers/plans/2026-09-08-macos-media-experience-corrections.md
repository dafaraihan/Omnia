# macOS Media Experience Corrections Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correct Omnia's macOS hero composition, browsing filters, Library and Settings layouts, subtitle persistence, resume behavior, and playback prompt placement without regressing the existing player or navigation.

**Architecture:** Keep one root-owned window hero, represent Library and Discover filtering as pure presentation models, use `SettingsPreferences` as the durable subtitle source of truth, and carry an explicit playback launch/resume intent through source resolution into a readiness-aware player seek. Keep macOS layout policy in small testable value types while SwiftUI views render those policies.

**Tech Stack:** Swift 6, SwiftUI, AppKit, XCTest, libmpv/Objective-C bridge.

**Spec:** `docs/superpowers/specs/2026-09-08-macos-media-experience-corrections-design.md`

## Global Constraints

- macOS only; do not implement or build iPhone/iPad changes.
- Preserve existing sidebar, context-menu, source-resolution, aspect-ratio, playback, and watch-state behavior unless the spec explicitly changes it.
- Write focused failing XCTest coverage before each production change.
- Do not add dependencies or modify hosted services.
- Preserve unrelated dirty-worktree changes and do not commit implementation work.

---

### Task 1: Single Window Hero and Accent Surfaces

**Files:**
- Modify: `Omnia/UI/Components/HeroBackdropEnvironment.swift`
- Modify: `Omnia/App/OmniaRootView.swift`
- Modify: `Omnia/Features/Home/HomeView.swift`
- Modify: `Omnia/Features/Library/MediaDetailView.swift`
- Create: `OmniaTests/HeroBackdropPresentationTests.swift`

**Interfaces:**
- Produces: `HeroBackdropPresentation.drawsLocalArtwork(on:)` and `HeroBackdropPresentation.usesArtworkAccentBelowHero`.
- Consumes: the existing `reportWindowHeroBackdrop` environment callback and `HeroAccentBackground`.

- [ ] Add tests asserting macOS uses the root artwork only and title detail uses the artwork accent below its hero.
- [ ] Run `xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test -only-testing:OmniaTests/HeroBackdropPresentationTests` and confirm the missing presentation contract fails.
- [ ] Add the presentation policy, replace macOS-local `FeaturedBackdrop` instances with transparent hero canvas content, keep iOS branches unchanged, and apply `HeroAccentBackground(item:)` beneath title details.
- [ ] Re-run the focused test and confirm it passes.

### Task 2: Darker Glass Modals

**Files:**
- Modify: `Omnia/UI/Components/OmniaLiquidGlass.swift`
- Modify: `Omnia/Features/Playback/PlaybackViews.swift`
- Modify: `Omnia/Features/Library/MediaDetailView.swift`
- Modify: `OmniaTests/PlaybackChromePresentationTests.swift`

**Interfaces:**
- Produces: a single `OmniaLiquidGlassSurfaceRole.modal` treatment with adaptive dark tint and readable foreground contrast.
- Consumes: existing `.omniaGlassModal` and source/synopsis modal content.

- [ ] Add a presentation test proving modal glass uses the dark, continuous role and does not use playback timeline or opaque panel treatment.
- [ ] Run the focused test and confirm it fails for the absent modal role.
- [ ] Add the modal role and apply it once at each modal boundary without adding nested glass panels.
- [ ] Re-run the focused test and confirm it passes.

### Task 3: Toolbar Titles and Settings Layout

**Files:**
- Modify: `Omnia/App/OmniaRootView.swift`
- Modify: `Omnia/Features/Settings/SettingsView.swift`
- Modify: `Omnia/Features/Settings/SettingsSupportViews.swift`
- Modify: root and destination views that currently suppress or duplicate navigation titles.
- Modify: `OmniaTests/SettingsPresentationTests.swift`

**Interfaces:**
- Produces: `MacSettingsLayout.contentWidth(for:)` and `MacSettingsLayout.leadingOffset` supporting a wide, left-aligned detail pane.
- Consumes: standard `.navigationTitle`, leading toolbar placement, and trailing `.searchable`/filter controls.

- [ ] Replace the existing centered-layout expectations with failing tests for responsive width and leading alignment.
- [ ] Run `SettingsPresentationTests` and confirm the old 680-point centered contract fails.
- [ ] Update the shared Settings container; remove the duplicate in-page Settings heading; place search in the macOS toolbar; ensure every destination/subpage exposes its navigation title.
- [ ] Re-run `SettingsPresentationTests` and relevant `SettingsRouteTests`.

### Task 4: Library Shelves and Global Filtering

**Files:**
- Modify: `Omnia/Features/Library/LibraryView.swift`
- Reuse: `Omnia/Features/Home/HomeView.swift` Continue Watching presentation components by moving shared pieces only if required.
- Modify: `Omnia/UI/Components/MediaPoster.swift`
- Create: `Omnia/UI/Components/LibraryCollectionPresentation.swift`
- Create: `OmniaTests/LibraryCollectionPresentationTests.swift`

**Interfaces:**
- Produces: `LibraryCollectionPresentation.sections(snapshots:kind:sort:) -> [LibrarySection]` with `.myList`, `.continueWatching`, and `.rewatch` mutually exclusive sections.
- Consumes: `LocalMediaSnapshot.isInWatchlist`, progress, watch state, saved date, and last-played date.

- [ ] Add tests for all state transitions, explicit watchlist membership, unfinished progress priority, completed priority, kind filtering, and ordering.
- [ ] Run the focused test and confirm the missing section model fails.
- [ ] Implement the pure section model, render three horizontal shelves, add dedicated grid destinations, and reuse the existing Continue Watching resume card behavior.
- [ ] Move the native filter menu trailing; use white unfilled macOS SF Symbols; apply one selected filter state to all sections.
- [ ] Re-run focused tests and context-menu/watch-state tests.

### Task 5: Functional Discover and Catalog Filtering

**Files:**
- Modify: `Omnia/Features/Search/DiscoverView.swift`
- Modify: `Omnia/Features/Search/AddonCatalogBrowseView.swift`
- Modify: `Omnia/Features/Settings/CatalogsSettingsView.swift`
- Modify: `Omnia/App/OmniaStore.swift` only if observable catalog state propagation requires it.
- Create: `Omnia/Features/Search/DiscoverFilterPresentation.swift`
- Create: `OmniaTests/DiscoverFilterPresentationTests.swift`
- Modify: `OmniaTests/StremioAddonClientTests.swift` only for advertised-extra request behavior.

**Interfaces:**
- Produces: `DiscoverFilterState` containing genre, enabled catalog IDs, kind, release period, selected year, and date sort; `DiscoverFilterPresentation.apply(_:to:)` for safe local fallback.
- Consumes: `HomeShelfPreferences`, installed add-on catalog enabled state, provider genre IDs, and only manifest-advertised Stremio extras.

- [ ] Add tests showing catalog toggles remove/restore shelves immediately, kind removes incompatible shelves, date filters and sorts, genre filters available metadata, and unsupported extras are never sent.
- [ ] Run focused Discover and Stremio tests and confirm failures against the visual-only behavior.
- [ ] Add native trailing Genre/Catalogs/Kind/Date menus, implement the approved release-period and sort choices, connect catalog toggles to rendered shelves, reset/cancel stale loads, and add empty/partial/retry states.
- [ ] Re-run focused tests.

### Task 6: Durable Subtitle Preferences

**Files:**
- Modify: `Omnia/Domain/Settings/SettingsPreferences.swift`
- Modify: `Omnia/Features/Settings/SubtitleAppearanceSettingsView.swift`
- Modify: `Omnia/Features/Playback/MacPlaybackChrome.swift`
- Modify: `Omnia/Platform/Playback/PlaybackSession.swift`
- Modify: `Omnia/App/OmniaApp.swift` or playback environment wiring only as required for the preference update callback.
- Modify: `OmniaTests/SettingsPreferencesTests.swift`
- Modify: `OmniaTests/PlaybackSessionTests.swift`
- Modify: `OmniaTests/PlaybackMediaSelectionPolicyTests.swift`

**Interfaces:**
- Produces: a Codable normalized subtitle preference value covering enabled state, languages, font name/size, scale, position, background, shadow opacity, and shadow blur; `PlaybackSession` emits preference mutations without persisting track IDs.
- Consumes: `SettingsPreferencesStore.update`, MPV language selection, and MPV subtitle style properties.

- [ ] Add migration/default/round-trip tests and tests mapping preferences into MPV style and normalized language selection.
- [ ] Run the focused tests and confirm missing fields/mappings fail.
- [ ] Extend preferences compatibly with decode defaults, expose the same controls in Settings, initialize each playback session from them, and persist playback-panel changes through a narrow update callback.
- [ ] Re-run focused tests.

### Task 7: Reliable Resume Persistence and Initial Seek

**Files:**
- Modify: `Omnia/Platform/Playback/PlaybackSession.swift`
- Modify: `Omnia/Platform/Playback/MPVPlayerController.h`
- Modify: `Omnia/Platform/Playback/MPVPlayerController.m`
- Modify: `Omnia/App/OmniaStore.swift`
- Modify: `Omnia/Features/Playback/PlaybackViews.swift`
- Modify: `OmniaTests/PlaybackSessionTests.swift`
- Modify: `OmniaTests/MPVPlaybackIntegrationTests.swift`
- Modify: `OmniaTests/LocalMediaStoreTests.swift`
- Reuse: `OmniaTests/ResumeProgressPresentationTests.swift`

**Interfaces:**
- Produces: an explicit pending initial seek applied after MPV reports a seekable file; a forced progress flush on stop/replacement; serialized local progress writes for the active media/episode.
- Consumes: `MediaDetailPlaybackIntent.resumeAt`, `PlaybackSourceSheet.resumeAt`, and `OmniaStore.recordPlayback`.

- [ ] Add tests reproducing a seek requested before MPV readiness, forced final progress persistence, ordered writes, movie resume, and series/anime episode+timestamp resume.
- [ ] Run focused tests and confirm the readiness/persistence regressions fail.
- [ ] Implement pending initial seek and forced flush without changing Play/Rewatch targets; make local writes ordered and prevent stale refreshes from replacing newer progress.
- [ ] Re-run focused session, integration, local-store, and resume-presentation tests.

### Task 8: Skip Intro and Up Next Layout

**Files:**
- Modify: `Omnia/Features/Playback/PlaybackViews.swift`
- Modify: `Omnia/Features/Playback/MacPlaybackChrome.swift`
- Modify: `OmniaTests/PlaybackAutomationControllerTests.swift`
- Modify: `OmniaTests/PlaybackChromePresentationTests.swift`
- Reuse: `OmniaTests/IntroDBClientTests.swift`

**Interfaces:**
- Produces: `MacPlaybackPromptLayout` anchors for `.skipIntro` above metadata and `.upNext` above option controls; prompt actions supplied to `MacPlaybackChrome` from `PlaybackExperienceView`.
- Consumes: `PlaybackAutomationController`, IntroDB segments, `playback.nextEpisode`, and existing `.omniaCapsuleGlassButton()`.

- [ ] Add failing tests for prompt anchor separation, automation visibility, IntroDB identity, and next-episode action delivery.
- [ ] Run focused automation/chrome/IntroDB tests and confirm the missing layout contract fails.
- [ ] Move prompt rendering into Mac playback chrome, apply interactive capsule glass with full hit regions, and remove the overlapping bottom-trailing prominent buttons.
- [ ] Re-run focused tests.

### Task 9: Full macOS Verification

**Files:**
- Review only all intended paths from Tasks 1-8.

**Interfaces:**
- Consumes: every preceding task's passing tests and the approved spec.
- Produces: a verified macOS build and an evidence-based handoff.

- [ ] Run the full macOS XCTest suite.
- [ ] Run `xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' build`.
- [ ] Run `git diff --check` and review only intended paths without staging unrelated work.
- [ ] Smoke-test Home and title details with sidebar shown/hidden; all Library and Discover filter combinations; Catalog toggle propagation; Settings root/subpages/search; persisted subtitle changes; movie and episodic Resume through source selection; Skip Intro and Up Next placement.
- [ ] Report any provider/device behavior that remains unverified. Do not run an iOS build.
