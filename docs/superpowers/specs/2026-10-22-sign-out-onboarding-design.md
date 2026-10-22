# Fresh sign-out and real onboarding previews

Status: approved by user, 22 October 2026. Implementation refinement: flush ordinary profile changes before Auth logout; failed flush keeps the signed-in session.

## Requested outcome

Successful sign-out returns to welcome onboarding with no active profile, library, viewing progress, add-ons, plugins, personal settings, provider credentials, media servers, or Live TV sources. Cloud account data remains intact and restores after sign-in. Reset is local detachment, never profile deletion or a cloud tombstone.

Preserve unsynced credential changes only as an encrypted, account-bound recovery snapshot, hidden from guests and other accounts. Clearly explain this exception in the sign-out confirmation. Do not erase the separate deployment key backup. Failed sign-out must retain a usable signed-in session and report the error.

## Reset boundary

Stop playback and cancel/invalidate asynchronous profile, library, provider and sync work before clearing active stores. Ensure late responses cannot refill the guest session or upload reset values. Reset onboarding completion and rebuild navigation only after authentication sign-out succeeds. Do not call existing profile deletion APIs, which also delete hosted profile data. Reset both in-memory state and its persisted active representation; reopening the app must still show welcome.

Use explicit store reset operations rather than deleting the complete defaults domain or arbitrary Application Support directories. Keep metadata/artwork caches, which contain discovery content rather than account settings. Pending ordinary profile data needs a safe disposition before reset; no claim of successful cloud restoration for data that never uploaded.

## Onboarding preview

Replace the imitation window's hand-built hero and poster thumbnails with the production Home and title-detail views at realistic layout dimensions, scaled into a preview viewport. Offer explicit Home/Title Details selection; select a real discovered title for details. Disable content interaction, playback, resume prompts, credential mutations, and unnecessary background tasks within preview mode. Share normal presentation components and discovery data rather than screenshots or duplicate layouts. Preview must never enter the user's navigation stack or alter their library.

Keep onboarding's primary Continue/Back actions reachable at narrow Mac window widths. Provide discovery loading, empty/unavailable, and retry states. Preview is supplementary to accessible explanatory text. Respect Reduce Motion and Reduce Transparency; avoid perpetual floating or automatic page switching. Preserve sign-in, skip-account and profile-creation paths.

## Validation

Follow DESIGN.md, SECURITY.md and repository validation policy. Build the supported macOS destination using canonical DerivedData and signing. Check diff whitespace and intended paths. Manually verify sign-out/relaunch, failed/offline sign-out, pending changes, same-account restoration, different-account isolation, real preview rendering, unavailable metadata, keyboard/VoiceOver, appearance, contrast, reduced motion/transparency and resizing. Record unavailable runtime checks honestly. Do not create automated test infrastructure or deploy hosted changes.
