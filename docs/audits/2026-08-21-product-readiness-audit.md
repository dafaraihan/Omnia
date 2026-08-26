# Omnia Product-Readiness Audit

Date: 2026-08-21  
Snapshot: `native/settings-capability-overhaul` at `7a0eccb`, including the uncommitted working tree  
Scope: read-only build, test, architecture, infrastructure, visual/accessibility, performance, and security review

## Executive verdict

Omnia is a substantial pre-release application, not an empty prototype. The current snapshot compiles in Debug for macOS and iOS Simulator, the signed macOS XCTest suite passes, and the code already contains unusually careful local-media, add-on, HTTP, Keychain, RLS, and native-playback controls. The repository also accurately documents many of its own gaps.

It is not ready for distribution or a production-readiness claim. The release path is intentionally blocked by incomplete native dependency provenance; OAuth callback acceptance is broader than the documented trust contract; cloud library synchronization exists but is not connected to app state; the public metadata path lacks production abuse and upstream-request bounds; CI, environment separation, privacy packaging, performance evidence, and device-level UI evidence are absent; and one repository smoke script currently fails.

The right direction is a focused productization program, not a rewrite. Preserve the domain policies and bounded adapters that already earn their keep. Concentrate behavior behind a few deeper interfaces, connect the currently disconnected product flows, and make release/security/performance claims depend on repeatable evidence.

## Evidence and limitations

### Commands run

| Check | Result | What it proves |
| --- | --- | --- |
| macOS Debug build | Pass | The current working snapshot compiles and signs with the available Apple Development identity. |
| Generic iOS Simulator Debug build | Pass | The current working snapshot compiles for the two iOS Simulator architectures. |
| Generic iOS Simulator Release build | Pass | Optimized simulator compilation succeeds; this is not a signed device archive. |
| macOS Release build without artifact root | Fail: exit 65 | The expected pinned native input is unavailable; compilation stops at missing `mpv/client.h` before producing a distributable. |
| macOS XCTest | Pass | The signed app-hosted suite, including libmpv and disc integration tests, completes successfully. |
| Deno frozen check | Pass | `supabase/functions/metadata/index.ts` type-checks against the committed lock. |
| Deno tests | Pass: 2, fail: 0 | The two TVDB identifier tests pass. This is very narrow Edge Function coverage. |
| Native repository scripts | 8 pass, 1 fail | Artifact, manifest, entitlement, staging, configuration, SBOM, and build-plan checks pass; the standalone torrent descriptor test no longer compiles. |
| Local Supabase status/lint | Not run | Docker is not running, so local database health, reset, migrations, lint, and RLS behavior were not exercised. |

The macOS test and Release builds emit multiple actor-isolation warnings across tests and local-media persistence. Several diagnostics explicitly say they become errors in Swift 6 language mode. The app target is currently set to Swift 5 mode while its packages compile in Swift 6 mode.

This audit did not run a physical iPhone or iPad, launch an iOS Simulator flow, exercise hosted Supabase, deploy anything, archive/notarize a release, run Instruments, test VoiceOver/Full Keyboard Access, or conduct a visual review on all supported form factors. No claim below substitutes for those gates.

### Current working-tree caution

The reviewed snapshot already contained 23 modified tracked files with 563 additions and 98 deletions, plus untracked settings, tests, and design notes. The audit did not alter those changes. Its only additions are this report and the [official primary-source brief](2026-08-21-primary-sources.md).

## Highest-priority findings

### P0 — block distribution or production claims

#### 1. Make OAuth callback acceptance exact and transaction-bound

`OmniaAccount.handle(callback:)` currently checks only that the incoming URL scheme equals `omnia`, then passes the URL to Supabase. It does not itself require the exact `omnia://auth-callback` host/path, record an active OAuth transaction, reject replay, or distinguish unrelated custom-scheme routes. The app forwards every custom-scheme URL that is not an add-on install callback into this method.

Direction: create one deep Auth module whose interface owns “begin transaction,” “accept callback,” “restore,” and “sign out.” It should require the canonical normalized callback, an active provider/PKCE transaction, single consumption, cancellation/expiry, and redacted errors. Test positive, wrong-host, wrong-path, missing-transaction, duplicate, replay, and concurrent-provider cases on iOS and macOS. Preserve Sign in with Apple’s nonce flow.

