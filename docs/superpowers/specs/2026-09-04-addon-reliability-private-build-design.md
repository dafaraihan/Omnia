# Add-on Reliability Private Build Design

> **Automated-validation policy:** Follow the repository-root `AGENTS.md`. Instructions below that call for automated test targets, suites, fixtures, or scripts are historical and superseded; use builds, static checks, and focused manual evidence instead.

**Date:** 2026-09-04

## Goal

Make Omnia's existing private macOS build recover usable Stremio add-ons when one saved record loses its Keychain endpoint, distinguish malformed add-on responses from legitimate empty results, retain standard torrent candidates for the bundled local resolver, and stabilize the existing macOS player integration test.

## Evidence

- The current macOS target builds with `OMNIA_LOCAL_TORRENT=1`; `OMLocalTorrentEngine.isAvailable` is backed by libtorrent rather than the unavailable stub.
- Local preferences contain four add-on records. Three corresponding Keychain items exist; the AIOStreams item is missing.
- `InstalledAddonPersistence.load()` decodes the saved array in one operation and returns `[]` for any decoding failure. One missing Keychain item therefore hides every add-on.
- `StremioAddonClient.fetchStreamCandidates` silently ignores malformed JSON responses. When every response is malformed, the UI reports a legitimate empty result instead of a failure.
- `AddonStreamCandidate` already accepts the documented Stremio torrent representation: `infoHash`, optional `fileIdx`, and tracker sources. The local engine is selected for those candidates on macOS.
- The full test suite intermittently crashes while destroying an animated AppKit test window. The same test passes in isolation; the crash is in `_NSWindowTransformAnimation` teardown.

## Approved Scope

### Loss-tolerant add-on restoration

Decode stored add-ons independently. Return every valid add-on and a redacted issue containing only the unavailable add-on's public manifest identity. Never expose, log, or reconstruct a configured manifest URL. Do not automatically rewrite storage when any record failed restoration; this preserves the saved record until the user explicitly reinstalls or otherwise changes add-ons.

The settings screen shows a “Needs Attention” section for restore issues. Its copy tells the user to reinstall the named add-on because its secure configuration could not be restored. Installing an add-on with the same manifest ID removes its issue.

### Honest stream diagnostics

Treat a response that cannot decode as the documented `{ "streams": [...] }` object as a failed response. Continue trying other supported identifier/type combinations, preserving the current fallback behavior. If at least one valid response is received, keep its candidates or legitimate empty result; if no valid response is received, surface failure for that add-on.

The source sheet retains its existing per-add-on loaded, empty, and failed states. Torrent rows continue to use the current consent-gated local macOS resolver. No new protocol, dependency, hosted mutation, or torrent streaming architecture is introduced.

### macOS integration-test stability

Disable AppKit window animations on the hidden integration-test window. Production window behavior is unchanged.

## Non-goals

- Progressive playback before a torrent file has completed downloading.
- Supporting undocumented magnet URLs in `stream.url`.
- Weakening HTTPS, origin, size, timeout, sandbox, Keychain, or local-storage constraints.
- Deploying Supabase, changing App Store distribution, or adding dependencies.
- Broad UI redesign. That work follows a separately approved visual direction.

## Acceptance Criteria

- A missing Keychain endpoint for one stored add-on no longer hides valid sibling add-ons.
- The affected add-on is identified by name in Settings without revealing its endpoint or credentials.
- Reinstalling the same add-on clears the restore issue.
- Storage is not automatically rewritten after a partial restore.
- A fully malformed stream response yields a failed add-on state; valid empty plus a later failure remains a legitimate empty result.
- Standard `infoHash` torrent candidates remain classified for local playback.
- The focused tests pass, the flaky MPV test passes repeatedly, the full macOS test suite passes, and macOS plus iOS Simulator builds succeed.
