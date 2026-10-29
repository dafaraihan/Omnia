# iOS Playback Implementation Plan

**Goal:** Complete the approved iOS player and appearance improvements.
**Architecture:** Retain shared controls while sizing them to the viewport; own device volume and AVKit PiP at the iOS platform boundary.
**Tech Stack:** SwiftUI, UIKit, AVKit, MediaPlayer, Icon Composer.
**Spec:** ../specs/2026-10-29-ios-playback-design.md

## Global Constraints

No automated tests or scripts; use canonical signed builds, static checks, and focused manual checks. No hosted mutations or new dependencies. Preserve macOS behavior.

## Review Focus

- Short landscape height, safe areas, large text, and panel dismissal.
- Hardware volume and route changes without double attenuation.
- PiP startup failure, unsupported sources, source replacement, and restoring position.
- Home gesture versus in-player brightness/volume swipes.
- Light/dark/clear icons on installed iOS builds.

## Tasks

- [x] Adapt shared chrome to iPhone viewport and remove global scaling; move gesture feedback and expose percentages. Verify source and simulator layout where possible.
- [x] Add system-volume observation/control without attenuating the media twice. Verify build and reserve hardware/route checks for device.
- [x] Add AVKit PiP ownership, background audio, compatible native-source handoff, failure recovery, and automatic Home transition. Verify build; record device-only checks and compatibility limits.
- [x] Verify Icon Composer compilation for iOS and adaptive appearances; correct build inputs if necessary.
- [x] Build affected destinations, review diff, run diff whitespace check, document evidence, and commit all intended changes.

## Handoff

Implementation and local build/static checks completed. Physical iOS signing and runtime acceptance remain blocked by the missing provisioning profile; see `../../verification/2026-10-29-ios-playback.md`. Repository policy supersedes skill test-script workflows; no test scripts were run. Independent review findings were addressed before commit.
