# Settings Phase 0A: Evidence and Contracts Design

> **Automated-validation policy:** Follow the repository-root `AGENTS.md`. Instructions below that call for automated test targets, suites, fixtures, or scripts are historical and superseded; use builds, static checks, and focused manual evidence instead.

**Status:** Approved on 2026-08-11

**Scope:** Evidence, domain contracts, security boundaries, feature gates, and deterministic test infrastructure

**Production UI:** Unchanged

## Objective

Establish the contracts that every later Settings phase must use before adding controls or connecting providers. Phase 0A records current behavior, makes unsupported features impossible to expose in Release, and supplies deterministic test doubles. It does not migrate user data, call live providers, deploy Supabase resources, or enable unfinished Settings rows.

## Repository Baseline

The starting worktree is intentionally dirty and must be preserved. Current overlapping work includes `SettingsView.swift`, `OmniaStore.swift`, add-on networking, source resolution, libmpv integration, metadata routing, Xcode configuration, tests, and the Supabase metadata function. The baseline procedure records:

- branch, HEAD, staged and unstaged paths, untracked paths, and diff statistics;
- Xcode and SDK versions, supported destinations, deployment targets, signing configuration, and bridging-header resolution;
- current macOS and iOS build outcomes;
- current macOS XCTest and Deno metadata-test outcomes;
- reproduced source-selection, video, audio-track, and subtitle-track behavior without live-provider mutation;
- known pending checks, including physical devices, iPad multitasking, Release archives, notarization, Instruments, provider credentials, legal approval, and hosted deployment.

Baseline failures are evidence, not permission to rewrite unrelated work. Every Phase 0 change must be reviewable independently from the existing diff.

## Domain Boundaries

### Profiles

`ProfileID` identifies either the durable device-only profile or one signed-in Omnia account. Device data and account data never share a persistent store. Signing in changes the active profile only after the destination store opens successfully; it does not migrate existing device data. A later migration flow may copy data only after explicit preview and confirmation.

Account switching cancels profile-scoped work. Every asynchronous result carries the originating `ProfileID` and is rejected if that profile is no longer active.

### Commands and Events

UI and playback code issue typed domain commands. Commands contain a stable command ID, profile ID, correlation ID, timestamp from an injected clock, and a bounded typed payload. They never contain credentials, authorization callbacks, signed URLs, subtitle dialogue, prompts, model output, or raw provider responses.

A command handler validates the current projection and emits one or more immutable, versioned domain events. Phase 0A defines event envelopes and protocols; Phase 0B supplies persistence and replay.

Initial event families cover:

- profile lifecycle and explicit migration intent;
- progress recording, completion, clearing, and conflict decisions;
- watchlist addition, removal, and conflict decisions;
- authoritative-owner selection by data type;
- provider connection state without secret material;
- delivery acknowledgement, rejection, retry scheduling, and cancellation;
- retention-policy changes and verified erasure operations.

### Ownership

`DataOwner` is typed and exhaustive. Continue Watching, Watchlist, and anime progress each have exactly one owner. The local device is always the durable write-ahead authority while offline, but it does not become a second remote mirror. Provider changes require an explicit migration policy: copy, replace, or start empty. No default silently merges data.

### Provider Adapters

Provider code conforms to narrow capability protocols rather than one universal service interface. Separate capabilities cover progress reads/writes, watchlist reads/writes, upcoming-content reads, anime status, skip-segment reads, and subtitle translation. Unsupported capabilities cannot be called or displayed.

All adapters accept an injected transport, clock, retry policy, credential reference, and cancellation context. Unit tests use fixtures and fakes only. Live API calls are prohibited from automated tests.

## Feature Gates

Feature gates have compile-time availability and runtime readiness. Both must be true before a feature can appear or execute.

- AniList and PublicMetaDB are compiled Release-disabled until written authorization, reviewed terms, production credentials, and release evidence exist.
- Trakt remains unavailable until Omnia has a registered application and a reviewed server-side client-secret and refresh-rotation design.
- OpenRouter remains unavailable until subtitle parsing, consent, OAuth-PKCE, ZDR routing, model eligibility, structured-output, and failure-isolation tests pass.
- Supabase cloud synchronization remains uncomposed. Authentication alone does not imply synchronization.
- Runtime configuration cannot override a Release-disabled gate.
- Settings queries capability state and omits unavailable actions. It does not render decorative or permanently disabled provider controls.

