# Native hero trailer extraction

Omnia's Home hero resolves a public YouTube trailer on-device and gives a
single Full HD HLS source or muxed MP4 URL to a dedicated AVPlayerLayer.
The main playback session is not involved. No iframe, server deployment,
additional entitlement, or new package is required.

## Source and scope

Reference inspected on 2026-10-21: [Nuvio Enhanced, commit
4e1326da4e7e6d957994280cff82efe0fcbf7fa2](https://github.com/luqmanfadlli/NuvioMobile-Enhanced/tree/4e1326da4e7e6d957994280cff82efe0fcbf7fa2),
especially `InAppYouTubeExtractor.kt`, the full iOS extraction adapter, and
the full/App Store trailer resolvers. That repository is GPL-3.0. Omnia adds
an independently written Swift implementation of the player-response approach;
no Nuvio source, Kotlin runtime, native binary, or third-party extractor is
bundled. Client identifiers and versions are interoperability inputs observed
in that reference, not a supported public YouTube API contract.

Unlike Nuvio's full multi-source player path, this preview supports HLS with
audio renditions and muxed MP4 only. Separate adaptive audio/video, signature
deciphering, proof-of-origin tokens, cookies, sign-in and age/region restriction
bypasses are not implemented. YouTube can reject all client profiles. Nuvio's
App Store iOS resolver returns no extracted source; this implementation does
not establish store distribution eligibility.

## Network and playback boundary

The input is an exact 11-character video ID from a canonical HTTPS YouTube
watch URL. Watch/player requests go only to `www.youtube.com`; extracted
media must use HTTPS on a subdomain of `googlevideo.com`, without credentials,
fragments or nonstandard ports. Redirects are restricted to the same host or
between validated Google video hosts. The ephemeral extraction session has no
cookie, credential or response-cache storage. Requests have six-second
timeouts, probes two seconds, and the complete extraction has a 30-second
cancellation deadline. Watch/JSON/manifest reads are capped at 4 MiB/1 MiB/
256 KiB while streaming, and probes cancel after response headers.

The HLS master is checked for allowed variant and URI-attribute URLs and a
1920×1080 variant is probed before playback. The extractor builds an in-memory
master containing only that video variant and preserves audio/subtitle
renditions with absolute validated HTTPS URLs. A private AVAssetResourceLoader
delegate serves only this generated master; it exposes no network listener or
persistent playlist file. MP4 fallback likewise requires an explicit 1920×1080
format. AVPlayer's rendered presentation size must be 1920×1080 before the
preview is revealed; a different size fails back to artwork. Missing Full HD
does not fall back to SD, HD or 4K. AVFoundation owns subsequent playlist,
segment and media requests, including their redirects; the extractor's
URLSession delegate does not intercept AVFoundation traffic. Nested playlists
remain part of the native playback/parser trust boundary in [SECURITY](../../SECURITY.md).
Signed URLs stay in memory and are never logged or persisted by this flow.

## States and focused manual checks

- Enable Hero Trailer Playback in Home Layout settings. The existing artwork
  remains during the configured delay, extraction, and initial buffering.
- A displayable frame and active playback reveal the preview; its existing
  mute control and carousel hold remain in effect. HLS retains the master
  playlist filtered to one Full HD video variant, so audio renditions are not
  discarded and adaptive quality cannot select another resolution.
- Missing trailers, unavailable networks, rejected responses and extraction
  timeouts release the carousel and leave artwork. Startup or rebuffering
  stalls fail after 15 seconds of active waiting. There is no error overlay
  on a decorative preview; changing the hero or revisiting Home retries.
- Page rapidly during extraction and playback; old completions must not
  reveal a different title. Toggle autoplay off; video/audio must stop.
- Switch tabs, open sources, start primary playback, or background the app;
  the preview pauses. Return to Home and confirm mute and playback recover.
- Enable Reduce Motion; preview autoplay and automatic hero paging stop,
  while explicit hero navigation remains available.
- Verify sound, end-of-trailer carousel recovery, Mac resizing/full screen,
  iPhone orientations/safe areas and iPad multitasking. Check VoiceOver focus,
  Dynamic Type, keyboard navigation, contrast/transparency and light/dark;
  the decorative player is accessibility-hidden and hit-testing-disabled.

Validation uses affected-destination builds and manual checks, following
[AGENTS](../../AGENTS.md). Build success does not prove live extraction or
playback. Hardware/accessibility checks and hosted YouTube responses must be
reported separately from compilation.

### Evidence recorded on 2026-10-21

- Canonical signed macOS Debug build passed. Live extracted trailers became
  visible for JoJo's Bizarre Adventure and Dark Matter. The native mute button
  updated its accessible label. Navigating Home → Library → Home and changing
  hero title succeeded. Disabling autoplay left artwork with no mute control;
  the original autoplay preference was restored after the check.
- The ordinary iOS Simulator build and an SDK/platform command-line override
  both failed destination selection before compilation: this checkout declares
  only `macosx` in `SUPPORTED_PLATFORMS`. No project/signing changes were made.
- Full iPhone/iPad, accessibility settings, audio-listening, offline/error,
  end-of-trailer and primary-playback interruption checks remain unverified.

### Full HD selection — 2026-10-22

The prior implementation returned the unrestricted HLS master and accepted
muxed MP4 heights at or below 1080. AVPlayer's preferred maximum resolution
was a ceiling preference, not a fixed-quality selection. This allowed varying
qualities. The current selection restricts both paths to 1920×1080 and gives
AVPlayer only one video variant while retaining HLS audio.

The signed canonical macOS Debug build passed. JUJUTSU KAISEN played visibly
in the final build, passing the new runtime presentation-size guard before
the preview and mute control appeared. Source review found no actionable
issues, and `git diff --check` passed. One current Omnia.app is retained.

Regression check: select heroes whose YouTube playlists offer SD, HD, FHD and
4K; only the FHD variant may appear in the generated master, and progressive
formats must report width 1920 and height 1080. With no reachable FHD format,
keep artwork rather than selecting another resolution. Retest mute, paging,
pause/resume and HLS audio. Live unavailable-FHD/offline cases, long playback
under bandwidth changes, listening verification, and iPhone/iPad checks remain
unverified; the existing project still lists only `macosx` destinations.

Apple references: [Playing video](https://developer.apple.com/design/human-interface-guidelines/playing-video/),
[AVPlayerLayer](https://developer.apple.com/documentation/avfoundation/avplayerlayer),
[preferredMaximumResolution](https://developer.apple.com/documentation/avfoundation/avplayeritem/preferredmaximumresolution),
[AVAssetResourceLoader](https://developer.apple.com/documentation/avfoundation/avassetresourceloader),
and [Apple Design Resources](https://developer.apple.com/design/resources/).
