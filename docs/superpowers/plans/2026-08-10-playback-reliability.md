# Playback Reliability Implementation Plan

**Goal:** Restore reliable source discovery and macOS video playback, then expose selectable audio and subtitle tracks.

**Root causes:** TVDB detail normalization discards `remoteIds`, so IMDb-oriented add-ons cannot match many series. The source sheet can also query before provider details finish loading. macOS playback embeds mpv through the older `wid` path, which mpv documents as fragile on macOS. Finally, the bridge and SwiftUI surface have cycle commands but no track-list state or selection API.

## 1. Preserve cross-provider source identifiers

- Add a pure TVDB remote-ID normalizer and Deno regression tests using official `RemoteID` fixtures.
- Include IMDb/TMDB identities in normalized TVDB details while retaining the canonical TVDB ID.
- Enrich the source sheet's item through `LiveMetadataStore` immediately before add-on resolution, merging existing add-on IDs so an early Play tap cannot race detail loading.
- Add XCTest coverage for the merged identifier order and episode suffixes.

## 2. Replace macOS window embedding

- Replace the plain `NSView`/`wid` attachment with an `NSOpenGLView` that owns an mpv render context.
- Initialize `vo=libmpv`, create the render context with the current CGL context, schedule redraws on the main thread, and free the render context before destroying the core.
- Keep the existing SwiftUI host and transport API stable.

## 3. Add real track selectors

- Introduce an Objective-C track value type and read mpv's `track-list` property.
- Expose audio/subtitle arrays plus explicit `aid`/`sid` selection, including a subtitle Off state.
- Mirror track state into `PlaybackSession` during its existing refresh loop.
- Replace the cycle buttons with SwiftUI `Menu` controls that show labels, languages, and selected-state checkmarks.

## 4. Verify

- Run Deno unit/type checks and macOS XCTest.
- Build Debug and Release with package resolution disabled.
- Launch a local multi-track media fixture or known-safe stream and verify video rendering, audio switching, subtitle selection/off, seeking, and cleanup.

