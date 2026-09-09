# Apple TV Interactions and Watch State Design

## Goal

Bring Omnia's macOS navigation, media actions, context menus, source selector, and libmpv playback chrome into one coherent Apple-native interaction language while making every watch-state command durable and functional.

## Apple-native surface rules

- Use current SwiftUI/AppKit system components, SF Symbols, and Liquid Glass.
- Controls floating over video use clear interactive Liquid Glass. Text-heavy option panels use one continuous regular Liquid Glass surface.
- At rest, symbols are monochrome. Hovered and pressed controls lift slightly and darken, except where this specification explicitly disables lift.
- Playback timeline is static: no lift and no hover/press darkening.
- Audio, subtitle, speed, and source-selector panels never lift. Their panel is one continuous glass surface; rows are transparent at rest and darken on hover or press without separate resting pills.
- The complete visible control shape is the hit target.
- Respect Reduce Motion, Reduce Transparency, Increase Contrast, keyboard focus, VoiceOver, and system appearance.

## Sidebar

- Restore the single system-owned sidebar toggle and remove all custom/duplicate toggles and AppKit removal code.
- The system sidebar supplies its native glass surface. The visible sidebar has no lift.
- When the system toggle is displayed outside a collapsed sidebar, it uses the system's native toolbar interaction treatment; no second control is introduced.
- Use outlined sidebar symbols, including `house` and `rectangle.stack`.
- Selected navigation uses a brighter gray selection surface, white text, and the system accent color for the symbol.

## Title-detail actions

Show Play/Resume/Rewatch, one circular watched-state toggle, and the existing single circular Add/Remove Library action together in the hero identity column. The watch toggle uses `eye` with the accessible action Mark as Watched for unwatched content, then `eye.slash` with Mark as Unwatched for watched content. Align the group with the transparent logo, synopsis, and MDBList ratings. Do not expose a second watch control on the detail page. All commands persist through the local media store.

## Native media context menus

Use SwiftUI's native macOS context menu so a right-click or two-finger trackpad tap presents the system menu.

Continue Watching movie commands:

1. Go to Movie
2. Separator
3. Mark as Watched
4. Mark as Unwatched
5. Remove Watch Progress

Continue Watching series commands:

1. Go to Show
2. Separator
3. Mark as Watched
4. Mark as Unwatched
5. Season Watched
6. Season Unwatched
7. Revert to Previous Episode
8. All Episodes up to Here Watched
9. All Episodes up to Here Unwatched

Other movie-card commands are Go to Movie, Add to Watchlist, and Remove from Watchlist. Other series-card commands are Go to Show, Add to Watchlist, and Remove from Watchlist. Both opposing actions remain visible; an already-satisfied action is harmless and idempotent. Watchlist means Omnia Library.

## Watch semantics

- Movie watched records watched status, clears resume progress, and preserves Library membership.
- Movie unwatched records unwatched status and resets resume progress.
- Current episode watched records watched status and advances Continue Watching to the next ordered episode when one exists.
- Current episode unwatched records unwatched status and makes it the resume target.
- Season commands affect every episode in the current season.
- Through-here commands affect the current episode and every earlier episode in season/episode order.
- Revert makes the immediately previous episode unwatched and the new resume target.
- Remove Watch Progress clears resume/progress without removing Library membership or watched history.

## Playback

- Keep the Apple TV hierarchy: top-left Close/PiP/Fullscreen, top-right Volume, centered back 10/play-pause/forward 10, title left and Audio/Subtitles/Speed right above the timeline.
- Do not add a visible full-player dimming rectangle.
- Fullscreen enters/exits the actual macOS fullscreen Space. In exclusive fullscreen, top controls move close to the top safe edge; windowed mode keeps ordinary window padding.
- Volume and timeline sliders update smoothly and keep chrome visible while dragging.
- Audio, Subtitles, and Speed panels are compact and content-sized.
- Subtitle Style includes native font selection, size, scale, position, shadow opacity, shadow blur/radius, and background selection, applied live to libmpv.

## Source selector

On macOS, the source-selector sheet uses one continuous regular Liquid Glass surface. Rows and filter controls remain transparent at rest and only darken on hover/press, without lift. Loading, empty, partial, error, retry, resolving, disabled, and destructive/consent states remain functional and readable.

## Verification

- Unit tests cover persistent movie/episode state transitions, bulk operations, idempotence, subtitle normalization, panel sizing, static timeline behavior, and outlined navigation symbols.
- macOS runtime checks cover native context menus, full-shape hit targets, hover/press response, source and playback panels, slider interaction, sidebar uniqueness, PiP, and exclusive fullscreen transitions.
- Run the macOS test suite and builds for macOS and generic iOS Simulator, then `git diff --check`.
