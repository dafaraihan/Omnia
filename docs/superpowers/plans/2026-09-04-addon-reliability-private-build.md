# Add-on Reliability Private Build Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore usable add-ons independently, report damaged secure configurations and malformed responses accurately, and produce a verified private macOS build.

**Architecture:** `InstalledAddonPersistence` returns a structured load result containing valid add-ons and redacted restore issues. `OmniaStore` owns those issues for presentation and clears one when that add-on is reinstalled. Stream decoding records malformed responses as failures while retaining the existing multi-identifier fallback and local torrent boundary.

**Tech Stack:** Swift 5, SwiftUI, Observation, Foundation, Security/Keychain, XCTest, AppKit, Xcode 26.

**Spec:** `docs/superpowers/specs/2026-09-04-addon-reliability-private-build-design.md`

## Global Constraints

- Preserve existing design and working behavior unless required by the approved repair.
- Do not expose or log configured add-on URLs, tokens, torrent hashes, or credentials.
- Do not introduce dependencies or hosted mutations.
- Keep torrent playback macOS-only and consent-gated.
- Work in the explicitly approved current checkout; do not stage or commit user work.

---

### Task 1: Loss-tolerant add-on restoration

**Files:**
- Modify: `OmniaTests/InstalledAddonPersistenceTests.swift`
- Modify: `Omnia/Data/Addons/InstalledAddonPersistence.swift`
- Modify: `Omnia/App/OmniaStore.swift`

**Interfaces:**
- Produces: `InstalledAddonRestoreIssue`, `InstalledAddonLoadResult`, and `InstalledAddonPersistence.load() -> InstalledAddonLoadResult`.
- Produces: `OmniaStore.installedAddonRestoreIssues: [InstalledAddonRestoreIssue]`.

- [ ] Write failing persistence tests proving one missing Keychain item preserves its valid sibling and reports only the public identity.
- [ ] Run the focused persistence tests and verify the new behavior fails with the all-or-nothing loader.
- [ ] Decode array elements independently and return valid add-ons plus redacted issues.
- [ ] Assign the result in `OmniaStore`, skip migration re-save after partial restoration, and clear the matching issue in `add(_:)`.
- [ ] Run the focused persistence tests and verify zero failures.

Focused command:

```sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' -only-testing:OmniaTests/InstalledAddonPersistenceTests test
```

### Task 2: Restore issue presentation

**Files:**
- Modify: `Omnia/Features/Settings/AddonsSettingsView.swift`
- Test: `OmniaTests/InstalledAddonPersistenceTests.swift`

**Interfaces:**
- Consumes: `OmniaStore.installedAddonRestoreIssues`.
- Produces: a redacted “Needs Attention” settings section.

- [ ] Add a failing store assertion that reinstalling an add-on with the same ID clears its restore issue.
- [ ] Add the settings warning row with reinstall guidance and no endpoint data.
- [ ] Run focused tests and build the macOS target.

### Task 3: Malformed stream-response diagnostics

**Files:**
- Modify: `OmniaTests/StremioAddonClientTests.swift`
- Modify: `Omnia/Data/Addons/StremioAddonClient.swift`

**Interfaces:**
- Consumes: existing `AddonClientError` and multi-identifier request loop.
- Produces: an error when no request yields a valid stream response.

- [ ] Write a failing malformed-response test using the real client and controlled transport.
- [ ] Run it and confirm the current client incorrectly returns an empty array.
- [ ] Record decoding failure, continue later identifiers, and throw only when no valid response was received.
- [ ] Run client, identifier, and local torrent tests.

Focused command:

```sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' -only-testing:OmniaTests/StremioAddonClientTests -only-testing:OmniaTests/SourceIdentifierTests -only-testing:OmniaTests/LocalTorrentPlaybackTests test
```

### Task 4: Stabilize the macOS player integration test

**Files:**
- Modify: `OmniaTests/MPVPlaybackIntegrationTests.swift`

**Interfaces:**
- Production code is unchanged.

- [ ] Set `window.animationBehavior = .none` before showing the test window.
- [ ] Run the focused test for ten iterations and confirm no crash.

```sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' -only-testing:OmniaTests/MPVPlaybackIntegrationTests/testLocalMultiTrackFixtureRendersAndSupportsExplicitTrackSelection -test-iterations 10 test
```

### Task 5: Full verification and smoke test

**Files:**
- Review only; no expected new files.

**Interfaces:**
- Consumes all preceding tasks.

- [ ] Run the full macOS test suite.
- [ ] Build macOS and generic iOS Simulator destinations.
- [ ] Launch the signed macOS app and inspect Add-ons plus source-selection states.
- [ ] Run `git diff --check`, inspect status, and review only intended paths.

```sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' build
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'generic/platform=iOS Simulator' build
```