Tests build the Release gate table and prove prohibited features cannot be activated through persisted values, deep links, debug defaults, or runtime configuration.

## Hardened Networking Contract

All new integrations use a shared transport abstraction backed by dedicated ephemeral `URLSession` configurations. `URLSession.shared` is not permitted for provider or add-on traffic.

Each request declares:

- allowed scheme, host, port, method, content type, and redirect behavior;
- connection and resource deadlines;
- request and response byte limits;
- concurrency class and cancellation ownership;
- whether retry is safe and which documented status headers govern it;
- whether credentials or request headers may be attached to the exact origin.

Redirect targets are validated before following them. Authorization and add-on-supplied headers never cross origins. Decoding begins only after status, media type, and response-size validation. Diagnostics record a provider name, operation, status class, duration bucket, and correlation ID—not full URLs, queries, bodies, credentials, subtitle text, or private payloads.

### Local-Network Add-ons

Loopback, link-local, and private-network destinations are denied by default. A user may grant one installed add-on access to exact, normalized private HTTPS hosts. Approval requires a native disclosure and Apple Local Network permission where applicable. Wildcards and subnet grants are not supported. DNS results are checked immediately before each request and every redirect; a public hostname resolving to any private address is rejected unless that exact host is granted. This reduces DNS-rebinding exposure, but Foundation does not publicly guarantee that `URLSession` connects to the same answer inspected during preflight. The residual time-of-check/time-of-use race remains a documented security limitation unless a separately reviewed address-pinning transport replaces `URLSession`. Revocation is visible and immediate.

## Credential Contract

Provider secrets use profile- and provider-scoped Keychain records with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and synchronization disabled. OAuth callbacks require an exact scheme, host, path, state, active transaction, and one-time code. Disconnect cancels active work before deleting the credential and credential-dependent cache. Events may record that a connection changed state, but never the credential or callback.

## Test Infrastructure

Phase 0A adds deterministic substitutes for:

- wall and monotonic clocks;
- identifier generation;
- network transport and redirect decisions;
- reachability and cancellation;
- credential lookup without exposing secret values;
- provider acknowledgements and rate-limit responses;
- feature-gate build/runtime inputs.

Fixtures cover valid, malformed, oversized, slow, redirected, cancelled, unauthorized, expired, rate-limited, duplicate, reordered, and partial responses. No fixture contains a real credential or private production payload.

## Verification and Acceptance

Phase 0A is complete when:

1. Current behavior and failures are captured without changing hosted state.
2. Domain, capability, transport, diagnostic, credential, and feature-gate contracts compile on macOS and generic iOS Simulator.
3. Red/green tests prove profile-context rejection, capability absence, Release gating, redirect/header isolation, response bounds, cancellation, and log redaction.
4. Existing focused tests still pass or any pre-existing failure is documented with exact evidence.
5. The macOS app builds and signed XCTest runs; the generic iOS Simulator build succeeds.
6. Deno metadata tests run frozen with the tracked lockfile unchanged.
7. `git diff --check` passes and the Phase 0A diff contains no hosted mutation, production credential, provider enablement, or unrelated cleanup.
8. Physical-device, accessibility, archive, legal, hosted, and Instruments checks remain explicitly pending until performed.

## Official References

- [Apple Design Resources](https://developer.apple.com/design/resources/)
- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- [Apple accessibility guidance](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [Trakt authentication](https://docs.trakt.tv/docs/authentication-oauth)
- [AniList terms](https://docs.anilist.co/guide/terms-of-use)
- [IntroDB API](https://introdb.app/docs/api)
- [OpenRouter OAuth PKCE](https://openrouter.ai/docs/guides/overview/auth/oauth)
- [OpenRouter ZDR](https://openrouter.ai/docs/guides/features/zdr)
- [Supabase Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)
