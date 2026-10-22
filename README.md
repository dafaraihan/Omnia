<div align="center">

# Omnia

**A native, cinematic media player for your own Stremio add-ons.**

Built with SwiftUI and libmpv for macOS, with iPhone and iPad builds from the same project.

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-black)
![Built with SwiftUI](https://img.shields.io/badge/built%20with-SwiftUI-orange)
[![Latest release](https://img.shields.io/github/v/release/Laviora/Omnia)](https://github.com/Laviora/Omnia/releases/latest)

### [⬇&nbsp;&nbsp;Download Omnia for macOS (.dmg)](https://github.com/Laviora/Omnia/releases/download/v0.1.1/Omnia-0.1.1.dmg)

Apple silicon · macOS 26 or later · [All releases](https://github.com/Laviora/Omnia/releases)

[Features](#features) · [Install](#install) · [Build from source](#build-from-source)

</div>

---

## What is Omnia?

Omnia is a home for the add-ons you already use. Point it at your own Stremio-compatible add-ons — a self-hosted [AIOStreams](https://github.com/Viren070/AIOStreams) or [MediaFusion](https://github.com/mhdzumair/MediaFusion) instance, or any other manifest URL — and Omnia turns their catalogs and streams into a native Apple-platform experience with a libmpv player underneath.

> [!IMPORTANT]
> **Omnia hosts, indexes, and distributes no content.** It ships with no add-ons and no sources. Everything you watch comes from add-ons, playlists, and servers that you configure yourself, and you are responsible for using them lawfully.

## Features

### Discover
- **Add-on catalogs and streams** — install any Stremio add-on by manifest URL; its catalogs appear on Home and its streams appear on every title.
- **Discover with search** — browse and search in one place, with filters by source, kind (movies or series), and genre.
- **Rich detail pages** — artwork, cast, seasons, and episodes filled in from TMDB metadata.
- **Hero trailers** — the Home and detail heroes play the title's trailer in the background.
- **Collections and shuffle** — build your own collections and let Omnia pick something for you.
- **Continue Watching** — resume where you left off, with options for how the row behaves.

### Streams
- **Nuvio-style streams page** — every source from every add-on in one list, so the right stream is easy to spot.

### Playback (libmpv)
- **libmpv engine** — the player behind mpv, with broad container and codec support.
- **Skip intro and skip outro.**
- **Up Next** — the next episode is offered before the credits end.
- **Subtitle sync** — shift subtitle timing during playback, plus audio and subtitle track selection.
- **Picture in Picture.**

### Live TV and media servers
- **Live TV** from **M3U** playlists, **Xtream Codes**, and **Stalker** portals.
- **Jellyfin and Emby** — connect your own media server and play its library alongside your add-ons.

### Personal
- **Viewer profiles** — separate watch history and preferences for everyone in the household.
- **Omnia account sync** — optionally sign in to keep profiles and settings in sync.
- **Theming** — choose the accent and appearance that suit you.
- **Guided onboarding** for adding your first add-on.

## Previews

Screenshots are not included yet. Omnia only shows what your own add-ons provide, so honest screenshots would contain third-party artwork. Clean previews of Omnia's own interface will be added later.

## Install

1. [Download Omnia-0.1.1.dmg](https://github.com/Laviora/Omnia/releases/download/v0.1.1/Omnia-0.1.1.dmg), or pick a version from [Releases](https://github.com/Laviora/Omnia/releases).
2. Open the `.dmg` and drag **Omnia** into **Applications**.
3. Open Omnia from Applications.

**Requirements:** a Mac with Apple silicon running macOS 26 or later.

### Opening an unsigned build

Release builds are not yet signed with an Apple Developer ID or notarized, so macOS warns the first time you open Omnia. To open it anyway, do one of these once:

- **Right-click (or Control-click) Omnia in Applications → Open**, then click **Open** in the dialog; or
- try to open Omnia, then go to **System Settings → Privacy & Security**, scroll to the message about Omnia, and click **Open Anyway**.

After that, Omnia opens normally.

## Getting started

1. Launch Omnia and follow onboarding.
2. Add an add-on by pasting its manifest URL (it usually ends in `manifest.json`). A self-hosted AIOStreams or MediaFusion instance works well as a single add-on that aggregates many sources.
3. Optionally add Live TV playlists or portals, or a Jellyfin or Emby server, from **Settings**.
4. Pick a title, choose a stream, and press play.

## Build from source

**Requirements:** Xcode 26 or later and [Homebrew](https://brew.sh).

```sh
brew install mpv libtorrent-rasterbar
git clone https://github.com/Laviora/Omnia.git
cd Omnia
open Omnia.xcodeproj
```

Select the **Omnia** scheme and the **My Mac** destination, then run. From the command line:

```sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' build
```

The macOS build copies libmpv and its Homebrew dependencies into the app automatically. You need your own development signing identity in Xcode. For an iPhone or iPad simulator build:

```sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'generic/platform=iOS Simulator' build
```

The optional cloud features (account sync and the metadata service) use Supabase; see the [Supabase guide](supabase/README.md) to run them locally.

## Project documentation

- [Product and interaction design](DESIGN.md)
- [Security boundaries](SECURITY.md)
- [Performance budgets and profiling](PERFORMANCE.md)
- [Infrastructure and operations](INFRASTRUCTURE.md)
- [Native playback dependencies](NativeDependencies/README.md)
- [Roadmap](FUTURE-UPDATES.md)
- [Contributor guidelines](AGENTS.md)

## License

Omnia is free software, released under the [GNU General Public License v3.0](LICENSE). You may use, study, share, and modify it under the terms of that license.

Omnia bundles [mpv](https://mpv.io) (libmpv), [FFmpeg](https://ffmpeg.org), [libtorrent](https://libtorrent.org), and other open-source libraries, each under its own license.
