# Fresh sign-out and onboarding validation — 22 October 2026

Approved design: [spec](../superpowers/specs/2026-10-22-sign-out-onboarding-design.md).
Implementation: [plan](../superpowers/plans/2026-10-22-sign-out-onboarding.md).

## Source evidence

Before: account logout cleared the Auth session and active vault identity but kept profiles, library, preferences and onboarding completion. The onboarding AppPreview was a separate hand-built hero and thumbnails.

After: ordinary profile changes flush before Auth logout; upload failure aborts logout with the local session retained. Vault changes get a sync attempt and retain encrypted account-bound recovery if still pending. Successful Auth logout sets a persistent local-cleanup marker. Cleanup stops playback, clears profiles without deletion APIs/tombstones, detaches the library to a fresh persisted store identity, resets profile stores and standalone personal preferences, clears active add-on catalogs/search/shuffle/stream-cache/resolver configuration, and returns to welcome with rebuilt navigation. The marker blocks underlying content and supports cleanup retry/relaunch after interruption. Cloud deletion APIs are not called by reset.

Generation checks prevent old profile, library, add-on and plugin operations from repopulating the active session. Default add-ons install only when a profile exists, including after guest profile creation; welcome stays empty across relaunch.

Onboarding now renders production HomeView and MediaDetailView in a scaled, read-only viewport using public discovery titles and an empty library/add-on store. Preview mode suppresses credential ratings requests, preference writes, trailer loading/playback, auto advance, server/catalog requests, shuffle picks, resume prompts and transition/focus consumption. Manual Home/Title Details selection stays outside the disabled content. Loading/unavailable/retry and narrow-width layout are explicit. Reduce Motion removes spatial transitions and ongoing preview motion; Reduce Transparency gives the preview an opaque surface.

The previous encrypted account recovery snapshots and older detached library/profile files are retained; this is an active-session reset rather than a secure disk erasure. Deployment key backups are untouched.

## Checks completed

- `xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' build`: **BUILD SUCCEEDED**, canonical signed Debug product. Log: `/tmp/omnia-onboarding-build.log`.
- `git diff --check`: passed.
- Focused independent review: found pending ordinary-change loss and default add-on relaunch inconsistency; both addressed; final targeted review found no remaining blocker.
- Apple onboarding HIG Markdown reviewed from the official developer.apple.com page. Apple Design Resources page fetch failed; no kit assets copied or redistributed. UI uses existing production SwiftUI components.
- No automated tests/fixtures/scripts created or run, per repository policy. No hosted mutation, commit, push or DMG rebuild in this task.

## Runtime evidence still required

Computer Use failed with ScreenCaptureKit SCStreamErrorDomain -3811 (audio/video capture failure). Therefore no visual or interactive completion claim is made. A signed-in account was not forcibly logged out to simulate the new flow.

On supported Mac hardware, manually check:

1. Edit a setting then sign out immediately: changes upload before logout. Verify failed/offline upload leaves the session and a retryable error.
2. Sign out successfully: welcome, no active profiles/library/settings/secrets/sources; relaunch stays at welcome and installs no default add-ons until a profile exists.
3. Sign back into the same account: synced profiles/library/settings/credentials/sources restore; a different account/guest sees no prior active state.
4. Exercise interrupted cleanup/retry and pending credential recovery without exposing snapshots to guests.
5. View both production previews; verify discovery loading/offline/retry and continuing setup without waiting for artwork.
6. Check narrow/wide/resized windows, keyboard/focus, VoiceOver, larger text, Reduce Motion/Transparency, Increase Contrast and light/dark appearance.

The project currently exposes macOS as the supported build destination. No iPhone/iPad runtime or performance claim is made. The existing GitHub DMG does not contain these new native changes.