Evidence: `Omnia/Core/Cloud/OmniaAccount.swift:43-64`, `Omnia/Core/Cloud/OmniaAccount.swift:74-132`, `Omnia/App/OmniaApp.swift:56-61`. This matches existing roadmap item `P0.1` in `FUTURE-UPDATES.md`.

#### 2. Close the macOS native release provenance gate

The native dependency manifest correctly marks the closure incomplete and review pending. Several components lack independent publisher evidence; libbluray is explicitly release-blocked because its signature uses an expired DSA/SHA-1 key. Release also disables Xcode user-script sandboxing, and the packaging phase always runs.

Direction: finish the full transitive SBOM/license/provenance review, produce deterministic universal artifacts on controlled clean builders, require a second reviewer, record pre-signing hashes, enable the script sandbox or isolate packaging in a documented controlled builder, then verify nested signatures, effective entitlements, notarization, stapling, Gatekeeper, clean-machine launch, and playback. Do not substitute the successful Homebrew-backed Debug build for this gate.

The unaided macOS Release build currently fails at the compiler with missing `mpv/client.h`, rather than an early actionable message explaining how to supply the reviewed artifact root. Add a preflight gate before native compilation so local and CI failures identify the missing or unverified release input directly.

Evidence: `NativeDependencies/playback-dependencies.json:1-22`, `NativeDependencies/playback-dependencies.json:70-82`, `Omnia.xcodeproj/project.pbxproj:462-540`. Existing roadmap item: `P0.2`.

#### 3. Prove the hosted identity/data boundary before enabling cloud features

The SQL migrations use ownership predicates, `USING` plus `WITH CHECK`, RLS, and separate server-managed tables; those are good foundations. They do not prove hosted state. The local stack could not be inspected because Docker was not running. Production grants, policies, Auth redirect configuration, migration history, Realtime publication, and cross-user denial therefore remain unknown.

Direction: against an explicitly authorized non-production target first, export and compare schema/grants/Auth settings, then run anon and two-user CRUD/isolation tests for every table and Realtime channel. Repeat against the intended production target only through the infrastructure runbook. Record the project ref, migration list, timestamp, test identities, and redacted evidence.

Evidence: `supabase/migrations/20260728174215_omnia_sync_and_metadata_contract.sql:7-126`, `supabase/migrations/20260729165952_discovery_catalog_pool.sql:4-29`. Existing roadmap item: `P0.1`.

#### 4. Repair the broken standalone regression gate

`Scripts/Tests/local-torrent-descriptor-tests.sh` compiles `LocalTorrentPlayback.swift` in isolation, but that file now references `DiscPlaybackRequest` and `MaterializedDisc`; the script does not include the files defining those types. The full XCTest suite passes because the app target supplies them, so this is specifically a stale standalone test harness.

Direction: either add the required domain/data sources to the standalone compilation or reduce the smoke fixture to the descriptor policy it intends to verify. Keep this gate in CI so future dependency drift is visible.

Evidence: `Scripts/Tests/local-torrent-descriptor-tests.sh:1-24`, compiler errors at `Omnia/Domain/Playback/LocalTorrentPlayback.swift:612-618`.

#### 5. Establish an owned vulnerability and incident path

The repository has a strong hardening register but no evidence here that an external private report reaches named primary and backup owners or that credential/session containment has been rehearsed.

Direction: enable and test private vulnerability reporting, name two maintainers, document severity/response ownership, rehearse a synthetic report and secret/session containment, and retain sensitive evidence outside public issues. Existing roadmap item: `P0.3`.

## Architecture direction

### What to retain

- The directory ownership model is understandable and mostly followed.
- `HTTPTransporting` is a real seam with production and test adapters. It hides HTTPS, same-origin redirect, content-type, timeout, cancellation, and byte-limit behavior behind a small interface.
- `LocalMediaStoring`, SwiftData’s `LocalMediaStore`, cache/reservation policies, typed disc requests, provider credential storage, and platform playback adapters contain substantial behavior behind narrow interfaces.
- The domain policies are heavily fixture-tested and should remain independent of UI layout.

### Where depth and locality are weak

