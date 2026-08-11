# macOS Local Playback Resolver Design

**Date:** 2026-08-12  
**Status:** Approved in conversation; pending implementation  
**Scope:** macOS playback source visibility, local resolving, libmpv track discovery, storage, security, and distributable native dependencies. iPhone and iPad are a separately reviewed future phase.

## Problem

Omnia currently hides some add-on stream results before libmpv can inspect them. In particular, compatibility filtering historically excluded opaque or extensionless HTTPS URLs, and the source model respects an add-on's `notWebReady` hint even when the add-on also supplies a direct HTTPS URL. The source picker therefore reports no sources or an incomplete set despite enabled add-ons returning candidates.

The macOS player also exposes audio and subtitle menus from periodically queried libmpv properties, but it does not consume libmpv's event queue. Local multi-track media is covered by an integration fixture, yet remote or incrementally discovered streams can leave the UI without timely track-list or selection updates.

Torrent candidates currently require a user-configured remote resolver. The product requirement is instead to resolve supported non-direct media locally on macOS, with explicit dependency, storage, security, and licensing controls.

## Goals

1. Show every source returned by every enabled stream add-on.
2. Attempt every syntactically valid direct HTTPS media URL with libmpv, independent of extension, compatibility heuristics, verification state, or `notWebReady`.
3. Resolve torrent info hashes and magnet metadata locally on macOS without an externally reachable local HTTP service.
4. Support local materialization and playback of unencrypted disc images or disc directory structures when a source can be represented safely.
5. Detect and synchronize audio and embedded subtitle tracks as libmpv discovers or changes them.
6. Bound disk, memory, network, and parser exposure and make resolving cancellable and observable.
7. Establish a reproducible, reviewable dependency and license path before distribution.
8. Preserve iPhone and iPad behavior until a separate mobile design is approved.

## Non-goals and hard limits

- No promise that every source will play. Servers can reject requests, URLs can expire, media can be malformed, and codecs or protocols can remain unsupported.
- No DRM implementation, credential circumvention, AACS/BD+ circumvention, or encrypted commercial-disc support.
- No arbitrary webpage extraction or site-specific downloader integration in this phase. A webpage is not a media container and requires a separate extractor, terms, licensing, and security review.
- No incoming peer listener, UPnP, NAT-PMP, or local peer discovery in the initial implementation.
- No background downloading, permanent download library, long-term seeding, or cloud synchronization of resolver data.
- No iOS or iPadOS libmpv/libtorrent packaging in this phase.
- No hosted Supabase, resolver, or deployment mutation.

## Considered approaches

### A. Expand the extension allow-list

Adding extensions such as `m2ts`, `ts`, `avi`, or `iso` is small but does not solve opaque URLs, misleading filenames, query-based endpoints, redirects, or containers that libmpv can identify by content. This approach is rejected because it preserves the source-visibility defect under a larger allow-list.

### B. Resolve torrents through a loopback HTTP server

A local server provides a familiar range-request interface to libmpv, but it expands the sandbox entitlement set, introduces listener lifecycle and origin-authentication risks, and creates another buffering layer. This approach is rejected for the initial implementation.

### C. Materialize every source completely before playback

Full download before playback simplifies reads but creates long startup delays, maximizes temporary storage, and prevents useful torrent streaming. It remains appropriate only for sources that require a complete seekable object or directory tree, such as disc-image playback.

### D. Native resolver with libmpv stream callbacks

This is the selected approach. A local libtorrent engine supplies bounded, seekable reads to a custom libmpv protocol. Direct HTTPS bypasses the resolver. Sources that require a complete object are materialized into an app-owned cache before being handed to libmpv.

## Source model and presentation

`AddonStreamCandidate` remains the complete, untrusted add-on result. Delivery classification must describe how Omnia can act on a source without removing it from the picker.

- **Direct HTTPS:** Any URL with HTTPS, a host, and no embedded user information is visible and selectable. `notWebReady` becomes a warning label rather than a veto. Extensions are descriptive only.
- **Torrent:** A valid v1 or v2 info hash, optional magnet metadata, file index, filename, and tracker hints form a locally resolvable candidate.
- **Disc materialization:** A torrent-selected or otherwise authorized local object may be recognized as an unencrypted ISO, DVD structure, or Blu-ray structure after safe materialization.
- **External webpage:** Visible with an explicit "external page—not locally resolved" state.
- **Malformed or unsupported declaration:** Visible with a bounded, non-sensitive reason.

Source filtering may narrow the visible list by selected add-on but must not silently remove a delivery category. "Show Only Compatible Formats" must not hide macOS libmpv candidates; it can remain relevant to the AVPlayer mobile path until the mobile redesign.

Autoplay can select only immediately playable direct HTTPS sources or previously resolved local sources. It must not start peer-to-peer activity without an explicit source selection in this phase.

## Local resolver architecture

### Components

