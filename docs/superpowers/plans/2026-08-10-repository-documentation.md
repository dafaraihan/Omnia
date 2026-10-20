# Repository Documentation Implementation Plan

> **Automated-validation policy:** Follow the repository-root `AGENTS.md`. Instructions below that call for automated test targets, suites, fixtures, or scripts are historical and superseded; use builds, static checks, and focused manual evidence instead.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create an evidence-based documentation system for building, designing, securing, operating, measuring, and extending Omnia.

**Architecture:** Keep one authoritative concern per root document and cross-link instead of duplicating guidance. `README.md` is the entry point, `DESIGN.md` owns product/UI behavior, specialist documents own security, performance, infrastructure, and roadmap detail, and `AGENTS.md` turns those standards into contributor gates.

**Tech Stack:** Markdown, Swift/SwiftUI, Objective-C/libmpv, Xcode, Deno TypeScript, Supabase/Postgres, official Apple Design Resources and Human Interface Guidelines.

## Global Constraints

- Describe repository evidence as current state; label unverified production configuration and intended work explicitly.
- Use direct, professional language. Exclude generic slogans, filler, invented status, and unmeasured performance claims.
- Use Apple Design Resources and the Human Interface Guidelines as primary references for flows, screens, UI elements, accessibility, and platform adaptation.
- Treat Apple TV as a cinematic reference, not a pixel-for-pixel template or substitute for iPhone, iPad, and Mac conventions.
- Add no application code, dependencies, secrets, credentials, generated artifacts, or private Apple assets.
- Preserve unrelated staged and unstaged work.
- Each finding states evidence, impact, priority, required action, and objective exit criteria.

---

### Task 1: Repository Entry Point

**Files:**
- Create: `README.md`
- Reference: `Omnia.xcodeproj/project.pbxproj`
- Reference: `supabase/README.md`

**Interfaces:**
- Consumes: current target configuration, source layout, and verified build/test commands.
- Produces: the canonical product introduction and documentation map used by every other guide.

- [ ] **Step 1: Write the repository overview**

Define Omnia as a native discovery, library, and HTTPS playback hub for iPhone, iPad, and Mac. State that Apple TV is a design reference and tvOS is not yet a target. Include the non-goals around hosting media, embedded torrent transport, and trusted-by-default add-ons.

- [ ] **Step 2: Add setup and verification commands**

Document Xcode/libmpv prerequisites, Supabase configuration, project opening, macOS build/test, Deno check/test, and local Supabase commands. Mark secrets and deploy operations clearly.

- [ ] **Step 3: Add current status and document map**

Link `DESIGN.md`, `SECURITY.md`, `PERFORMANCE.md`, `INFRASTRUCTURE.md`, `FUTURE-UPDATES.md`, `AGENTS.md`, and `supabase/README.md`. Describe current maturity without using a fabricated completion percentage.

- [ ] **Step 4: Validate links and commands**

Run: `rg -n '\[[^]]+\]\([^)]+\.md[^)]*\)' README.md`

Expected: every specialist document is linked once and paths are relative.

### Task 2: Security Guide and Hardening Register

**Files:**
- Create: `SECURITY.md`
- Reference: `Omnia.entitlements`
- Reference: `AppInfo.plist`
- Reference: `Omnia/Core/Security/KeychainStore.swift`
- Reference: `Omnia/Platform/Playback/AuthorizedPlaybackResolver.swift`
- Reference: `supabase/functions/metadata/index.ts`
- Reference: `supabase/migrations/*.sql`

**Interfaces:**
- Consumes: verified trust boundaries and configuration discovered during the audit.
- Produces: the authoritative security model and prioritized hardening findings linked from `AGENTS.md` and `FUTURE-UPDATES.md`.

- [ ] **Step 1: Document assets, actors, and trust boundaries**

Cover user identity, library history, credentials, add-on manifest URLs, resolver tokens, provider secrets, publishable Supabase configuration, third-party payloads, final media URLs, and embedded native libraries.

- [ ] **Step 2: Document required controls**

Specify Keychain-only secrets, HTTPS/ATS, exact callback and host validation, RLS, service-role isolation, response-size limits, timeout/cancellation behavior, redacted diagnostics, dependency provenance, signing/notarization, and least-privilege entitlements.

- [ ] **Step 3: Add the evidence-based findings table**

Include confirmed or verification-required findings for OAuth callback validation, the `allow-jit` entitlement, disabled user-script sandboxing on the app target, libmpv supply-chain reproducibility, publishable-key endpoint abuse/rate limiting, operational seed-token transport, query-string provider credentials, response-size bounds, privacy-manifest/API-use audit, root ignore coverage, production auth policy verification, dependency scanning, and incident reporting.

- [ ] **Step 4: Add security verification and reporting**

Provide pre-release checks and a private reporting process that instructs reporters not to open public issues containing credentials or exploit details.

- [ ] **Step 5: Scan for accidental secret values**