- `OmniaApp` constructs five concrete observable objects directly. Screens reach into these broad environment objects, while stores also call static clients directly. This makes the composition root simple, but makes feature behavior harder to replace and test through one interface.
- `LiveMetadataStore` is an 816-line `@MainActor` module that owns provider routing, 11-way initial fan-out, result ranking, merging, transformation, and view state. It has a large interface and concentrates both pure computation and observable mutation on the UI actor.
- The Edge Function is 954 lines and mixes request validation, provider adapters, normalization, caching, catalog operations, authorization, and response/error policy.
- `PlaybackViews.swift` (1,355 lines), `MediaDetailView.swift` (917), and `HomeView.swift` (733) mix composition, state, presentation policy, and reusable UI. Line count alone is not a reason to split them, but the mixed reasons to change are.
- `CloudLibrarySync` is an implemented actor with direct table methods, but repository-wide references show no caller. Account sign-in therefore does not produce a cloud-backed library experience.

### Target module shape

Use a single app composition root that constructs these deep modules and injects their interfaces:

1. **Identity module** — session lifecycle and exact callback transaction handling.
2. **Catalog module** — search/catalog/detail interface; internally owns provider routing, bounded scheduling, request coalescing, cache, normalization, and fallback. Production uses Supabase/AniList/add-on adapters; tests use deterministic in-memory adapters.
3. **Library module** — one interface for local watchlist/progress plus optional authenticated sync. Its implementation owns offline-first persistence, coalescing, conflict resolution, retry, and user-visible sync state. Do not expose separate local and cloud choreography to views.
4. **Playback module** — keep the platform seam, but let one coordinator own source resolution, preparation, session lifecycle, progress flushing, and observable player state. AVPlayer and libmpv remain adapters.
5. **Feature presentation modules** — each screen gets a compact state/action interface. Extract pure ranking, formatting, and policy first; keep SwiftUI views small enough that layout changes do not touch networking or persistence.

Do not add protocols for every type. A seam is justified when there are at least two meaningful adapters, normally production and deterministic test. Test each deep module through its public interface; avoid layering new wrappers over the current broad stores.

For the Edge Function, keep one composition entry point and extract pure request schemas, TMDB/TVDB adapters, metadata normalization, repository/cache operations, and operational handlers. This is a P2 refactor after security bounds and observability exist, not a prerequisite for shipping every P0 fix.

## Infrastructure direction

### CI and environments

There is no tracked `.github` workflow. The app bundle contains one Supabase project URL/publishable key, with no visible Debug/Staging/Production selection. The root `.gitignore` contains only `.worktrees/`; `supabase/.gitignore` protects Supabase dotenv variants, but the root does not provide repository-wide secret/signing/build-output protection.

Both app deployment targets are explicitly `26.5`. That makes the newest OS minor release the minimum supported version and materially limits the addressable device base. The Release configuration also uses manual signing with no general development team value; the successful iOS Release check was a locally signed Simulator build, not an iPhone/iPad archive. Decide and document an actual OS support window, lower the targets where product requirements permit, availability-gate newer presentation features, and prove device/archive signing separately.

Build a protected pipeline in this order:

1. filename and content secret sentinels, root ignore fixtures, formatting/diff checks;
2. frozen Deno check and all Edge Function tests;
3. clean local Supabase reset, migration application, database lint, and anon/two-user contract tests;
4. macOS build/test and iOS Simulator build for every supported destination policy;
5. all native shell regressions, manifest/SBOM/license verification, and dependency vulnerability review;
6. Release archive verification on a controlled signed runner, with immutable artifact hashes;
7. separate, human-approved deployment jobs that identify the exact Supabase target and never run from an ordinary code check.

Use checked-in `.xcconfig` files for non-secret environment identity and build labels. Keep publishable keys client-visible but target-specific; keep secret/service-role/provider credentials in server-side secret storage only. Add a visible in-app build/environment diagnostic for non-production builds.

Supabase’s 2026 platform changes make explicit grants and key migration time-sensitive: new public tables increasingly require explicit grants independently of RLS, and legacy `anon`/`service_role` keys are being retired by the end of 2026. The current migrations already grant intentionally, and the app uses a publishable key; plan the server-side secret-key migration and test the enforced-grants behavior before the deadlines. See the [primary-source brief](2026-08-21-primary-sources.md).

### Operations and recovery

Add structured, redacted request correlation across the app and Edge Function; define SLOs for metadata availability/latency, Auth success, sync convergence, and playback startup/failure; alert on provider saturation, publishable-endpoint abuse, cache/database failures, and authorization denials. Keep URLs, tokens, media titles, and provider bodies out of diagnostics by default.

