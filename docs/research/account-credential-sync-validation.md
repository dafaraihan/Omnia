# Account credential sync validation — 2026-10-22

This records the original local implementation phase. Subsequent authorized
backend activation is recorded in [deployment evidence](account-credential-vault-deployment-2026-10-22.md).

## Scope

Implemented the approved sign-in-only vault: user-owned provider keys (including
plugin TMDB), PIN salt/verifiers, media-server connections/tokens, Live TV source
configuration/credentials and imported playlist attachments. The native boundary
uses existing Keychain accounts, an account-scoped coordinator, encrypted payload
blobs/metadata, explicit deletion/revision conflicts and recoverable local writes.
The cloud source contains Auth verification, server-key AES-GCM, service-only RLS
storage/RPC, atomic CAS, quotas and bounded scheduled cleanup.

Prior title-detail changes and untracked Keychain-interaction helpers were
preserved. No commits, pushes, automated tests/fixtures/scripts, hosted mutations,
secret installation, deployments or new DMG were performed.

## Commands and observed results

- `xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' build`:
  passed with valid Apple Development signing. Pre-existing Swift concurrency
  warnings remain in media-server mapping and other sources; a passing build is
  not evidence that those unrelated warnings are resolved.
- `deno check --config supabase/functions/credential-vault/deno.json --lock supabase/functions/credential-vault/deno.lock --frozen supabase/functions/credential-vault/index.ts`:
  passed.
- `git diff --check`: passed.
- `xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'generic/platform=iOS Simulator' build`:
  blocked before compilation: current project/scheme lists macOS only
  (`SUPPORTED_PLATFORMS = macosx`). Platform settings were not changed.
- `supabase db lint --local`: unavailable local database, `LegacyDbConnectError`.
  Migration application, cron installation and SQL/runtime grants are unverified.
- Exactly one physical current app product remains in canonical project
  DerivedData; `/Applications/Omnia.app` links to it. No simulator app was created.

## Source review and repairs

Independent native and server reviews were performed. Fixed identified issues:

- Native list bound disagreed with retained tombstones; now accepts 2,000 total
  rows while the backend separately limits 1,000 active entries.
- Inactive accounts lacked attachment GC; private bounded hourly pg_cron cleanup
  now supplements request cleanup. Monitor the backlog; 24h is eligibility.
- Provider/PIN payloads are JSON strings; server validation now accepts their
  exact types instead of rejecting all non-object payloads.
- Failed sign-out now runs explicit credential reattachment completion.
- Edits made during an upload schedule another pass; pending/conflict state no
  longer reports an unconditional success timestamp.
- Missing PIN verifiers have a distinct unavailable result and retry controls
  accessible from both the picker and PIN sheet.
- Interrupted remote writes persist staged IDs, which recover before local
  capture; account transitions persist both snapshots before publishing ownership
  and use a Keychain recovery marker around live detachment.
- First-use Keychain retry distinguishes an absent snapshot from a saved empty
  one, preserving the installation's existing credentials.
- Payload filenames use device-key HMAC references; individual encrypted blobs
  avoid base64-encoding an entire collection of large playlists into metadata.

The final targeted reviewers reported no direct native blocker and no material
server validation/cleanup finding. These were source reviews, not runtime checks.

## Required pending evidence

The complete manual matrix and release gates are in
[INFRASTRUCTURE.md](../../INFRASTRUCTURE.md#account-credential-vault-release-gate).
In particular, local SQL apply/lint and two-account RPC/table isolation, two-device
fresh restoration, Keychain write failures, interruption recovery, concurrent
edits/deletions, partial/corrupt playlist restore and sign-out/account switching
remain unperformed. Native UI automation previously timed out in this session;
visual/accessibility checks (VoiceOver, Dynamic Type, keyboard/focus, appearances,
reduced motion/transparency, contrast and supported form factors) remain pending.

UI uses native SwiftUI progress, labels, buttons and existing confirmation controls.
Current reference consultation: Apple Design Resources,
[progress indicators](https://developer.apple.com/design/human-interface-guidelines/progress-indicators)
and [privacy](https://developer.apple.com/design/human-interface-guidelines/privacy).
No performance improvement is claimed; no Release/Instruments baseline was captured.

At the end of the local implementation phase, backend activation was pending.
It has since completed under separate owner authorization; see the deployment
record linked above. The remaining native/device limitations still apply.
