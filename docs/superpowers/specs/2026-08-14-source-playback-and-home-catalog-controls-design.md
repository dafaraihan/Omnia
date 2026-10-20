# Source Playback and Home Catalog Controls Design

> **Automated-validation policy:** Follow the repository-root `AGENTS.md`. Instructions below that call for automated test targets, suites, fixtures, or scripts are historical and superseded; use builds, static checks, and focused manual evidence instead.

**Date:** 2026-08-14  
**Status:** Approved by the user for immediate implementation  
**Scope:** macOS source selection/playback, add-on management, and built-in Home shelf visibility. iPhone and iPad keep torrent playback disabled.

## Problem and evidence

The supplied screenshots show MediaFusion filters with zero rows while the same configured add-on returns rows in Fusion, and Torrentio rows that Omnia retrieves but disables with “The reviewed local torrent engine is not included in this build.” Repository evidence shows the native torrent implementation is compiled only in macOS Release, while the screenshot is an Xcode Debug run. A read-only request using the installed MediaFusion configuration currently returns three valid HTTPS stream declarations for the affected Reacher episode, so a transient or per-add-on failure must not be collapsed into a permanent zero count.

Add-on removal already exists as swipe/context-menu behavior, but that action is effectively hidden on macOS. Home already stores coarse movie/series shelf flags without exposing controls. The requested result needs visible actions and durable, per-shelf controls.

## Selected approach

1. Keep direct HTTPS and torrent candidates separate. Preserve every successful add-on batch even when another add-on or identifier fails. Record a status for every enabled add-on and let the person retry failed or empty add-ons without dismissing the sheet or discarding successful Torrentio rows.
2. Enable the existing reviewed local torrent engine for macOS Debug development by using the documented Homebrew development fallback. Debug builds link libtorrent/OpenSSL only on macOS, stage their runtime libraries, and keep the existing explicit peer-consent, cache, cancellation, and safe-path boundaries. Release continues to require the pinned native artifact gate. Mobile stays disabled.
3. Add an always-visible destructive button to each installed add-on row. It opens the existing confirmation dialog and removes the manifest URL from Keychain only after confirmation.
4. Give every built-in Home shelf a stable identifier and persist a disabled-ID set. Catalog Settings lists each shelf under “Home Shelves” with an independent toggle. Disabled shelves are removed from Home rows and from hero candidates, while Discover remains unchanged. Existing coarse movie/series flags migrate by disabling the corresponding shelf IDs once, then are retired.

## Data flow and failure behavior

`PlaybackSourceResolver` returns ordered per-add-on results instead of only one flattened error array. `PlaybackSourceSheet` renders source counts from successful candidates and a compact state row for add-ons that returned no candidates or failed. Retry calls the same bounded HTTPS client for only that add-on and merges its result by add-on ID. Response-size, content-type, same-origin redirect, timeout, cancellation, and secret-redaction rules remain unchanged.

The local torrent button is enabled only when the native bridge reports availability. Debug dependency staging fails with a concise setup error when libtorrent is missing rather than producing a build whose UI promises unavailable functionality.

Shelf settings are local preferences. They trigger view recomputation only; they do not mutate metadata routes, installed add-ons, Supabase, or hosted state.

## Accessibility and verification

Retry state is conveyed with text and a button label, not color. The remove button is named for the add-on and confirmation remains native. Shelf toggles use their visible shelf names and preserve system keyboard, VoiceOver, contrast, and Dynamic Type behavior.

Regression coverage will prove partial add-on success, retry replacement, visible removal presentation, shelf persistence/filtering, and Debug native-engine build configuration. Verification includes focused XCTest, the full signed macOS test suite, macOS Debug build with the development native dependencies, generic iOS Simulator build, Deno checks because the existing metadata source fix remains in the working tree, and `git diff --check`.

## Constraints

- No hosted Supabase mutation or deployment.
- No add-on token, manifest URL, source URL, info hash, peer address, or request header is written to ordinary logs or test fixtures.
- No incoming listener, UPnP, NAT-PMP, background download, long-term seeding, DRM bypass, or mobile torrent support is added.
- Release distribution remains blocked by the existing independent native-dependency and legal-review gates.
- Existing unrelated worktree edits are preserved.
