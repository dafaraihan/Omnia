# Progressive title loading — 23 October 2026

User explicitly selected **Keep content visible while loading**, overriding the earlier proposed atomic reveal. [Amended design](../superpowers/specs/2026-10-23-coordinated-title-presentation-design.md), [plan](../superpowers/plans/2026-10-23-progressive-title-loading.md).

## Source evidence and changes

Before: Home waited for resolved metadata before starting MDBList. Logo artwork loaded separately when its URL became available. Add-on Home heroes did not start provider enrichment alongside add-on resolution. The optional episode watch control appeared only after episode data arrived, changing action-row composition/alignment. Detail ratings request identity included every external identifier, including changes irrelevant to the effective MDBList route.

After:

- Home requests ratings from available catalog identifiers concurrently with metadata. Add-on Home heroes also start provider enrichment concurrently, publishing useful results while retaining owning add-on precedence. New identifiers can trigger a fallback provider match.
- Both Home and details use the actual validated MDBList route for rating task identity. Unrelated identifier changes do not restart ratings. Successful same-title ratings stay visible during route enrichment; title-scoped rendering prevents another hero's ratings from leaking across a selection change.
- Home prepares only the next candidate, warming metadata, available ratings and decoded transparent-logo artwork through existing caches. Identifiers/URLs discovered by enrichment start further preparation only while the task remains current. Speculative preparation does not record provider preferences or mutate visible hero state.
- Home always reserves the current watch-control slot. Without usable episode data it is disabled and labeled Loading Episode Information / Episode Information Unavailable, rather than inserting a button after loading. Current shared responsive action styling remains unchanged.
- Same-source same-title refreshes retain visible content. Changing add-on source configuration clears the previous source's resolved fields. Add-on metadata cache identities include enabled sources, identifiers and origin.
- Ratings cache entries/in-flight work are scoped to a non-logged SHA-256 credential fingerprint, bounded to 120 entries, and checked against the current key after await. Dedicated provider-ID-only notifications reset ratings for local and vault-applied MDBList key changes without responding to unrelated vault changes. Cancellation owned by a superseded request cannot publish; still-current cancellation settles loading.

No shared backend secrets, new dependency, endpoint or hosted setting is introduced. Credential fingerprints and add-on cache identity remain in memory, with no secret-bearing diagnostics.

## Validation

- Signed canonical macOS Debug build: `xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' build`. Latest log: `/tmp/omnia-progressive-build.log`.
- Focused independent source review found unstable JSON task identity, credential cache scoping and clearing same-title content during refresh. Addressed using sorted encoding, credential-scoped cache/rechecks and source-only invalidation.
- `git diff --check` and nested signature verification performed at handoff.
- Computer Use could read an existing Home accessibility tree with ratings and actions. Its screenshot showed video playback instead of that Home tree. The running session was not interrupted/relaunched, so this is **not** a visual or interactive validation of the newly built code.
- No automated tests, fixtures, or scripts created or run, per repository policy. Pre-existing Keychain helper edits preserved. No commit, push, DMG rebuild, or release update in this task.

## Remaining manual evidence

Check cold/warm Home entry, arbitrary detail navigation, next/previous/rapid hero selection, missing identifiers, failed logo, unavailable/rate-limited ratings, API key replacement/removal, module toggles, source reconfiguration, preview mode, and narrow/wide action layout. Verify VoiceOver, keyboard/focus, large text, Reduce Motion/Transparency, contrast and light/dark appearance.

This change starts independent work earlier and reuses/prepares caches; it does **not** guarantee instant network delivery or simultaneous completion. No speed, memory, energy, or performance-target claim is made. Before/after Release Instruments measurements on the same supported hardware remain required by PERFORMANCE.md.
