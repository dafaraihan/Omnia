# macOS Playback Track Switching and Timeline Preview Design

> **Automated-validation policy:** Follow the repository-root `AGENTS.md`. Instructions below that call for automated test targets, suites, fixtures, or scripts are historical and superseded; use builds, static checks, and focused manual evidence instead.

## Scope

This change is macOS-only. It improves three existing surfaces without replacing Omnia's playback chrome or changing its navigation:

1. Audio and subtitle track changes must not issue a pause or block the main actor.
2. Hovering the playback timeline should show a preview for the hovered timestamp.
3. Continue Watching cards for episodic media should show the exact resume episode beneath the title and year.

The work does not add a hosted media provider, upload media, pre-scan complete remote files, or introduce a new binary dependency.

## Continue Watching Presentation

Movies keep their current two-line label:

```text
Movie Title
2026
```

Series, television, and anime use:

```text
Reacher · 2022
S4 E1 · In the Name of the Mother
```

The first line uses the media title and release year. The second uses the persisted resume season, episode number, and episode title. If the stored snapshot has no trustworthy episode title, Omnia shows only `S4 E1`; it must not invent a title. VoiceOver exposes the same information in full words.

This is presentation-only. It does not change resume targeting or watch progress.

## Non-Blocking Track Switching

The Objective-C libmpv bridge will replace synchronous `aid` and `sid` property writes with asynchronous property requests. Each request receives an identifier so a late reply from an older selection cannot overwrite a newer selection.

Omnia never changes the user's paused state during a track request. If playback was running, video remains running while libmpv activates the new track. A remote audio track may still have a short audible gap while libmpv fetches, decodes, and synchronizes it; the app must not represent that gap as a user pause. Subtitle changes should be seamless when the subtitle track is already embedded or cached.

The selected-row state continues to come from libmpv's observed `aid`, `sid`, and `track-list` properties. A failed request retains the last confirmed selection and produces a bounded, non-secret playback error. Subtitle preferences are persisted only for the confirmed selection.

## Timeline Preview Architecture

### Source order

`PlaybackTimelinePreviewService` resolves previews in this order:

1. A storyboard explicitly advertised by the selected playback source.
2. A standard HLS image playlist advertised by the selected HLS master playlist.
3. A locally generated frame from the exact selected source.

TMDB artwork and the single thumbnail in Stremio metadata are not treated as timeline storyboards because they are not timestamp-addressable and may not match the selected cut.

### Provider storyboard boundary

Provider data is optional and untrusted. Storyboard manifests and images must use HTTPS, remain on a validated origin allowed by the source contract, use bounded response sizes and dimensions, and support cancellation. Omnia does not send playback URLs, headers, credentials, or viewing activity to a new third party.

No currently configured Omnia provider offers a universal storyboard API. The provider boundary exists so a future source can attach a reviewed storyboard without changing the playback UI.

### Local fallback

The local fallback uses a separate, low-priority libmpv preview core. It opens the already selected source with the already validated request headers, disables audio and visible video output, seeks to the requested timestamp, and returns one downscaled frame. It never seeks the primary player.

The service applies these limits:

- wait 250 milliseconds after pointer movement before requesting a frame;
- allow only one in-flight frame request and cancel superseded work;
- keep at most 24 downscaled frames or 8 MiB, whichever is reached first;
- keep the cache in memory only and clear it when the source or player closes;
- stop the preview core immediately when hover ends or playback stops;
- use a longer 500-millisecond debounce and an eight-frame cache in Low Power Mode;
- decline local generation when the source cannot perform bounded seeking.

These limits favor energy use and playback stability over exhaustive preview generation. Omnia generates the frame the user requests; it does not crawl the entire movie in advance.

## Timeline Interaction

The existing timeline remains the seek control. A pointer-hover layer maps the horizontal pointer position to a clamped playback timestamp. After the debounce, a compact preview bubble appears above the timeline with a 16:9 image and timestamp. The bubble stays inside the window edges and disappears when the pointer leaves, the controls hide, the source changes, or playback closes.

Until a frame is available, the bubble shows the timestamp with the current glass treatment. Failure falls back quietly to the timestamp-only bubble; it does not interrupt playback or display repeated alerts. Dragging and keyboard seeking retain their current behavior.

Reduce Motion removes preview transitions. VoiceOver and Full Keyboard Access continue to use the existing timeline value and seeking actions; hover imagery is supplementary and carries no required information.

## Data Flow and Ownership

`PlaybackSession` owns the active source identity, track-switch request identifiers, and timeline preview service lifecycle. The libmpv bridge owns asynchronous property replies and the isolated preview core. `MacPlaybackChrome` owns only pointer position and presentation state. Continue Watching formatting remains a pure presentation function so it can be tested without rendering SwiftUI.

Cancellation flows from the player and view lifecycle down to manifest loading, frame extraction, and image decoding. Results carry the source identity and timestamp; stale results are discarded before publication.

## Testing and Evidence

Implementation follows red-green TDD.

- Presentation tests cover movie and episodic Continue Watching labels, including missing episode titles.
- The local multi-track fixture verifies that audio and subtitle requests do not set the player to paused, that the latest request wins, and that observed selection updates after confirmation.
- A deterministic local video fixture verifies timestamp mapping, hover debounce, cancellation, cache bounds, stale-source rejection, and frame extraction.
- Security tests reject oversized, malformed, non-HTTPS, cross-origin, and redirecting storyboard resources.
- UI smoke testing verifies bubble clamping, player dismissal cleanup, Reduce Motion, and the exact Continue Watching typography on Mac.

Performance claims require before-and-after Release measurements on the same Mac and source. Record hover latency, main-thread stalls, memory high-water mark, network bytes, and Energy Log behavior. Acceptance requires no primary-playback seek, no unbounded background scan, no regression in dropped frames, and cache limits matching this document.

## Trade-offs

A provider-only implementation would be lighter but unavailable for nearly all current sources. Pre-generating a complete storyboard would feel instant after generation but conflicts with Omnia's load-time, bandwidth, storage, and battery goals. The hybrid, on-demand design provides coverage while keeping work proportional to deliberate pointer interaction.
