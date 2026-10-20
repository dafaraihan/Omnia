# Shared Poster Labels and Anime Card Consistency

> **Automated-validation policy:** Follow the repository-root `AGENTS.md`. Instructions below that call for automated test targets, suites, fixtures, or scripts are historical and superseded; use builds, static checks, and focused manual evidence instead.

## Goal

Make movie and series poster cards consistent across Omnia, ensure Anime cards identify their titles, and let the user hide or show poster metadata from Settings → Appearance. The implementation retains native SwiftUI presentation and the existing navigation behavior.

## Scope

- Remove the “Browse Anime by Genre” entry from the Anime browse page.
- Apply one shared poster-and-label composition to standard `MediaPoster` and `RankedMediaPoster` instances on Home, Discover, Search, Anime, Library, add-on catalogs, metadata catalogs, and related-title shelves.
- Keep Continue Watching unchanged because it already owns a resume-specific landscape label.
- Keep specialized upcoming episode, episode, person, genre-directory, and video cards unchanged because they are not movie/series poster cards and already expose purpose-specific identity.
- Add an enabled-by-default “Show Details Under Posters” toggle to Settings → Appearance.

## Poster and Label Design

Every standard and ranked media card uses the shared 2:3 poster width, height, continuous corner radius, and horizontal spacing from `MediaBrowseMetrics`. Artwork is explicitly constrained to this geometry so remote image dimensions cannot alter card size.

When labels are enabled, the label appears below the artwork at the same fixed width:

1. The exact `MediaItem.title` is shown in full. It is never abbreviated, rewritten, or truncated. It wraps as needed and uses smaller native system text styles for longer titles.
2. A secondary line shows the available release year and first genre, separated by a centered dot. If either value is unavailable, the remaining value is shown without placeholder text or a dangling separator.

The title uses semantic primary foreground styling. Year and genre use semantic secondary foreground styling. Typography uses SwiftUI system text styles, preserving San Francisco, accessibility scaling, appearance, and contrast behavior.

Artwork dimensions and horizontal gaps remain identical regardless of title length. In a grid, each row naturally adopts the height of its tallest full title while keeping every poster top-aligned. In a horizontal shelf, posters remain top-aligned and equally spaced while labels may wrap independently below them.

Top 10 cards retain their existing rank treatment and gain the same label below the poster. Continue Watching ignores the new preference and keeps its existing title, year, progress, and episode presentation.

## Preference and Data Flow

`SettingsPreferences` gains a persisted Boolean preference for showing poster details. Its default is `true`, and decoding older saved settings that lack the field also resolves to `true`.

`AppearanceSettingsView` exposes the preference as a native `Toggle` named “Show Details Under Posters,” with explanatory footer text. The root view passes the current value through a lightweight SwiftUI environment value so shared poster components update immediately without requiring every feature screen to duplicate settings wiring.

`MediaPoster` and `RankedMediaPoster` read that environment value and render the shared label only when enabled. This keeps all pages synchronized and avoids page-specific card variants.

## Anime Changes

The Anime browse page starts directly with its provider-backed catalog shelves after loading. The “Browse Anime by Genre” link and its now-unreachable private genre directory types are removed. Anime search results, shelves, and paged catalog results use the same shared labeled poster component as other media pages.

## Empty and Partial Metadata

The title is always rendered from the real `MediaItem.title`. Missing artwork continues to use the existing semantic artwork fallback. Missing year or genres never suppress the title and never produce invented metadata. If both are missing, only the title is shown.

## Accessibility

The navigation link continues to expose the full media title as its accessibility label. The visible metadata follows the artwork in reading order. Text is not embedded into artwork and remains available to Dynamic Type, Increase Contrast, and light/dark appearance. Full titles may increase card height rather than becoming inaccessible through truncation.

## Verification

- Unit-test the poster metadata formatter with complete, partial, and missing year/genre values.
- Unit-test the enabled default, persistence round trip, and backward-compatible decoding of the poster-label preference.
- Confirm standard and ranked posters share the same label behavior while Continue Watching remains independent.
- Build and test the macOS app target.
- Build the iOS Simulator target.
- Smoke-test Home, Discover, Search, Anime, Library, and a catalog page at representative Mac and compact iPhone widths, with labels enabled and disabled.
