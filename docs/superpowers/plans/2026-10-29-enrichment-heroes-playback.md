# Enrichment, Heroes and Playback Implementation Plan

**Goal:** Implement the seven user-requested changes with Nuvio enrichment precedence, iPhone-only ratings repair, and Apple typography.
**Architecture:** Keep native presentation and existing provider/player boundaries. Explicit trailer purpose isolates short-form playback from title history. Each independent subsystem has owned files; Home/detail wiring stays with the coordinator.
**Tech Stack:** SwiftUI, UIKit, AVFoundation/AVKit, libmpv, existing HTTP clients.
**Spec:** ../specs/2026-10-29-enrichment-heroes-playback-design.md

## Global constraints

No new dependencies, test suites/scripts/fixtures, hosted deployment, credential logging or custom DerivedData. Preserve user changes and existing Mac/iPad ratings. Nuvio behavior is implemented independently in SwiftUI; preserve GPL provenance links.

## Review focus

- External-ID matching, conflicting provider data, partial provider failures and stale/language-specific cache entries.
- Portrait ratings, long text/large type, hidden hero accessibility and restore after trailer end/failure.
- Separate HLS audio/master preservation, trailer history isolation, source replacement and repeated handoffs.
- Scene rotation before loading, dismiss/error/PiP transitions and orientation restoration.
- Next-up, unknown durations, spoiler artwork, saved scenes, card size settings and native context actions.

## Tasks

- [x] Confirm portrait ratings root cause, record approved design and pinned Nuvio comparison.
- [x] Extract the unchanged ContinueWatchingCard into its own feature file, then implement adaptive Nuvio-style presentation with system fonts and existing actions.
- [x] Implement TMDB ID resolution/partial-success behavior and Nuvio merge policy, plus TVDB supported enrichment data, settings routes and backward-compatible preferences. Own metadata/settings/domain files; coordinator wires Home/detail request keys and merge call sites.
- [x] Implement scene-specific iPhone player orientation and explicit trailer launch/purpose/HLS transport. Own playback/platform/root/trailer model files; expose launch API to Home/detail coordinator.
- [x] Wire portrait ratings and conditional hero identity/dots/fullscreen trailer actions in Home/detail and PortraitHeroIdentity; retain mute and generation protections.
- [x] Build affected destinations sequentially from canonical DerivedData; run diff checks; independently review the complete diff and repair important findings. Document manual evidence and any device-only gaps before handoff.

Local implementation/build/review gates completed. Device acceptance remains pending; see ../../verification/2026-10-29-enrichment-heroes-playback.md.