Define backup retention, recovery point/time objectives, and an isolated restore drill. A backup policy without a recorded restore is not readiness evidence. Preserve the existing rule that deploys, secret changes, migrations, restores, and releases require explicit human authorization.

## Security direction

### Strengths observed

- Client configuration exposes a publishable Supabase key rather than a server secret.
- User-managed provider credentials and secret-bearing add-on/resolver values are stored in Keychain-backed paths.
- The shared HTTP transport enforces HTTPS, exact normalized origin redirects, bounded timeouts, accepted content types, cancellation, and streaming byte caps.
- Media cache, torrent descriptors, archive imports, disc materialization, and playback handoff have extensive hostile-input tests.
- SQL enables RLS and uses user ownership checks for library/progress while revoking direct client access to server-managed metadata tables.

### Remaining risks

1. Fix OAuth callback scope and transaction/replay handling as the first code security change.
2. The metadata Edge Function accepts publishable-key traffic for discovery/search/details. Add gateway/WAF rate limits, per-client/global concurrency budgets, cost controls, metrics, and abuse alerts before treating it as a public production endpoint.
3. Its six upstream provider `fetch` calls have no visible abort deadline or response-byte/decompression bound. Add shared bounded fetch behavior, response schema/collection/nesting limits, and cancellation propagation. Avoid returning or logging upstream bodies.
4. Move seed/reindex/status authorization from a long-lived token in JSON to a short-lived admin authorization header or a secret-auth function surface. Rotate the current operational secret when that change is deployed.
5. Add and validate `PrivacyInfo.xcprivacy`, reconcile it with SDK manifests and App Store Connect disclosures, and document retention/deletion for account, library, playback, diagnostics, and peer-to-peer data.
6. Verify Keychain access groups/accessibility and backup/sync semantics on every platform. Consider stronger passcode-bound accessibility only where it matches recovery expectations.
7. Add dependency scanning and independent native provenance review. The existing manifest is honest about unresolved supply-chain evidence; keep it fail-closed.

## Visual, interaction, and accessibility direction

### Current evidence

The UI is not merely placeholder SwiftUI. It uses current adaptive TabView/sidebar behavior, native navigation stacks, Mac commands, pointer/press states, custom playback controls, cinematic shelves/heroes, partial-failure source presentation, and 83 explicit accessibility modifiers across 18 source files. The design documentation has screen-by-screen state contracts.

However, there are only five previews, no UI test/snapshot/accessibility test files, no committed string catalog, and no recorded device/assistive-technology matrix. Source inspection cannot establish that hierarchy, contrast, focus, clipping, safe areas, resizing, or motion are actually good.

### Product and information architecture

Validate the top-level six-destination structure with users before polishing it. A likely simpler mobile model is Home, Search/Explore, and Library as primary destinations; Anime can be a curated content mode within discovery, and Settings can move behind an account/profile destination. Keep richer sidebar destinations on iPad/Mac where space and discoverability support them. Treat this as a research hypothesis, not a redesign mandate.

Keep the cinematic identity in content surfaces, but use platform-native density and behavior:

- iPhone: one dominant action, edge-safe portrait/landscape layout, reachable controls, no information conveyed only by artwork or color.
- iPad: real split-view/multitasking behavior, keyboard shortcuts, focus restoration, pointer states, and layouts that do more than stretch the phone.
- Mac: resizable windows, toolbar/sidebar conventions, menus, hover, full keyboard access, multiple-window decisions, and full-screen playback.

### Concrete quality gates

For every screen, create deterministic states for loading, empty, partial success, offline/error, retry/recovery, disabled, destructive confirmation, long/localized content, and missing artwork. Add a committed string catalog and test pseudo-localized/RTL layouts.

Run and record VoiceOver, Dynamic Type, Full Keyboard Access, focus order/restoration, Increase Contrast, Differentiate Without Color, Reduce Motion, Reduce Transparency, light/dark appearance, iPhone orientation/safe areas, iPad Split View/Stage Manager/pointer/keyboard, and Mac resize/menu/hover/full-screen checks. Add a small XCUITest suite for critical journeys and accessibility identifiers; use image snapshots only for stable visual primitives, not as the sole accessibility proof.

