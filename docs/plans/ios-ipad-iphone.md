# Omnia for iPad and iPhone

Status, 2026-10-27: the app target builds for iPhone and iPad simulators and
launches into onboarding on both (`build(ios)` commit). Playback on iOS uses the
existing AVPlayer path. This plan covers what remains.

## What is shared and what is platform-specific

- **Shared as-is (most of the app):** Domain, Data (add-ons, metadata, trackers,
  Supabase account and vault, collections, library), Core, and nearly all
  SwiftUI screens. 52 Swift files already branch on `#if os(macOS)`, with iOS
  paths written when Omnia first targeted iPhone and iPad.
- **macOS-only today:** `Platform/macOS` (window chrome, whole-screen full
  screen, display-sleep assertion, timeline storyboard previews), libmpv and
  its Objective-C controller and thumbnail generator, the local torrent engine
  (libtorrent), macOS settings cards (`OmniaSettingsForm` page cards), hover
  previews, menus and commands.
- **iOS stand-ins already in place:** AVPlayer playback, `Form`-based settings,
  `UIColor` backgrounds, the tab bar `TabView`.

## Player on iOS

AVPlayer plays HLS and MP4/MOV (H.264/HEVC, AAC/AC-3/E-AC-3), but not MKV,
most WebM, PGS/ASS subtitles or many debrid files. Omnia needs libmpv on iOS to
match the Mac:

1. **Preferred:** extend `Scripts/build-playback-dependencies.sh` to emit iOS
   device (arm64) and simulator (arm64) slices as xcframeworks: FFmpeg, libass,
   libplacebo, MoltenVK (iOS), mpv with `moltenvk` and `gpu-next`, drawn into a
   `CAMetalLayer` (the same path as Metal Rendering on the Mac). It keeps the
   pinned, digest-checked supply chain and its licence evidence. Estimate: the
   first iOS dependency build takes about 45–60 minutes per platform pair on
   this Mac. Ask Dafa before starting it.
2. **Fallback:** MPVKit's prebuilt iOS xcframeworks (LGPL/GPL, compatible with
   Omnia's GPLv3). Faster to adopt, but it's a second, unpinned binary source
   that needs its own provenance and licence review under `SECURITY.md`.
3. AVPlayer stays the fallback for what it can play, as today.

The local torrent engine stays Mac-only at first (iOS background and network
limits); debrid and HTTP sources work everywhere.

## Phases and effort

1. **Builds and launches** (done): platforms enabled, AppKit-only code guarded.
2. **iPad** (~2–3 days): the Mac layout with touch targets, pointer and keyboard
   support, Stage Manager and Split View sizes, the iPad hero (landscape art as
   on the Mac), settings as the Mac's page cards where they fit.
3. **iPhone** (~4–6 days):
   - bottom tab bar (Home, Library, Discover, Profile);
   - portrait hero: TMDB's textless "No Language" poster (fanart.tv fallback),
     the title logo over a bottom fade; fallback to a subject-centred backdrop
     crop, or the poster with a heavier fade;
   - single-column title pages, sheets for sources and seasons;
   - full-screen player with iOS controls, Picture in Picture, AirPlay.
4. **libmpv on iOS** (~3–5 days plus the dependency build): see Player on iOS.
5. **Release** (~1–2 days): App Store or TestFlight signing (needs a paid Apple
   Developer membership), privacy manifest, screenshots.

## Accessibility and checks per phase

VoiceOver, Dynamic Type, Reduce Motion, light/dark, iPhone orientations and safe
areas, iPad multitasking and keyboard, as `AGENTS.md` requires.
