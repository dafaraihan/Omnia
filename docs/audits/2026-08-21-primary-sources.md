# Omnia Product-Readiness Audit Primary Sources

> **Automated-validation policy:** Follow the repository-root `AGENTS.md`. Instructions below that call for automated test targets, suites, fixtures, or scripts are historical and superseded; use builds, static checks, and focused manual evidence instead.

Date: 2026-08-21

Repository note: the repo currently keeps planning and design notes under `docs/superpowers/`; there was no existing audit-notes convention, so this brief lives in `docs/audits/`.

## Apple UI, Accessibility, and Adaptive SwiftUI

- [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines?lang=en): the top-level Apple design source for cross-platform product review. Current guidance emphasizes hierarchy, harmony, consistency, and platform-specific adaptation across iPhone, iPad, and Mac.
- [Layout](https://developer.apple.com/design/human-interface-guidelines/layout?changes=la): use for responsive-layout checks. Apple explicitly calls out adapting to screen sizes, orientation, resizable windows, Dynamic Type, right-to-left layout, and safe areas, and recommends SwiftUI or Auto Layout for dynamic adaptation.
- [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility): use for audit criteria around perceivability, adaptability, control size, spacing, keyboard/switch/focus support, and color-independent communication. The page includes current minimum control-size guidance for iOS/iPadOS and macOS.
- [Accessibility fundamentals](https://developer.apple.com/documentation/swiftui/accessibility-fundamentals?changes=_3_1___9_8%2C_3_1___9_8): use for SwiftUI-specific accessibility checks. Apple states standard SwiftUI controls expose baseline accessibility automatically, but custom content still needs explicit labels, values, and navigation improvements.
- [Interface fundamentals](https://developer.apple.com/documentation/technologyoverviews/interface-fundamentals): use for platform-readiness review across automatic layout, internationalization, accessibility, focus navigation, and standard interaction behaviors.
- [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/): use for Mac-specific audit points. Apple highlights resizable windows, menu-bar commands, keyboard-first workflows, pointer precision, and full-screen support.

## Apple Security and Privacy

- [Preventing Insecure Network Connections](https://developer.apple.com/documentation/security/preventing-insecure-network-connections?changes=l_5): primary ATS source. Apple says ATS is on by default for apps linked against modern SDKs and requires TLS with modern certificates/ciphers; exceptions should only exist when a server cannot be made secure.
- [Keychain services](https://developer.apple.com/documentation/security/keychain-services?changes=_1): primary source for storing user secrets. Apple positions the keychain as the secure place for passwords, keys, certificates, and other small secrets.
- [Restricting keychain item accessibility](https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility?changes=_9): use for audit checks on `kSecAttrAccessible`, device-lock behavior, and stronger passcode-bound protections where appropriate.
- [Protecting the User’s Privacy](https://developer.apple.com/documentation/uikit/protecting-the-user-s-privacy?changes=l__4_8%2Cl__4_8%2Cl__4_8): use for privacy review of consent, transparent disclosure, data minimization, and deletion/control surfaces for collected data.
- [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files?changes=_8): current source for `PrivacyInfo.xcprivacy`, required-reason APIs, and bundled data-collection declarations.
- [Adding a privacy manifest to your app or third-party SDK](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk?changes=_8): use for packaging checks. Apple notes App Store Connect rejects invalid privacy manifests, and documents where the file must live for iOS/iPadOS versus macOS bundles.
- [App privacy details on the App Store](https://developer.apple.com/app-store/app-privacy-details/): use when reconciling in-bundle manifests with App Store Connect privacy disclosures.

## Apple Performance, Signposts, Instruments, and XCTest Metrics

- [Performance and metrics](https://developer.apple.com/documentation/xcode/performance-and-metrics): Apple’s central performance index for Instruments, Organizer metrics, responsiveness, memory, launch time, power, disk, and network analysis.
- [Improving your app’s performance](https://developer.apple.com/documentation/Xcode/improving-your-app-s-performance?changes=l_1): use as the top-level audit method. Apple frames performance as a measure-fix-remeasure loop and recommends preserving regressions with performance tests.
- [Profiling apps using Instruments](https://developer.apple.com/tutorials/instruments): current first-party walkthrough for hang analysis and practical Instruments usage.
- [Writing and running performance tests](https://developer.apple.com/documentation/xcode/writing-and-running-performance-tests): use for XCTest baselines, max standard deviation thresholds, and profiling failing performance tests directly in Instruments.
- [Performance Tests](https://developer.apple.com/documentation/xctest/performance-tests?changes=_1_3): primary reference for available XCTest metrics, including launch, CPU, memory, hitch, storage, and signpost-backed metrics.
- [OSSignposter](https://developer.apple.com/documentation/os/ossignposter?language=objc_): primary source for instrumenting named intervals and points of interest in code for timeline analysis in Instruments.
- [XCTOSSignpostMetric](https://developer.apple.com/documentation/xctest/xctossignpostmetric): use when tying XCTest performance tests to signposted regions.
- [MetricKit](https://developer.apple.com/documentation/metrickit): use for shipping-app telemetry from real devices, including daily metric reports and diagnostic reports.
- [MetricKit updates](https://developer.apple.com/documentation/updates/metrickit): relevant current change note. In June 2026 Apple introduced `MetricManager` async-sequence delivery that replaces `MXMetricManager` for new APIs.

## Supabase Security, Auth, RLS, Edge Functions, and Secrets

- [Auth](https://supabase.com/docs/guides/auth): top-level source for how Supabase Auth issues JWTs and integrates with RLS-backed authorization.
- [Users](https://supabase.com/docs/guides/auth/users): use for understanding permanent versus anonymous users and token-backed access semantics.
- [User Management](https://supabase.com/docs/guides/auth/managing-user-data): use for profile-table patterns. Supabase explicitly recommends app-owned `public` tables that reference `auth.users`, with RLS enabled and `on delete cascade` on the foreign key.
- [Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security): core authorization source. Supabase says RLS must always be enabled on tables in exposed schemas, and distinguishes grants from policies. The doc also warns against using mutable `raw_user_meta_data` for authorization decisions; prefer immutable `raw_app_meta_data`.
- [Securing your data](https://supabase.com/docs/guides/database/secure-data): use for deciding whether Omnia should access Postgres via Data API with RLS, via Edge Functions, or via trusted server-side direct connections.
- [Understanding API keys](https://supabase.com/docs/guides/getting-started/api-keys): current source for key classes. Publishable keys are safe for client apps; secret keys bypass RLS and must stay in trusted server-side environments only.
- [Migrating to publishable and secret API keys](https://supabase.com/docs/guides/getting-started/migrating-to-new-api-keys): relevant migration source because Supabase is deprecating legacy `anon` and `service_role` keys by the end of 2026.
- [Edge Functions](https://supabase.com/docs/guides/functions): top-level execution model for server-side Deno functions, including edge gateway behavior, short-lived/idempotent design, pooled database access, and secret handling.
- [Securing Edge Functions](https://supabase.com/docs/guides/functions/auth): primary auth-pattern source for functions. It documents `auth: 'user'`, `auth: 'secret'`, `auth: 'publishable'`, and `auth: 'none'`, and when `ctx.supabase` versus `ctx.supabaseAdmin` is appropriate.
- [Authorization headers](https://supabase.com/docs/guides/functions/auth-headers): use for 401/root-cause review. Supabase explicitly distinguishes `Authorization: Bearer <user-jwt>` from `apikey: sb_publishable_...` or `sb_secret_...`, and notes that `verify_jwt` only validates user JWTs, not API keys.
- [Environment Variables](https://supabase.com/docs/guides/functions/secrets): primary source for Edge Function secret management, default injected variables, and the new `SUPABASE_PUBLISHABLE_KEYS` / `SUPABASE_SECRET_KEYS` environment model.

## Recent Supabase Breaking Changes Relevant to an Audit

- [Breaking Change: Removing access to OpenAPI spec via the anon key](https://supabase.com/changelog/42949-breaking-change-removing-access-to-openapi-spec-via-the-anon-key): rollout completed on 2026-04-08 for existing projects. Any tooling that still expects anon-key access to the Data API OpenAPI spec must move server-side and use a service-role or secret key.
- [Breaking Change: Tables not exposed to Data and GraphQL API automatically](https://supabase.com/changelog/45329-breaking-change-tables-not-exposed-to-data-and-graphql-api-automatically): published 2026-04-28. New tables in `public` increasingly require explicit `GRANT` statements to be reachable through Data API / GraphQL. This is separate from RLS and becomes enforced for existing projects on 2026-10-30.
- [Breaking Change: OAuth token endpoint will return HTTP 200 instead of 201](https://supabase.com/changelog?types=breaking-change): effective 2026-06-01. Any integration checking specifically for HTTP `201` must be relaxed to generic `2xx`.
- [Migrating to publishable and secret API keys](https://supabase.com/docs/guides/getting-started/migrating-to-new-api-keys): not a one-day breaking change, but it is a 2026 migration item with product-readiness impact because client apps should standardize on publishable keys and server-side components should migrate off legacy `service_role` usage.

## Suggested Audit Use

Use the Apple sources above as the authoritative checklist for:

- adaptive layout across iPhone portrait/landscape, iPad multitasking, and macOS window resizing;
- accessibility states, labeling, keyboard/focus order, Dynamic Type, and control sizing;
- ATS exceptions, Keychain storage semantics, privacy manifests, and App Store privacy disclosures; and
- measurable performance coverage through Instruments, signposts, XCTest metrics, and MetricKit.

Use the Supabase sources above as the authoritative checklist for:

- key placement (`publishable` in app, `secret` only server-side);
- RLS enablement and explicit grants on exposed tables;
- Auth-to-RLS data modeling using `auth.users` references;
- Edge Function auth mode, JWT verification, and secret loading; and
- migration risk from 2026 platform hardening changes.
