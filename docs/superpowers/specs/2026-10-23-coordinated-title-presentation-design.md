# Coordinated title presentation

Status: user selected “Keep content visible while loading”, 23 October 2026. This overrides the proposed atomic reveal below.

## Request and verified source behavior

Show MDBList ratings, transparent title logo and enrichment together on Home heroes and title details. Remove the apparent previous-version hero action row during loading.

Current source: HomeView's metadata task publishes resolvedFeatured before a second task starts MDBList. TitleLogoView separately downloads artwork through CachedArtworkImage. MediaDetailView publishes provider/add-on intermediate items while its ratings task independently follows identifier changes. HeroActionRow is a single shared component, not separate legacy/new implementations; series watch actions appear only after episodes resolve, and ViewThatFits can select a different arrangement as controls change. Runtime reproduction of the reported visual swap remains required; prior Computer Use attempts failed with ScreenCaptureKit capture errors.

## Proposed behavior

- Resolve metadata/enrichment, MDBList ratings and logo artwork through a shared preparation pipeline, with independent requests started concurrently whenever their identifiers/URLs are already known. If metadata supplies a previously missing identifier or logo, start the newly possible request immediately.
- Publish a prepared presentation once all required requests have reached success, empty, unavailable or error. Do not publish intermediate metadata to the visible identity/actions/enrichment tree. Bind a presentation to its title and request generation; canceled or old-title results cannot appear under a new backdrop.
- Use one stable, accessible loading presentation before readiness, including reserved action geometry. Reveal only the current shared button component when prepared; do not introduce an old-style fallback. Retain responsive layout and disabled-action accessibility.
- Treat missing ratings, absent/dead logos and incomplete enrichment as terminal partial success, with the existing contextual retry/settings recovery. One failed provider must not leave the screen permanently loading. No fake ratings or invented metadata.
- Reuse existing metadata, artwork and ratings caches/request coalescing. Bound speculative preparation to the current and next Home hero; no all-catalog metadata fan-out. Include settings, credentials and source ownership in any added presentation-cache validity rules, and clear private state at sign-out.
- Keep provider/add-on precedence, integration toggles, preview side-effect suppression, and personalized watch/library state intact. Read watch/library state live after prepared metadata arrives.

## Limits and validation

Instant cold network retrieval cannot be guaranteed. Coordinated reveal trades intermediate visibility for a stable final presentation and can wait for the slowest provider. Do not claim faster loading without the before/after Release Instruments evidence required by PERFORMANCE.md.

Follow DESIGN.md/SECURITY.md. No backend deployment or new dependency is needed. Preserve pre-existing Keychain helper changes. Use canonical signed macOS builds and static checks; no automated tests/fixtures/scripts, per AGENTS.md. Verify warm/cold/offline/provider failure, hero switching while loading, settings/key changes, canceled navigation, logo failure, watch actions, read-only previews and accessibility. If Computer Use remains unavailable, record manual checks as pending. Commit/push/rebuild/release are not part of this change unless requested again.

## Approved amendment

Keep visible metadata/artwork and usable controls throughout loading. Do not wait for the slowest provider or hide the page behind a unified skeleton. Start ratings against known catalog identifiers in parallel with metadata/enrichment, and preserve successful same-title ratings if identifiers improve. Decode/cache logo art as soon as URLs are available. Prefetch only the next Home hero, through existing caches. Keep the current Home action geometry from first render, using a disabled watch action until episode information is available. All other precedence, cancellation, preview, failure, scope and validation constraints above remain applicable.