Run: `rg -n --hidden --glob '!*.lock' --glob '!*.mkv' '(service_role|BEGIN (RSA|EC|OPENSSH) PRIVATE KEY|sk_live_|ghp_)' README.md SECURITY.md PERFORMANCE.md INFRASTRUCTURE.md FUTURE-UPDATES.md AGENTS.md DESIGN.md`

Expected: only explanatory references such as `service_role`; no credential values.

### Task 3: Performance Guide and Measurement Plan

**Files:**
- Create: `PERFORMANCE.md`
- Reference: `Omnia/Data/Metadata/LiveMetadataStore.swift`
- Reference: `Omnia/UI/Components/ArtworkView.swift`
- Reference: `Omnia/Platform/Playback/PlaybackSession.swift`
- Reference: `Omnia/Platform/Playback/MPVPlayerController.m`

**Interfaces:**
- Consumes: current request fan-out, image loading, actor isolation, persistence, and playback behavior.
- Produces: measurable targets and a performance gap register linked from the roadmap.

- [ ] **Step 1: Define measurement rules and provisional budgets**

Separate unmeasured baseline from target budgets. Cover launch, visible-content latency, interaction response, animation hitches, memory, energy, network requests, image decoding, and playback startup. Require real-device Instruments traces before claiming improvement.

- [ ] **Step 2: Document subsystem guidance**

Cover request deduplication, cancellation, bounded concurrency, cache ownership, image downsampling, off-main decoding, SwiftUI identity, persistence batching, playback polling/events, and low-power/thermal behavior.

- [ ] **Step 3: Add the findings table**

Include startup request fan-out, repeated multi-page catalog loading, use of `URLSession.shared`, missing unified cache policy, broad `AsyncImage` usage, main-actor decode risk, large feature/store files, synchronous `UserDefaults` rewrites, 250 ms playback polling, deprecated OpenGL rendering, missing signposts/MetricKit, and absent performance tests/baselines.

- [ ] **Step 4: Add profiling recipes**

Provide specific workflows for Time Profiler, SwiftUI, Hitches, Allocations, Leaks, Network, Energy Log/Power Profiler, XCTest metrics, and Xcode Organizer/MetricKit.

- [ ] **Step 5: Check that claims distinguish targets from measurements**

Run: `rg -n 'baseline|target|measure|Instruments|MetricKit|XCTest' PERFORMANCE.md`

Expected: budgets are explicitly identified as targets until baselines are recorded.

### Task 4: Infrastructure and Operations Guide

**Files:**
- Create: `INFRASTRUCTURE.md`
- Reference: `AppInfo.plist`
- Reference: `Omnia.xcodeproj/project.pbxproj`
- Reference: `Omnia/Platform/Playback/embed-libmpv.sh`
- Reference: `supabase/config.toml`
- Reference: `supabase/functions/metadata/deno.json`
- Reference: `supabase/migrations/*.sql`

**Interfaces:**
- Consumes: app/backend topology, build settings, packaging, and database policy evidence.
- Produces: the operational source of truth for environments, deploys, observability, backup, and recovery.

- [ ] **Step 1: Map runtime and deployment topology**

Document SwiftUI clients, Supabase Auth/Postgres/Realtime/Edge Function, TMDB/TVDB, user-managed providers, Stremio add-ons, resolver boundary, AVPlayer, and libmpv.

- [ ] **Step 2: Define environment and configuration ownership**

Separate publishable app configuration, Edge Function secrets, local `.env`, Keychain values, Xcode settings, and database migrations. State what may and may not be committed.

- [ ] **Step 3: Document build and deploy runbooks**

Include migration lint/apply, Edge Function check/test/serve/deploy, app build/test, libmpv embedding/signing validation, staged release, rollback, and post-deploy smoke checks.

- [ ] **Step 4: Add the infrastructure findings table**

Include absent CI/CD, missing root `.gitignore`, missing configured `supabase/seed.sql`, single-environment app configuration, no documented backup/restore drill, limited structured observability, no SLOs/alerts, non-reproducible Homebrew libmpv input, function monolith, and production Supabase settings requiring verification.

- [ ] **Step 5: Validate referenced files and commands**

Run: `test -f Omnia.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved && test -f supabase/functions/metadata/deno.lock && test -f Omnia/Platform/Playback/embed-libmpv.sh`

Expected: exit 0.

### Task 5: Product and Apple UI Design Guide

**Files:**
- Modify: `DESIGN.md:1-270`

**Interfaces:**
- Consumes: current flows/components plus official Apple Design Resources and Human Interface Guidelines.
- Produces: the canonical product, flow, screen, and UI-element specification.

- [ ] **Step 1: Remove specialist duplication**

Keep a concise architecture/trust summary and link detailed security, performance, infrastructure, and roadmap material to their owner documents.

- [ ] **Step 2: Add Apple reference policy and resource index**

Link official iOS/iPadOS, macOS, and tvOS UI kits; HIG navigation, loading, focus, materials, search, playback, accessibility, layout, and motion guidance; SF Symbols; and system typography. Explain permitted reference use and platform adaptation.