`LocalPlaybackResolver` is a main product-facing Swift actor. It owns job lifecycle and exposes a small state machine:

```text
idle -> readingMetadata -> selectingFile -> buffering -> ready
                                      \-> materializing -> ready
any active state -> failed | cancelled
ready -> stopped
```

It delegates peer transport and piece storage to a native `LibtorrentEngine` behind a Swift protocol. Production uses an Objective-C++ bridge; tests use deterministic fakes. The bridge owns libtorrent objects on a dedicated serial executor and never exposes C++ types to Swift.

`ResolverCache` owns paths, reservations, accounting, eviction, and deletion. It is the only component allowed to create or remove resolver files.

`OMMpvPlayerController` registers a read-only custom stream protocol such as `omnia-torrent://<opaque-job-id>`. The opaque identifier contains no info hash, filename, URL, token, or user data. The open callback obtains a resolver stream handle; read and seek callbacks request the needed byte ranges; close releases the handle.

### Torrent metadata and file selection

Only bounded normalized metadata enters the product layer. Selection order is:

1. Use the add-on-provided file index when it exists and is in range.
2. Match an add-on-provided normalized filename exactly.
3. Select the largest plausible video object when exactly one clear candidate exists.
4. Present a file chooser when multiple plausible media objects remain.

The chooser shows normalized relative filename, size, and index. It never renders an absolute cache path. Non-regular files, traversal, absolute paths, device names, links, and paths escaping the job directory are rejected.

Piece scheduling is range-led. The resolver raises the priority and deadline of pieces covering the current read position plus a bounded look-ahead window. A seek cancels obsolete deadlines and reprioritizes the new range. Plain `sequential_download` is not the streaming strategy.

### Disc materialization

Disc playback requires a complete seekable object or directory structure. A selected ISO or disc tree is downloaded to a reserved cache job, verified against torrent piece hashes, and handed to libmpv through its DVD/Blu-ray input options. Only unencrypted media is supported. Materialization reports determinate byte progress when total size is known.

### Cancellation and teardown

Closing playback, selecting another source, clearing the active job, or cancelling the source sheet propagates cancellation to metadata lookup, peer connections, piece waits, materialization, and libmpv stream reads. The resolver stops active upload immediately when playback ends. No job may retain UI, session, or player objects after teardown.

## Audio and subtitle track synchronization

The mpv controller must install a wakeup callback and drain events without blocking libmpv. It observes at least:

- file-loaded and end-file;
- track-list changes;
- selected audio (`aid`) and subtitle (`sid`) changes;
- duration and playback-time changes needed by the existing session;
- log/error state reduced to redacted user-facing failures.

Objective-C posts a small immutable state snapshot to the main actor. `PlaybackSession` updates audio tracks, subtitle tracks, selection state, loading state, and playback error from snapshots rather than treating 250 ms property polling as the source of truth. A low-frequency defensive refresh may remain if testing demonstrates value.

Track rows include every libmpv audio or subtitle track with a valid ID. Missing title/language metadata falls back to a stable "Track N" label. Embedded text, ASS/SSA, VobSub, PGS, and other subtitle codecs appear when libmpv exposes them. The UI distinguishes "Tracks still loading" from "No embedded subtitles".

## Storage policy

Resolver files live in an Omnia-specific subdirectory returned for the sandboxed caches directory. They are excluded from backup and treated as discardable.

- Default quota: 20 GB.
- User options: 5, 10, 20, or 50 GB.
- Reserve: retain at least 10% of volume capacity and never consume the final 5 GB.
- Active jobs cannot be evicted.
- Inactive completed or partial jobs are evicted least-recently-used.
- Incomplete data is removed when abandoned unless the user explicitly enables temporary retention.
- Settings show current usage and provide per-source cleanup plus a confirmed "Clear Resolver Cache" action.
- Quota reservation happens before materialization. A job fails clearly before download if safe space cannot be reserved.

Cache metadata contains only opaque job IDs, bounded display data, sizes, timestamps, and engine resume data needed for an active or temporarily retained job. Signed URLs, headers, tokens, playback history, and unnecessary source identifiers are not persisted.

## Security and privacy controls

### Network boundary

The initial engine makes outbound connections only under the existing network-client entitlement. Incoming peer listening, UPnP, NAT-PMP, and local peer discovery are disabled. DHT and tracker use must be explicit, bounded, and tested under the sandbox. If acceptable peer discovery cannot work without a broader entitlement, implementation stops for a new design review rather than silently adding it.

### Untrusted input bounds

The implementation defines and tests maximum values for magnet/source length, torrent metadata bytes, file count, path depth and length, tracker count, piece count/size, concurrent jobs, peers, connections, memory cache, disk quota, metadata wait, read wait, and idle job lifetime. Exact values belong in the implementation plan and must be justified by fixtures and resource measurements.

