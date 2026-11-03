# Performance pass — 2026-11-03

Dafa's round of Nov 3, item 12. PERFORMANCE.md asks for before-and-after Release evidence from Instruments on supported hardware before claiming anything is faster, smoother or lower-energy. That was not done here, so apart from the one measurement below, these changes are hypotheses that still need that evidence.

## Measured

| What | Before | After | How |
|---|---|---|---|
| Connections to the source when a stream starts on iOS | 2 (mpv plus an AVFoundation probe) | 1 (mpv) | Logging HTTP server, one MKV on the iPhone 17 Pro simulator, Debug build, one run each, 14 seconds of playback. Requests identified by User-Agent |

This counts connections. It doesn't show that playback starts faster.

## Changed, not measured

| Change | Hypothesis | Tradeoff |
|---|---|---|
| The PiP probe waits for the first video frame, and skips formats AVFoundation can't open (`PlaybackSession.swift`, `IOSPlaybackSupport.swift`) | Less competition during start, and no extra connection counted against a debrid limit | The PiP button turns on a moment after playback starts |
| Metadata detail cache key is stable (`OnDeviceMetadataService.swift`) | Details come from disk after a relaunch instead of the network, within the existing 4-hour limit | None. Needs a TMDB or TVDB key to see |
| Search wait after typing 450 ms → 300 ms, and recent add-on results show at once, then refresh (`SearchView.swift`) | Results feel quicker, and deleting a letter doesn't blank the page | Slightly more requests when typing slowly. Up to 24 searches held in memory for 5 minutes |
| Player state checked every 750 ms while paused, not 250 ms (`PlaybackSession.swift`) | Less background work during long pauses | The paused time display can lag slightly |
| Hero trailers don't autoplay in Low Power Mode (`HomeView.swift`) | Less video decoding on low battery | No trailer in Low Power Mode |
| Animated covers limited to 3 at once, decoded a frame at a time, stopped when not visible (`CollectionViews.swift`) | Bounded CPU and memory | Other covers wait their turn |

## Looked at and left alone

- mpv cache: 150 MiB ahead, 50 MiB behind, 20 seconds of readahead (`MPVPlayerController.m:1072-1075`). This is the main thing to tune for buffering, but changing it blind could make things worse: more memory on iPhone, or less headroom for 4K remuxes. It needs a real debrid stream and Instruments.
- Add-on requests already run in parallel with timeouts, and results appear as each add-on answers.
- `RemoteArtworkFetcher` already has a disk cache and a per-host limit.

## Still needed from a real device

Release build on an iPhone, iPad and Mac with a real add-on and debrid stream, using Instruments: time to first frame, rebuffer count, Home load time, search time, and energy. Compare with 0.3.4 on the same hardware and network.