- [ ] **Step 3: Specify product flows and screen contracts**

For Home, Anime, Search, Library, Discover, Detail, Source Selection, Playback, and Settings, document purpose, entry/exit, primary action, loading/empty/error states, platform behavior, and accessibility.

- [ ] **Step 4: Specify reusable UI elements**

Map current component names to semantic roles and define artwork treatment, shelves, posters, heroes, source rows, playback controls, materials, typography, spacing, focus/hover, motion, and reduced-motion behavior.

- [ ] **Step 5: Verify repository symbol accuracy**

Run: `rg -o '\x60[A-Z][A-Za-z0-9]+\x60' DESIGN.md | sort -u`

Expected: named implementation types can be located under `Omnia/`, or are clearly marked as intended concepts.

### Task 6: Prioritized Future Updates

**Files:**
- Create: `FUTURE-UPDATES.md`
- Reference: `SECURITY.md`
- Reference: `PERFORMANCE.md`
- Reference: `INFRASTRUCTURE.md`
- Reference: `DESIGN.md`

**Interfaces:**
- Consumes: open findings from all specialist documents.
- Produces: one deduplicated execution order with acceptance criteria.

- [ ] **Step 1: Define priority semantics**

Use P0 for release/security blockers, P1 for reliability and measurable product quality, and P2 for expansion after the foundations are stable.

- [ ] **Step 2: Build the roadmap**

Prioritize security hardening, reproducible builds/CI, observability, performance baselines, network/image architecture, playback modernization, test coverage, cloud sync, platform completeness, and only then optional integrations.

- [ ] **Step 3: Add dependencies and exit criteria**

Every item names its source document, affected area, prerequisite, verification method, and completion condition. Avoid dates and percentage estimates without planning evidence.

- [ ] **Step 4: Check for vague backlog language**

Run: `rg -n 'T''BD|T''ODO|someday|eventually|nice to have|maybe|could potentially' FUTURE-UPDATES.md`

Expected: no matches.

### Task 7: Contributor Enforcement Guide

**Files:**
- Modify: `AGENTS.md:1-49`

**Interfaces:**
- Consumes: commands and gates from all specialist documents.
- Produces: concise, enforceable instructions for human and agent contributors.

- [ ] **Step 1: Preserve repository-specific structure and commands**

Correct Deno commands to use `supabase/functions/metadata/deno.json`; include signed macOS tests and relevant build destinations.

- [ ] **Step 2: Add evidence-first working rules**

Require reproduction before fixes, measurement before optimization claims, small scoped changes, no speculative abstractions, no placeholder UI, no invented APIs, and no dependency additions without documented value and supply-chain review.

- [ ] **Step 3: Add security, performance, and Apple design gates**

Require threat-boundary review for external inputs/credentials, Instruments or XCTest evidence for performance work, official Apple resources for UI decisions, complete loading/empty/error states, accessibility coverage, and platform-specific interaction checks.

- [ ] **Step 4: Keep the guide concise**

Run: `wc -w AGENTS.md`

Expected: 500-800 words; detailed policy remains in linked documents.

### Task 8: Cross-Document Quality Gate

**Files:**
- Verify: `README.md`
- Verify: `SECURITY.md`
- Verify: `PERFORMANCE.md`
- Verify: `INFRASTRUCTURE.md`
- Verify: `FUTURE-UPDATES.md`
- Verify: `AGENTS.md`
- Verify: `DESIGN.md`

**Interfaces:**
- Consumes: all completed documents.
- Produces: a consistent, navigable documentation set ready for contributor use.

- [ ] **Step 1: Scan for placeholders and formatting defects**

Run: `rg -n 'T''BD|T''ODO|FIX''ME|Lorem|AI-generated|as an AI|vibe coding' README.md SECURITY.md PERFORMANCE.md INFRASTRUCTURE.md FUTURE-UPDATES.md AGENTS.md DESIGN.md; git diff --check -- README.md SECURITY.md PERFORMANCE.md INFRASTRUCTURE.md FUTURE-UPDATES.md AGENTS.md DESIGN.md`

Expected: no placeholders, meta-commentary, prohibited phrasing, or whitespace errors.

- [ ] **Step 2: Check local Markdown links**

Run a shell loop that extracts relative `.md` link targets from the seven documents and fails when a target file does not exist.

Expected: every local Markdown target exists.

- [ ] **Step 3: Verify evidence-sensitive claims**

Check every `Current`, `Confirmed`, or `Implemented` statement against the referenced code/configuration. Downgrade uncertain claims to `Needs verification`.

- [ ] **Step 4: Review duplication and ownership**

Ensure detailed security findings exist only in `SECURITY.md`, performance findings only in `PERFORMANCE.md`, infrastructure runbooks only in `INFRASTRUCTURE.md`, and roadmap status only in `FUTURE-UPDATES.md`.

- [ ] **Step 5: Report deliverables and material findings**

List created and modified files, validation results, highest-priority confirmed gaps, and areas requiring production or real-device verification.