The relevant current Apple HIG and SwiftUI accessibility sources are collected in the [primary-source brief](2026-08-21-primary-sources.md).

## Performance direction

No performance API usage was found: no `OSSignposter`, signpost metrics, XCTest performance measurements, or committed benchmark baselines. Therefore the audit makes no claim that the app is fast, smooth, memory-efficient, or energy-efficient.

The first hypotheses to measure are:

- initial catalog launch performs 11 built-in metadata requests plus anime work before considering artwork requests;
- metadata ranking/merging and add-on decoding may execute on the main actor because the project defaults actor isolation to `MainActor` and `LiveMetadataStore` is explicitly main-actor isolated;
- catalog/add-on fan-out can create bursts without a shared global scheduler;
- repeated `AsyncImage` use lacks an app-owned request/decode/deduplication/target-size cache contract;
- progress observation/persistence and playback UI updates may create avoidable wakeups or writes;
- large observable stores can invalidate broader SwiftUI subtrees than necessary.

Instrument before changing implementation. Add signposted intervals for launch-to-first-content, catalog fetch/normalize/publish, search, detail, artwork decode, source resolution, playback preparation/start, buffering/recovery, progress flush, and sync convergence. Capture repeated Release traces on the same physical iPhone, iPad, and Mac with fixed fixtures and documented network/cache/power/thermal conditions. Use Time Profiler, SwiftUI, Network, Allocations/Leaks, Energy Log, Hangs/Hitches, and XCTest metrics; add MetricKit/Organizer monitoring for shipping builds.

Then build two shared pipelines:

1. a bounded request scheduler with priority, cancellation, in-flight coalescing, concurrency budgets, cache partitioning, and partial-success semantics;
2. an artwork pipeline with memory/disk budgets, target-size decoding off the main actor, in-flight deduplication, cancellation, and memory-pressure eviction.

Only adopt an optimization when repeated before/after Release evidence on the same hardware improves the active budget without unacceptable memory, energy, quality, or complexity tradeoffs.

## Recommended execution sequence

### Phase 0 — restore trustworthy gates

- Fix the standalone torrent regression script.
- Make warnings actionable and adopt a staged Swift 6 migration gate.
- Add protected CI reproducing the current local checks.
- Add root secret/build/signing ignore coverage and synthetic secret-sentinel tests.

Exit: clean checkout reproduces all non-release checks, including local Supabase tests, with no broken gate and an owned warning budget.

### Phase 1 — close release/security blockers

- Exact transaction-bound OAuth callback handling.
- Hosted Auth/grant/RLS/Realtime evidence.
- Native dependency provenance, deterministic artifacts, sandboxed packaging, privacy manifest, archive/sign/notarize verification.
- Private vulnerability reporting and incident ownership.

Exit: roadmap `P0.1`–`P0.3` have dated evidence; `P0.4` remains separately authorized and is not implied.

### Phase 2 — make the core product coherent

- Decide whether account/sync ships now; either wire an offline-first library module with conflict policy and visible sync state, or remove/label nonfunctional cloud promises from the release scope.
- Bound Edge Function and client request pipelines.
- Establish environment separation, diagnostics, observability, SLOs, and recovery drills.
- Reduce navigation and complete screen states based on user research.

Exit: sign-in has a truthful product outcome, external failures remain isolated, and operators can diagnose/recover without sensitive data.

### Phase 3 — prove experience quality

- Activate the physical-device accessibility and platform matrix.
- Add critical XCUITest journeys and localization coverage.
- Capture performance baselines, add signposts/metrics, then implement only measured pipeline/renderer changes.

Exit: every supported iPhone/iPad/Mac flow has recorded functional, accessibility, performance, and recovery evidence.

### Phase 4 — expand only after foundations

- Split the metadata monolith at proven seams.
- Evaluate tvOS as a separate product/target.
- Add providers, resolvers, or new playback modes only through the established security, observability, and performance contracts.

## Release decision

Current decision: **do not distribute as production-ready**.

Reason: Debug compilation and macOS tests are healthy, but release provenance, exact OAuth handling, hosted authorization evidence, cloud product coherence, CI/environments, privacy packaging, performance baselines, and device-level UX/accessibility verification are not closed. The repository’s existing `FUTURE-UPDATES.md` ordering is broadly sound; the immediate practical addition is to restore the broken smoke gate and convert the documented roadmap into protected automated evidence.
