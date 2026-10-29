# Enrichment, hero playback, and Continue Watching

## Intent and approved scope

The user requested seven improvements for Mac, iPad and iPhone, selected **A: Match Nuvio**, and clarified that missing MDBList hero ratings affect only iPhone. Continue Watching Card must use Apple system typography while its other presentation follows Nuvio. The supplied screenshots establish working ratings on Mac/iPad and absent ratings in the iPhone portrait hero.

## Approach

Nuvio-compatible enrichment replaces existing add-on fields with nonempty enabled provider data; empty/failed responses preserve source data. Gap-fill-only enrichment was the alternative and was not selected. Match Nuvio exceptions: keep an existing nonblank IMDb rating and retain source episode release dates; empty arrays do not erase source lists. Higher-priority providers win only for fields eligible for replacement. Honor the configured primary-provider order, with enabled secondary enrichment filling fields not supplied by the higher-priority provider. Preserve stable title/stream identities and watch progress. Do not implement backend deployment or add dependencies.

## Requirements

1. iPhone player presentation requests landscape before its loading screen is shown, keeps landscape during source recovery and PiP, and restores normal app orientation behavior on actual dismissal. iPad and Mac are not forced into phone orientation. Use public scene-specific UIKit APIs, not device-orientation KVC.
2. Add the existing MDBList ratings presentation and retry action to both iPhone portrait heroes. Existing loaders/credentials remain authoritative; do not disturb working Mac/iPad ratings or assume the credential is missing.
3. Resolve TMDB enrichment by stable provider/external IDs before conservative title/year fallback. Optional collection/studio/season failures must retain successful detail sections. Respect enabled modules, language and credential changes in request/cache identities. Keep secrets in existing Keychain ownership and diagnostics redacted.
4. Add TVDB Enrichment directly after TMDB Enrichment in Profile > General > Integrations > Integrations. Decode old settings safely. Implement real supported TVDB detail, artwork, credits, productions, trailers and season/episode data before exposing switches. Do not present unsupported recommendation/collection features as working. Existing users keep prior behavior until TVDB enrichment is enabled.
5. A playing Home/detail hero trailer opens in the normal full-screen player when its hero is tapped/clicked, with accessible keyboard activation. Preserve the resolved HLS master/audio rendition rather than reducing it to a URL. Use an explicit trailer playback purpose so trailers do not change Continue Watching, scrobble, invoke title recovery/skip/next-episode automation, or start duplicate audio.
6. While a hero trailer is actually playing and visible, hide the logo/title, metadata identity, synopsis, ratings, action buttons and carousel dots from rendering, hit testing and accessibility. Preserve hero geometry and the mute control. Restore identity on stop/end/failure/offscreen/inactive state. Stale callbacks must not affect a newly selected hero.
7. Match the pinned official Nuvio Card reference for landscape aspect ratio, adaptive sizing, gradient, artwork fallback, remaining/next-up badges, bottom progress and context actions; use Apple system fonts and native accessibility/keyboard behavior. Preserve Omnia's Card/Wide/Poster settings and intentional actions, paused-scene option, spoiler preference and existing history ownership.

## Boundaries and states

Reuse existing clients, player engines, credentials, settings and native controls. Media/provider URLs remain untrusted; use existing validated HTTPS/playlist boundaries, cancellation, bounded work, and no secret-bearing diagnostics. Loading/partial/offline/failure preserve useful metadata; retry is explicit. Unavailable enrichment must not erase existing title information. Empty hero/trailer states keep existing artwork and identity. Destructive history actions retain existing confirmation semantics.

## Evidence and verification

Primary references and differences: ../../research/2026-10-29-nuvio-enrichment-and-continue-watching.md. Source-confirmed iPhone ratings cause: PortraitHeroIdentity renders metadata/synopsis/actions but no ratings view. TMDB lookup currently omits IMDb lookup and optional requests can fail the entire response. Current TVDB normalization discards rich extended fields.

Repository policy forbids automated test targets, fixtures and test scripts. Verify with canonical signed macOS/iOS builds, static checks, focused manual iPhone/iPad/Mac flows and documented remaining device/accessibility limitations. Keep exactly one current app build at handoff. No performance claim is supported without the required hardware evidence. New release packaging or hosted mutation is outside this implementation scope.
