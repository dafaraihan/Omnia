# Player Engines and Competitive Review (2026-10-26)

Answers Dafa's items 6, 7 and 8 from 2026-10-26: what player Nuvio Enhanced
uses and whether Omnia should switch to it, how Nuvio's and Omnia's playback
engines compare, and what Omnia can learn from Nuvio, Nuvio Enhanced, Harbor
and PlayTorrio.

Evidence is source code read at each project's default branch on 2026-10-26
(shallow clones), each project's README and release notes, and Omnia's own
source and crash reports. Nothing here is measured. Performance points are
hypotheses with a measurement plan, as [PERFORMANCE.md](../../PERFORMANCE.md)
requires.

## 6. Nuvio Enhanced's "new player"

**Finding: no fork of Nuvio has dropped libmpv on Apple platforms.**

| Project | iOS / macOS engine | Android engine | Licence |
| --- | --- | --- | --- |
| NuvioMedia/NuvioMobile (official) | libmpv through MPVKit (`iosApp/iosApp/Player/MPVPlayerBridge.swift`) | ExoPlayer and libmpv | GPL-3.0 |
| luqmanfadlli/NuvioMobile-Enhanced | The same MPVKit bridge, grown from 1,427 to 2,583 lines | ExoPlayer, a new "Exo native" engine, libmpv, with an engine switch | GPL-3.0 |
| luqmanfadlli/NuvioMobile-iOS | MPVKit (release notes 0.5.8–0.6.4 talk about libmpv, VideoToolbox and Metal) | — | GPL-3.0 |
| AKRusso/NuvioMobile-Enhanced | MPVKit submodule | "Serialized Android libmpv playback", ExoPlayer for sidecar subtitles | GPL-3.0 |
| yesnt10/NuvioDesktop-Enhanced | Kotlin/Compose Desktop with an MPVKit submodule; ships a macOS DMG | — | not stated on the page |

What is new in Nuvio Enhanced is the way the same libmpv draws and recovers,
not a different engine:

- `vo=gpu-next` (libplacebo) on `gpu-api=vulkan`, `gpu-context=moltenvk`,
  drawing into a `CAMetalLayer` passed as `wid`.
- `hwdec=videotoolbox` with `hwdec-software-fallback=300`, and recovery
  when VideoToolbox drops out (Notification Center, PiP).
- HDR: `target-colorspace-hint=yes`, `tone-mapping=auto`,
  `hdr-compute-peak=yes`.
- Native Picture in Picture fed with mpv's VideoToolbox frames.
- `audio-fallback-to-null=yes`, so a failing audio device doesn't fail
  playback.
- Smaller caches: 64 MiB ahead and 32 MiB behind.

MPVKit (mpvkit/MPVKit) is LGPL-3.0, or GPL-3.0 when built with GPL options.
It supports iOS, macOS, tvOS and visionOS. Its own README calls Metal "only a
patch version" and the project "only suitable for learning libmpv".

**Recommendation: don't swap engines; Omnia already has the same one.** What
Omnia could adopt is the rendering path (see 7.1). Its Homebrew libmpv 0.41
already lists `vo=gpu-next` and `gpu-context=macvk` (Vulkan through
MoltenVK), so this needs no new dependency. **Decision for Dafa:** whether to
move from the OpenGL render API to `gpu-next` + `macvk`.

## 7. Decoder and playback engine: Nuvio vs Omnia

| | Omnia (macOS) | Nuvio / Nuvio Enhanced (iOS) |
| --- | --- | --- |
| Core | libmpv 0.41 (Homebrew build, embedded) | libmpv (MPVKit) |
| Video output | `vo=libmpv` render API on OpenGL (`CAOpenGLLayer`, deprecated since macOS 10.14) | `vo=gpu-next` on Vulkan/MoltenVK (Metal) |
| Hardware decoding | `hwdec=auto-safe`, Settings can force software | `hwdec=videotoolbox`, software fallback after 300 frames, recovery after interruptions |
| HDR / Dolby Vision | Not tone-mapped for the display; OpenGL has no EDR path | Colour-space hint and automatic tone-mapping |
| Audio output | `avfoundation`, then `coreaudio` (changed today after crash reports) | `audiounit`, exclusive, falls back to null |
| Cache | 150 MiB ahead, 50 MiB behind, 20 s read-ahead | 64 MiB ahead, 32 MiB behind |
| Network | Browser user agent, ffmpeg reconnect options, 30 s timeout | Protocol whitelist; headers set per load |
| Failure recovery | Ported today: refresh the same add-on's link, then up to two other sources, with a failure log | Refresh an expired credentialed link and resume |
| Picture in Picture | Omnia's own | Native, fed with mpv's frames |

Neither engine is better in itself; both are libmpv. Nuvio's iOS build has the
more modern output: Metal through MoltenVK, HDR tone-mapping and VideoToolbox
recovery. Omnia's cache is more generous, which helps slow debrid links at the
cost of memory.

### 7.1 What Omnia can do, in priority order

