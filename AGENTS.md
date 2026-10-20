# Repository Guidelines

## Structure and Ownership

`Omnia/` contains the SwiftUI app. Keep composition in `App/`, models and protocols in `Domain/`, service implementations in `Data/`, platform integrations in `Platform/`, reusable controls in `UI/`, account and security utilities in `Core/`, and screens in `Features/<FeatureName>/`. Assets belong in `Assets.xcassets`. `Omnia.xcodeproj` defines the iPhone, iPad, and Mac app target, Swift packages, signing, and libmpv embedding; tvOS is not a supported target.

`supabase/` is the cloud boundary. Add forward-only SQL migrations under `supabase/migrations/`; keep the metadata Edge Function, import map, lock, and helpers together in `supabase/functions/metadata/`. Read the [Supabase guide](supabase/README.md) before changing data access, Auth, credentials, or deployment inputs.

## Evidence-First Workflow

Inspect `git status`, the relevant source, configuration, and current diff before editing. Reproduce a reported defect with recorded steps before changing behavior, then preserve those steps as the regression check. Mark current behavior only when repository or runtime evidence supports it; identify anything requiring device, hosted-environment, or production verification.

Make the smallest coherent change that satisfies the demonstrated need. Do not refactor unrelated code, introduce speculative abstractions, invent provider or platform APIs, or ship placeholder UI. A new dependency requires documented functional value, license and provenance review, version/lock review, supply-chain risk assessment, and an explanation of why existing platform or repository capabilities are insufficient.

## Build and Local Commands

Run commands from the repository root. macOS requires Homebrew libmpv. Use a valid development identity and do not bypass signing.

Keep exactly one current Omnia build. Use Xcode's canonical DerivedData location for this project; do not pass a custom `-derivedDataPath`, create duplicate `Omnia.app` products, or leave temporary/obsolete Omnia builds behind. Reuse the canonical build for manual checks, and verify only one current `Omnia.app` remains before handoff.

```sh
open Omnia.xcodeproj
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' build
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'generic/platform=iOS Simulator' build
deno check --config supabase/functions/metadata/deno.json --lock supabase/functions/metadata/deno.lock --frozen supabase/functions/metadata/index.ts
supabase start
supabase db lint --local
supabase functions serve metadata --env-file supabase/.env
```

This repository intentionally has no automated test targets, suites, fixtures, or test scripts. Do not create, restore, or run them. Validate changes with affected-destination builds, static checks, focused manual flow checks on relevant iPhone, iPad, and Mac form factors, and the release evidence described in [INFRASTRUCTURE.md](INFRASTRUCTURE.md).

## Implementation and Quality Gates

Use four-space indentation in Swift and two spaces in TypeScript. Follow Xcode naming: `UpperCamelCase` types, `lowerCamelCase` members, and descriptive `View`, `Store`, `Client`, and `Provider` suffixes. Prefer small SwiftUI views, explicit ownership, and structured concurrency. Match neighboring `MARK` and extension organization.

Security-sensitive changes must identify the affected trust boundary before implementation. Treat callbacks, add-on/provider payloads, resolver results, media, redirects, and credentials as untrusted. Require HTTPS, exact normalized allow-lists, bounded inputs, timeouts and cancellation, redacted diagnostics, Keychain ownership of user secrets, server-only shared secrets, and reviewed RLS/grants as applicable. Apply the gates in [SECURITY.md](SECURITY.md); never commit tokens, `service_role` keys, `supabase/.env`, signing material, or secret-bearing logs.

Performance work starts with a hypothesis and a reproducible baseline. Do not claim faster, smoother, lower-memory, or lower-energy behavior from code inspection or a single Debug/Simulator run. Attach before-and-after Release evidence from the same supported hardware and scenario using Instruments, including variance and tradeoffs. Follow [PERFORMANCE.md](PERFORMANCE.md).

UI changes must use the current official Apple Design Resources and Human Interface Guidelines for the affected platform, plus the contracts in [DESIGN.md](DESIGN.md). Every changed flow must define loading, empty, partial-success, offline/error, retry/recovery, disabled, and destructive states where applicable. Manually verify VoiceOver, Dynamic Type, focus order, Full Keyboard Access, Reduce Motion, Reduce Transparency, Increase Contrast, light/dark appearance, and color-independent status. Check iPhone orientation and safe areas; iPad multitasking, pointer, and keyboard; and Mac resizing, menus, hover, keyboard, window, and full-screen behavior.

## Scope, Review, and Live Operations

Keep diffs scoped and preserve user work. Recheck `git status`, review only intended paths, run relevant builds and static checks, and use `git diff --check` before handoff. Do not stage, commit, or rewrite unrelated changes. Commit subjects are concise, imperative, and focused. Pull requests state user-visible impact, evidence and commands run, risks, migrations/secrets/entitlement changes, linked findings, and screenshots or recordings for UI work.

Local checks and code changes never authorize hosted mutations. `supabase db push`, secret changes, live configuration changes, release promotion, restore operations, and deploys require explicit human authorization, verified target, reviewed source, rollback evidence, and the relevant [infrastructure runbook](INFRASTRUCTURE.md). `supabase functions deploy metadata` remains a pending manual operation and is never implied by a code or documentation change.

Start with [README.md](README.md); consult [FUTURE-UPDATES.md](FUTURE-UPDATES.md) for priorities and objective exit criteria. Specialist documents own their detailed policies; link them rather than duplicating their registers or runbooks.
