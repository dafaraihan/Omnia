# macOS Local Playback Rollout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the approved macOS playback design through four independently reviewable, testable plans.

**Architecture:** First remove source/track reliability regressions without adding dependencies. Next replace development-only Homebrew packaging with a pinned native dependency pipeline. Then add bounded local torrent streaming and cache ownership, followed by complete-object disc materialization.

**Tech Stack:** Swift 6 concurrency, SwiftUI, Objective-C/Objective-C++, libmpv, FFmpeg, libtorrent 2.x, Boost, libbluray, XCTest, shell build tooling, macOS App Sandbox and hardened runtime.

## Global Constraints

- macOS is the only local-resolver target; iPhone and iPad behavior must continue to build unchanged.
- Show every add-on source, but never claim every source is playable.
- Direct HTTPS eligibility is independent of extension and `notWebReady`.
- DRM, AACS/BD+ circumvention, encrypted commercial discs, and arbitrary webpage extraction are excluded.
- Local peer activity requires explicit consent and stops with playback; no incoming listener, UPnP, NAT-PMP, local peer discovery, background download, or long-term seeding.
- Resolver data stays in the sandboxed caches directory and is never synced or backed up.
- No hosted Supabase, resolver, configuration, or deployment mutation.
- Distribution remains blocked until native dependency provenance, licensing, hashes, SBOM, signatures, and vulnerability review pass.
- Preserve unrelated worktree changes and commit only paths named by the active task.

---

## Execution order

1. [Source visibility and track reliability](2026-08-12-playback-source-track-reliability.md)
2. [Reproducible native playback dependencies](2026-08-12-native-playback-dependencies.md)
3. [Local torrent resolver and cache](2026-08-12-macos-local-torrent-resolver.md)
4. [Disc-image and directory materialization](2026-08-12-macos-disc-materialization.md)

Each child plan must finish its tests, builds, diff review, and focused commits before the next begins. Plans 1 and 2 are independent and may be reviewed separately, but Plan 3 consumes both. Plan 4 consumes Plan 3's cache and resolution interfaces.

## Final acceptance gate

- [ ] All four child plans are complete with their documented evidence.
- [ ] `xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test` passes from the integrated revision.
- [ ] `xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'generic/platform=iOS Simulator' build` passes from the integrated revision.
- [ ] The final macOS archive uses only the pinned native dependency bundle and passes the dependency/license verification script.
- [ ] Direct opaque HTTPS, local torrent seek, cache exhaustion/recovery, unencrypted Blu-ray playback, audio selection, and subtitle selection are smoke-tested on a signed macOS build.
- [ ] `git diff --check` is clean and `git status --short` contains no unintended paths.