1. **Move to `vo=gpu-next` + `gpu-context=macvk`** on a `CAMetalLayer`.
   - *Expected:* real HDR and EDR on XDR displays, libplacebo scaling, an end
     to the deprecated OpenGL path.
   - *Risk:* this is a rework of `MPVPlayerController.m`'s rendering and
     timeline previews; MoltenVK becomes a runtime dependency.
   - *Measure:* Instruments GPU and Energy on the same 4K HDR and 1080p SDR
     titles, before and after.
2. **Test `hwdec=videotoolbox` with `hwdec-software-fallback=300`** against
   `auto-safe`.
   - *Measure:* CPU and Energy Impact while playing the same 4K HEVC file.
3. **Set `audio-fallback-to-null=yes`.** A broken output then plays silently
   instead of failing.
4. **Set the cache by stream size and quality:** keep 150 MiB for 4K
   remuxes, and use about 64 MiB for 1080p web releases.
   - *Measure:* Allocations, peak memory over a 20-minute session.
5. **Done today:** removed the crashing CoreAudio and Lua paths
   (`5bf6959`), added the display-sleep assertion, and added source recovery
   with Diagnostics (`2eb70f3`).

## 8. What else Omnia can learn

### Projects compared

- **Nuvio / Nuvio Enhanced:** see above.
  - Also: Trakt and Simkl sync engines (about 12.7k lines), comments,
    parental guide, chapters, "sync subtitles by ear", Stream Quality chooser
    for HLS, mini player, EPG.
- **Harbor** (harborstremio/harbor and mirrors; MIT):
  - Built with Tauri 2, React and a Rust/WASM `harbor-core`.
  - Bundled libmpv or HTML5 playback, with HDR passthrough, bt.2446a
    tone-mapping and Anime4K upscaling.
  - A four-stage stream ranking pipeline (parse, trust, score, rank) that
    drops cams and fakes, and debrid cache checks.
  - Watch parties on the user's own Cloudflare relay.
  - Casting: Chromecast, DLNA/UPnP, AirPlay, Roku.
  - Live TV with EPG, catch-up, DVR and 2×2 multiview; Kitsu and AniSkip
    for anime.
  - macOS 11+ DMG.
- **PlayTorrio** (ayman708-UX/PlayTorrio; GPL-2.0):
  - A hub for torrents, debrid, IPTV, music and books.
  - Directory sites flag legal risk, and one reviewer questions its
    provenance. Not a model to copy; listed for completeness.

### Ideas for Omnia, by area

| Area | Idea | Source | Effort |
| --- | --- | --- | --- |
| User experience | Stream ranking pipeline: drop cams and fakes, rank by quality tier and debrid cache | Harbor | Medium |
| User experience | Chapters on the seek bar and a chapter list | Nuvio Enhanced | Small (mpv `chapter-list`) |
| User experience | Sync subtitles by ear (Heard/Saw) | Nuvio Enhanced | Small |
| User experience | HLS quality chooser | Nuvio Enhanced | Small |
| User experience | AirPlay and casting | Harbor | Medium |
| User experience | Watch party | Harbor | Large |
| User experience | Trakt and Simkl history and library sync, beyond the scrobbling added today | Nuvio | Large |
| Power | `gpu-next` + Metal; pause rendering when the window is hidden or fully covered | Nuvio | Medium |
| CPU | Explicit VideoToolbox with recovery | Nuvio Enhanced | Small |
| RAM | Cache by quality; artwork cache capped at 192 MiB | Nuvio | Small |
| Network | Debrid cache detection before playing; parallel HEAD probe of the top sources | Harbor | Medium |
| Processing time | Genre pages show results as they arrive (done today); the same for Home rows | — | Small |
| Live TV | Catch-up, DVR, multiview | Harbor | Large |
| Anime | AniSkip for intro and outro; Kitsu IDs | Harbor | Small–Medium |
| Picture quality | Anime4K shaders (needs `gpu-next`) | Harbor | Small after 7.1 |

### Decisions for Dafa

1. Move playback to `gpu-next` + Metal (MoltenVK)? This is the change most
   likely to improve picture quality and HDR, and it would retire OpenGL.
2. Which of the larger items should come first: stream ranking, casting,
   watch party, or full Trakt/Simkl sync?

## Sources

- https://github.com/NuvioMedia/NuvioMobile
- https://github.com/luqmanfadlli/NuvioMobile-Enhanced
- https://github.com/luqmanfadlli/NuvioMobile-iOS/releases
- https://github.com/AKRusso/NuvioMobile-Enhanced
- https://github.com/yesnt10/NuvioDesktop-Enhanced
- https://github.com/mpvkit/MPVKit
- https://github.com/3-pr/harbor (mirror of harborstremio/harbor)
- https://alternativeto.net/software/playtorrio/about/
- Omnia: `Omnia/Platform/Playback/MPVPlayerController.m`, crash reports in
  `~/Library/Logs/DiagnosticReports/Retired/Omnia-2026-10-2*.ips`
