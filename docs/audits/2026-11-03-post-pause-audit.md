# Post-pause audit — 2026-11-03

Scope: every item in Dafa's summary of the work done between `82b222a` and `dfbf781` (16 commits).

Ratings: **Good** works as described. **Messy** works but has a defect or weak edge. **Broken** does not do what it claims. **Placeholder** stands in for the real thing.

Evidence labels:
- `ran` means I saw it on a simulator in this audit (iPhone 17 Pro, iPad Air 11-inch).
- `code` means source reading only.
- Mac: Debug build succeeded and the app launched. Screen capture is not permitted on this machine, so nothing on the Mac is visually verified.

Not checked anywhere, and needing a physical device: PiP, hardware volume, screen brightness, clear and tinted icon appearances, the accessibility matrix.

## Summary

| Rating | Count | Items |
|---|---:|---|
| Broken | 5 | Detail disk cache key, TVDB Enrichment toggle, trailer end, iPad sidebar over the hero (portrait), hero not behind the sidebar (landscape, round 3 item 3) |
| Placeholder | 1 | Continue Watching live preview |
| Messy | 7 | Volume value, trailer buffering shows paused, Mac Standard style, TVDB without a key, TVDB artwork-types request, empty TMDB seasons, dead `cardStyleWidth` |
| Limited | 1 | iOS PiP availability (platform limit, stated below) |

## Player and playback

| Item | Rating | Evidence |
|---|---|---|
| iPhone landscape controls, spacing, safe areas | Good | `ran`; `MacPlaybackChrome.swift:916` |
| Automatic landscape on entering playback, including loading | Good | `ran`: loading overlay, then landscape; `PlaybackPresentationHosts.swift:9-45` |
| Close while a stream loads | Good | `ran` (button visible during load, close tap not exercised); `PlaybackViews.swift` loading overlay |
| Gesture feedback at top centre | Good | `code`; `PlaybackViews.swift` `.overlay(alignment: .top)` |
| Volume and brightness percentages | Messy | `code`: `PlaybackSession.swift:820` reads `outputVolume` straight after moving the slider. That value updates asynchronously, so the stored value and HUD lag one step behind the drag |
| iOS volume tied to device output | Messy | `code`: same line. `IOSPlaybackSupport.swift:20` also does not report whether the slider moved |
| Brightness on the presenting display | Good | `code`; device needed to confirm |
| iOS PiP button and background handoff | Limited | `code`: `IOSPlaybackSupport.swift:126-150` only offers PiP when AVFoundation can open the source and it has no request headers. MKV and header-bearing streams stay inline, with the button disabled. This comes from mpv not exposing a PiP surface; it is not a bug. Device unverified |
| Fullscreen on tapping a playing hero trailer | Good | `code`; `HomeView.swift:676`, `MediaDetailView.swift:211` |
| Trailers kept out of history and tracking | Good | `code`: `purpose` guards at `PlaybackSession.swift` `persistProgress` and `captureContinueWatchingScene` |
| Trailer reaching its end | **Broken** | `code`: `startTrailer` (`PlaybackSession.swift:487`) has no end-of-item handling, so the player sits on the last frame until closed by hand |
| Trailer buffering state | Messy | `code`: `PlaybackSession.swift:1628` treats any non-playing status as paused, so buffering shows the pause overlay |
| Trailer black-screen fix | Good | `code`: `IOSPlaybackSupport.swift:157` attaches the layer before the PiP support check |
| Trailer Original/Fill | Good | `code`: `IOSPlaybackSupport.swift:344-346` |

## Subtitles and app icons

| Item | Rating | Evidence |
|---|---|---|
| iPhone/iPad subtitle settings | Good | `code`: shares the Mac preview and styling; `SubtitleAppearanceSettingsView.swift`. Page not opened in this audit |
| Adaptive iOS icon | Good | `code`: `IOSAppIcon.icon` vector layers. Clear and tinted appearances need a device |

## Ratings and metadata enrichment