Torrent piece hashes are verified by libtorrent before bytes become readable. The file bridge must not follow links or allow writes outside its assigned cache directory. Native parser and peer-engine failures must not reveal URLs, hashes, filenames, peer addresses, or request headers in user-visible diagnostics or ordinary logs.

### Peer participation disclosure

Before the first local torrent resolution, Omnia explains that peer-to-peer playback reveals the device's IP address to trackers and peers and can upload pieces while playback is active. The user must explicitly continue. The choice is local and reversible in Playback settings. Upload and download limits are user-configurable, with bounded defaults. Omnia stops participation when playback stops and never seeds in the background.

## Dependency and licensing plan

The current Homebrew-based build remains development-only. The observed local Homebrew mpv closure includes GPL-configured FFmpeg and cannot serve as the unreviewed distribution pipeline.

Release packaging must:

1. Pin exact source revisions or releases for mpv, FFmpeg, libtorrent, Boost components, libbluray, and every transitive native library.
2. Acquire sources reproducibly, verify cryptographic hashes, record provenance, and build universal macOS artifacts in CI.
3. Build mpv with its LGPL configuration and build FFmpeg without GPL or nonfree components.
4. Prefer dynamic linking for LGPL components, preserve replacement/relink rights, and ship required notices and source/relink instructions after legal review.
5. Reproduce libtorrent's BSD notice and inventory required Boost Software License notices.
6. Generate an SBOM and scan native artifacts and sources for applicable vulnerabilities.
7. Verify the final app's dylib closure, entitlements, nested signatures, hardened runtime, notarization, and archive behavior.
8. Block distribution when license provenance, notices, source obligations, hashes, signatures, or applicable high/critical vulnerability review is incomplete.

This document records engineering requirements and is not legal advice. Distribution requires an appropriate license review.

## UI states and accessibility

The source sheet defines loading, empty, partial success, unavailable, resolver metadata, file selection, buffering, materializing, ready, cancellation, retry, storage-full, offline, and playback-failed states. One add-on or resolver failure does not erase successful rows from other add-ons.

Progress is communicated by text as well as animation or color. Source type, add-on, peer-to-peer status, selected filename, and unavailable reason are available to VoiceOver. Focus moves predictably into and out of the file chooser and consent presentation. Cancellation remains available during every network or materialization phase. Reduce Motion and Increase Contrast must not hide state.

The player track menus remain keyboard accessible and announce loading, empty, selected, and available-track states. Track identity never relies only on a checkmark color.

## Testing and verification

### Unit and contract tests

- Direct HTTPS candidates remain visible and playable regardless of extension and `notWebReady`.
- External and malformed candidates remain visible with the correct reason.
- Autoplay never starts a new local torrent job.
- Torrent hash, metadata, path, tracker, and file-count bounds reject hostile fixtures.
- File selection follows index, filename, unique-largest, then chooser order.
- Cache reservations, active protection, LRU eviction, cleanup, and free-space guardrails are deterministic.
- Cancellation reaches metadata, range reads, materialization, and teardown.
- Logs and persisted cache metadata contain no prohibited source capabilities or peer data.
- Track snapshots preserve all tracks and selection changes.

### Native integration tests

- Existing local multi-track MKV renders and supports audio/subtitle selection.
- Track-list and selected-track events update the Swift session.
- A deterministic local torrent fixture supports initial buffering, forward seek reprioritization, cancellation, and hash verification without public peers.
- An unencrypted small disc fixture materializes and reaches libmpv's disc input when licensing/build support includes libbluray.
- Malformed media and native engine errors fail without a crash or sensitive log output.

### Build and release evidence

- Build and test the signed macOS target.
- Build the generic iOS Simulator target to prove the macOS-only change does not break mobile compilation.
- Run `git diff --check` on intended paths.
- Inspect final entitlements and signed nested libraries.
- Record dependency versions, licenses, hashes, SBOM, scan results, universal architectures, and reproducible-build evidence.
- Perform macOS smoke tests for direct opaque HTTPS, torrent playback and seek, cache exhaustion/recovery, offline behavior, track menus, resizing, full screen, keyboard, VoiceOver, and appearance/accessibility settings.

## Rollout and failure behavior

Local resolving is macOS-only and initially off until the user accepts the peer-participation disclosure. Direct HTTPS visibility and track-event fixes do not depend on enabling torrents.

Failures remain isolated by source. A resolver failure returns to the source sheet with retry and cleanup actions; it does not remove other candidates. Cache schema/version changes are forward-only or invalidate discardable entries safely. The existing remote resolver configuration is not contacted by local mode and can be retained only as inert migration data until a separate removal decision.

No release claim may say "all media works." The truthful contract is: Omnia shows all add-on sources, lets libmpv inspect every direct HTTPS source, locally resolves supported torrent/disc forms on macOS, exposes discovered embedded tracks, and clearly reports the remaining technical or policy limit.