| Item | Rating | Evidence |
|---|---|---|
| MDBList ratings in the iPhone portrait heroes, centred | Good | `code`: `PortraitHeroArtwork.swift:87,122`. Needs an MDBList key to see |
| TMDB external-ID matching and precedence | Good | `code`: `LiveMetadataStore.swift` `tmdbCounterpart`, unique-result guards |
| Enrichment cache identity | **Broken** | `code`: `OnDeviceMetadataService.swift:63` builds the identity with `Hasher`, which is seeded per process. `LiveMetadataStore.swift:1133` puts it in the on-disk cache key, so no entry is ever found after a relaunch and files accumulate unpruned |
| TVDB Enrichment toggle | **Broken** | `code`: `LiveMetadataStore.swift:235` only asks providers already listed under Metadata Sources. With TVDB not listed, turning the toggle on does nothing and nothing says why |
| TVDB without an API key | Messy | `code`: `MetadataSettingsView.swift` shows "On" with no key, and requests fail silently |
| TVDB artwork types | Messy | `code`: `OnDeviceMetadataService.swift:582` refetches a fixed list for every title |
| Partial-failure handling | Messy | `code`: `tmdbSeasons` dropped the non-empty filter, so a failed or unaired season shows as an empty tab. The merge already keeps the source's seasons, so the filter is safe to restore |
| Identifiers preserved through enrichment | Good | `code`: `IntegrationPreferences.swift` `mergingEnrichment` |

## Home and title-detail heroes

| Item | Rating | Evidence |
|---|---|---|
| Hero information stays visible during trailers | Good | `code`: `HomeView.swift` `hero` |
| Dynamic Home background | Good | `ran` on iPad and iPhone. Fresh profiles default off, profiles saved before the setting existed decode on (`HomeLayoutPreferences.swift:40,72`), as documented |

## Continue Watching

| Item | Rating | Evidence |
|---|---|---|
| Card layout, badge, progress, native type | Good | `code`: `ContinueWatchingCard.swift:154-212` |
| Independent size and corners, Match Poster | Good | `code`: `DisplayPreferences.swift` `ContinueWatchingCardPreferences` |
| Library grid fits custom sizes | Good | `code`: `LibraryView.swift` `LibrarySectionGridView` |
| Style illustrations restored | Good | `code`: `SettingsStylePreviews.swift` |
| Live preview | **Placeholder** | `code`: `SettingsStylePreviews.swift:146` always draws a made-up "Continue Watching Preview" item with a gradient and no artwork, so it never looks like a real card |
| `cardStyleWidth` | Messy | `code`: `ContinueWatchingCard.swift:39` has no callers |

## Collections and poster sizing

| Item | Rating | Evidence |
|---|---|---|
| Match Poster for shape, size, corners | Good | `code`: `DisplayPreferences.swift`, `CollectionViews.swift:60-66` |
| Preview scrolling, Reduce Motion | Good | `code`: `CollectionsSettingsView.swift` |
| Landscape sizes on cards, shelves, grids | Good | `code`: `MediaBrowseMetrics.swift`, `MediaPoster.swift` |

## Onboarding

| Item | Rating | Evidence |
|---|---|---|
| Poster wall uses real catalog art | Good | `ran` on iPad with the onboarding flag reset |
| App preview, default catalog fallback, isolated metadata | Good | `code`: `OnboardingView.swift` `OnboardingPreviewSource`. Preview step not stepped through |
| Loading, unavailable, retry | Good | `code`; offline not exercised |

## Search and Discover

| Item | Rating | Evidence |
|---|---|---|
| Search grid width, narrow clamping | Good | `code`: `SearchView.swift` |
| iOS search field placement | Good | `code`: `DiscoverView.swift`, `SearchView.swift` |
| Deterministic add-on order | Good | `code`: `StremioAddonClient.swift:200` |
| Reload identities, empty states, retry, pagination recovery | Good | `code`: `DiscoverView.swift`, `AddonCatalogBrowseView.swift`. Live Xperience not verified |

## Navigation

| Item | Rating | Evidence |
|---|---|---|
| iPhone native tabs only | Good | `ran`; `OmniaRootView.swift` `usesNuvioBar` |
| iPad sidebar over the hero, portrait | **Broken** | `ran`: the sidebar opens by default and covers the logo, synopsis and buttons, with no way to reach them until it is dismissed |
| Hero and content behind the sidebar, landscape (round 3 item 3) | **Broken** | `ran`: content starts at the sidebar's edge and the sidebar sits on a blank area. Not done |
| Mac Top Bar Style | Messy | `code`: `DisplayPreferences.swift:115` omits Standard on the Mac, yet `OmniaRootView` still renders it, so a saved Standard shows no selection |

## Fix order

1. Broken and Placeholder: cache key, TVDB toggle, trailer end, Continue Watching preview.
2. iPad: sidebar and hero.
3. Messy: volume value, trailer buffering, Mac Standard, TVDB key notice, artwork types, empty seasons, dead code.

PiP on MKV stays as described. A real fix needs an mpv sample-buffer output, which is separate work.
