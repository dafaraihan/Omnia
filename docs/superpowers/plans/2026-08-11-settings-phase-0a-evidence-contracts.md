# Settings Phase 0A Evidence and Contracts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish reproducible baseline evidence, typed Settings/provider contracts, Release-enforced feature gates, deterministic test support, hardened network policy, scoped credentials, and privacy-safe diagnostics without changing current product UI.

**Architecture:** Add focused domain values and protocols under `Domain/`, security and transport implementations under `Core/`, and deterministic fakes under `OmniaTests/TestSupport/`. Phase 0A defines event contracts; Phase 0B implements their SwiftData persistence and replay.

**Tech Stack:** Swift 6, Foundation, Security, Network, CryptoKit, OSLog, XCTest, Xcode 26.6; no new dependency.

**Design:** `docs/superpowers/specs/2026-08-11-settings-phase-0a-evidence-contracts-design.md`

## Global Constraints

- Preserve the dirty worktree and existing staged assets. Stage and commit only paths named by the active task.
- Support iPhone, iPad, and Mac at deployment target 26.5. Do not add tvOS.
- Do not alter current Settings UI or migrate existing `OmniaStore` data.
- Keep AniList and PublicMetaDB disabled in Release; runtime state cannot override that result.
- Keep Trakt, OpenRouter, and Supabase cloud sync unavailable until their documented gates pass.
- Automated tests use deterministic fixtures and never call live providers.
- Require HTTPS, bounded inputs, cancellation, exact-origin credential handling, and redacted diagnostics.
- Reject private-network add-on access by default; permit only exact-host, per-add-on grants.
- Keep credentials profile/provider-scoped in the device-only Keychain.
- Do not mutate hosted Supabase, provider configuration, secrets, migrations, functions, or releases.
- Start every production behavior with a focused failing test.
- Do not claim performance improvements without before/after Release Instruments evidence.
- Test helpers named `fixtureA`, `fixtureB`, `id1`, `id2`, or `fixture` use fixed values declared in the same test file: profile UUIDs ending in `00a1`/`00b2`, command UUIDs ending in `0101`/`0102`, `Date(timeIntervalSince1970: 1_700_000_000)`, and media key `tmdb:movie:550`. They must never generate random fallback values.

---

### Task 1: Capture the Phase 0 Baseline

**Files:**
- Create: `docs/superpowers/evidence/2026-08-11-settings-phase-0-baseline.md`
- Read: `Omnia.xcodeproj/project.pbxproj`
- Read: `OmniaTests/MPVPlaybackIntegrationTests.swift`
- Read: `supabase/functions/metadata/tvdb-identifiers_test.ts`

**Interfaces:**
- Consumes: The current repository snapshot and commands in `AGENTS.md`.
- Produces: A commit-addressed baseline for later Phase 0 comparison.

- [ ] **Step 1: Record repository and toolchain identity**

Run:

~~~sh
git rev-parse --abbrev-ref HEAD
git rev-parse HEAD
git status --short
git diff --stat
git diff --cached --stat
xcodebuild -version
~~~

Use `apply_patch` to record the literal output, timestamp, and exit status. State that the baseline is a dirty working snapshot and does not imply a clean tree.

- [ ] **Step 2: Record target configuration**

Run:

~~~sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -showdestinations
rg -n 'SUPPORTED_PLATFORMS|TARGETED_DEVICE_FAMILY|IPHONEOS_DEPLOYMENT_TARGET|MACOSX_DEPLOYMENT_TARGET|SWIFT_OBJC_BRIDGING_HEADER|TEST_HOST|BUNDLE_LOADER' Omnia.xcodeproj/project.pbxproj
test -f Omnia/Omnia-Bridging-Header.h
~~~

Record only conclusions supported by the output: configured platforms, deployment targets, test host, signing requirement, and bridging-header presence.

- [ ] **Step 3: Run the local baseline**

Run each independently and record PASS, FAIL, or BLOCKED plus the first actionable error:

~~~sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' build
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'generic/platform=iOS Simulator' build
deno check --config supabase/functions/metadata/deno.json --lock supabase/functions/metadata/deno.lock --frozen supabase/functions/metadata/index.ts
deno test --config supabase/functions/metadata/deno.json --lock supabase/functions/metadata/deno.lock --frozen supabase/functions/metadata
~~~

Do not bypass signing, install dependencies, deploy, or contact a live provider to manufacture a pass.

- [ ] **Step 4: Record current behavioral boundaries**

Use current line-number evidence to cover source selection, pending TVDB metadata deployment, macOS libmpv, absent iOS media-selection groups, oversized Settings, local `UserDefaults` persistence, uncomposed `CloudLibrarySync`, and missing provider/outbox/subtitle-translation behavior.

- [ ] **Step 5: Verify and commit**

~~~sh
rg -n 'PASS|FAIL|BLOCKED|Pending|HEAD|Xcode' docs/superpowers/evidence/2026-08-11-settings-phase-0-baseline.md
git diff --check -- docs/superpowers/evidence/2026-08-11-settings-phase-0-baseline.md
git diff -- docs/superpowers/evidence/2026-08-11-settings-phase-0-baseline.md
git add -- docs/superpowers/evidence/2026-08-11-settings-phase-0-baseline.md
git commit --only -m "Document Settings phase zero baseline" -- docs/superpowers/evidence/2026-08-11-settings-phase-0-baseline.md
~~~

### Task 2: Add Deterministic Inputs

**Files:**
- Create: `Omnia/Core/Determinism/OmniaClock.swift`
- Create: `Omnia/Core/Determinism/OmniaIDGenerator.swift`
- Create: `OmniaTests/TestSupport/ManualOmniaClock.swift`
- Create: `OmniaTests/TestSupport/FixedOmniaClock.swift`
- Create: `OmniaTests/TestSupport/SequenceIDGenerator.swift`
- Test: `OmniaTests/DeterminismTests.swift`

**Interfaces:**
- Produces: `OmniaClock.now() async -> Date`, `OmniaClock.sleep(for:)`, `OmniaIDGenerator.next() async -> UUID`, and deterministic test actors.

- [ ] **Step 1: Write failing tests**

~~~swift
import XCTest
@testable import Omnia

final class DeterminismTests: XCTestCase {
    func testManualClockAdvancesOnlyWhenRequested() async {
        let start = Date(timeIntervalSince1970: 1_000)
        let clock = ManualOmniaClock(now: start)
        XCTAssertEqual(await clock.now(), start)
        await clock.advance(by: .seconds(30))
        XCTAssertEqual(await clock.now(), start.addingTimeInterval(30))
    }

    func testSequenceIDGeneratorReturnsIDsInOrder() async {
        let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let generator = SequenceIDGenerator([first, second])
        XCTAssertEqual(await generator.next(), first)
        XCTAssertEqual(await generator.next(), second)
    }
}
~~~

- [ ] **Step 2: Run RED**

~~~sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test -only-testing:OmniaTests/DeterminismTests
~~~

Expected: compilation fails because the deterministic types do not exist.

- [ ] **Step 3: Implement the production protocols**

~~~swift
protocol OmniaClock: Sendable {
    func now() async -> Date
    func sleep(for duration: Duration) async throws
}

struct SystemOmniaClock: OmniaClock {
    func now() async -> Date { Date() }
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

protocol OmniaIDGenerator: Sendable {
    func next() async -> UUID
}

struct SystemOmniaIDGenerator: OmniaIDGenerator {
    func next() async -> UUID { UUID() }
}
~~~

Implement the two test actors. Exhausting `SequenceIDGenerator` must fail immediately rather than fall back to a random UUID.

- [ ] **Step 4: Run GREEN and commit**

~~~sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test -only-testing:OmniaTests/DeterminismTests
git diff --check -- Omnia/Core/Determinism OmniaTests/TestSupport OmniaTests/DeterminismTests.swift
git add -- Omnia/Core/Determinism OmniaTests/TestSupport/ManualOmniaClock.swift OmniaTests/TestSupport/FixedOmniaClock.swift OmniaTests/TestSupport/SequenceIDGenerator.swift OmniaTests/DeterminismTests.swift
git commit --only -m "Add deterministic domain inputs" -- Omnia/Core/Determinism OmniaTests/TestSupport/ManualOmniaClock.swift OmniaTests/TestSupport/FixedOmniaClock.swift OmniaTests/TestSupport/SequenceIDGenerator.swift OmniaTests/DeterminismTests.swift
~~~

### Task 3: Define Profiles and Ownership

**Files:**
- Create: `Omnia/Domain/Profiles/ProfileIdentity.swift`
- Create: `Omnia/Domain/Sync/AuthoritativeOwnership.swift`
- Test: `OmniaTests/ProfileOwnershipTests.swift`

**Interfaces:**
- Produces: `ProfileID`, `ProfileActivation`, `ProfileKind`, `SyncDataType`, `ProviderKind`, `ProviderAccountReference`, and `AuthoritativeOwner.supports(_:)`.

- [ ] **Step 1: Write failing tests**

~~~swift
func testActivationsForOneProfileRemainDistinct() {
    let profile = ProfileID(rawValue: UUID())
    XCTAssertNotEqual(
        ProfileActivation(profileID: profile, token: UUID()),
        ProfileActivation(profileID: profile, token: UUID())
    )
}

func testAniListCanOwnOnlyAnimeProgress() {
    let account = ProviderAccountReference(provider: .aniList, opaqueAccountID: "account-a")
    let owner = AuthoritativeOwner.remote(account)
    XCTAssertTrue(owner.supports(.animeProgress))
    XCTAssertFalse(owner.supports(.continueWatching))
    XCTAssertFalse(owner.supports(.watchlist))
}
~~~

Also assert Trakt and PublicMetaDB support only the data types approved in the specification.

- [ ] **Step 2: Run RED**

~~~sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test -only-testing:OmniaTests/ProfileOwnershipTests
~~~

- [ ] **Step 3: Implement typed ownership**

~~~swift
struct ProfileID: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: UUID
}

struct ProfileActivation: Codable, Equatable, Sendable {
    let profileID: ProfileID
    let token: UUID
}

enum SyncDataType: String, Codable, CaseIterable, Sendable {
    case continueWatching
    case watchlist
    case animeProgress
}

enum ProviderKind: String, Codable, CaseIterable, Sendable {
    case trakt
    case publicMetaDB
    case aniList
    case openRouter
}
~~~

`AuthoritativeOwner.supports(_:)` must return true for local ownership of every data type, Trakt/PublicMetaDB Continue Watching and Watchlist, and AniList anime progress only. OpenRouter owns no synchronization data.

- [ ] **Step 4: Run GREEN and commit**

~~~sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test -only-testing:OmniaTests/ProfileOwnershipTests
git diff --check -- Omnia/Domain/Profiles Omnia/Domain/Sync OmniaTests/ProfileOwnershipTests.swift
git add -- Omnia/Domain/Profiles Omnia/Domain/Sync OmniaTests/ProfileOwnershipTests.swift
git commit --only -m "Define profile and ownership contracts" -- Omnia/Domain/Profiles Omnia/Domain/Sync OmniaTests/ProfileOwnershipTests.swift
~~~

### Task 4: Define Commands, Events, and Narrow Provider Capabilities

**Files:**
- Create: `Omnia/Domain/Events/DomainEventContracts.swift`
- Create: `Omnia/Domain/Providers/ProviderCapabilities.swift`
- Test: `OmniaTests/DomainContractTests.swift`

**Interfaces:**
- Consumes: `ProfileActivation` and normalized ownership types.
- Produces: `DomainCommandPayload`, `DomainCommand`, `DomainEventPayload`, `UncommittedDomainEvent`, `EventOrigin`, and separate progress/watchlist/upcoming/anime/skip/translation provider protocols.

- [ ] **Step 1: Write failing event-envelope tests**

~~~swift
private struct ExampleEvent: DomainEventPayload {
    static let eventType = "test.example-recorded"
    static let schemaVersion = 1
    let value: Int
}

func testEventUsesCanonicalTypeAndVersion() throws {
    let event = try UncommittedDomainEvent(payload: ExampleEvent(value: 8), origin: .localUser)
    XCTAssertEqual(event.type, "test.example-recorded")
    XCTAssertEqual(event.schemaVersion, 1)
}

func testEventRejectsPayloadAbove64KiB() {
    XCTAssertThrowsError(
        try UncommittedDomainEvent(payload: LargeFixture(bytes: 65_537), origin: .localUser)
    )
}
~~~

- [ ] **Step 2: Run RED**

~~~sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test -only-testing:OmniaTests/DomainContractTests
~~~

- [ ] **Step 3: Implement canonical bounded events**

~~~swift
protocol DomainEventPayload: Codable, Sendable {
    static var eventType: String { get }
    static var schemaVersion: Int { get }
}

struct UncommittedDomainEvent: Sendable {
    static let maximumPayloadBytes = 65_536
    let type: String
    let schemaVersion: Int
    let payload: Data
    let origin: EventOrigin
}
~~~

Encode with a private `JSONEncoder` configured for sorted keys and reject an empty type, versions below 1, and payloads above the bound.

- [ ] **Step 4: Add capability compile tests**

Define separate protocols named `ProgressProvider`, `WatchlistProvider`, `UpcomingProvider`, `AnimeProgressProvider`, `SkipSegmentProvider`, and `SubtitleTranslationProvider`. Add one fake per protocol and consumer functions that accept only the narrow capability. Do not add a universal provider protocol or raw JSON/URLSession parameters.

- [ ] **Step 5: Run GREEN and commit**

~~~sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test -only-testing:OmniaTests/DomainContractTests
git diff --check -- Omnia/Domain/Events Omnia/Domain/Providers OmniaTests/DomainContractTests.swift
git add -- Omnia/Domain/Events Omnia/Domain/Providers OmniaTests/DomainContractTests.swift
git commit --only -m "Define event and provider contracts" -- Omnia/Domain/Events Omnia/Domain/Providers OmniaTests/DomainContractTests.swift
~~~

### Task 5: Enforce Feature Availability

**Files:**
- Create: `Omnia/Core/FeatureGates/OmniaFeature.swift`
- Create: `Omnia/Core/FeatureGates/FeatureGateEvaluator.swift`
- Test: `OmniaTests/FeatureGateTests.swift`

**Interfaces:**
- Produces: `OmniaFeature`, `BuildChannel`, `FeatureBlocker`, `FeatureReadiness`, `FeatureAvailability`, and `FeatureGateEvaluator.availability(of:)`.

- [ ] **Step 1: Write failing Release-gate tests**

~~~swift
func testReleaseCannotEnableLegallyBlockedProviders() {
    let evaluator = FeatureGateEvaluator(
        build: .release,
        readiness: [.publicMetaDB: .ready, .aniList: .ready]
    )
    XCTAssertEqual(evaluator.availability(of: .publicMetaDB).blocker, .releaseDisabled)
    XCTAssertEqual(evaluator.availability(of: .aniList).blocker, .releaseDisabled)
}

func testRuntimeReadinessCannotOverrideBuildPolicy() {
    let evaluator = FeatureGateEvaluator(build: .release, readiness: [.aniList: .ready])
    XCTAssertFalse(evaluator.availability(of: .aniList).isAvailable)
}
~~~

Add Trakt registration/broker, OpenRouter subtitle/consent/ZDR, and uncomposed Supabase tests.

- [ ] **Step 2: Run RED**

~~~sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test -only-testing:OmniaTests/FeatureGateTests
~~~

- [ ] **Step 3: Implement immutable build policy before runtime readiness**

~~~swift
enum OmniaFeature: String, CaseIterable, Sendable {
    case trakt
    case publicMetaDB
    case aniList
    case openRouterTranslation
    case supabaseCloudSync
}

struct FeatureAvailability: Equatable, Sendable {
    let isAvailable: Bool
    let blocker: FeatureBlocker?
}
~~~

The evaluator checks the closed Release policy first. Persisted state and injected readiness can only add blockers, never remove a Release blocker.

- [ ] **Step 4: Run GREEN and Release compile**

~~~sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test -only-testing:OmniaTests/FeatureGateTests
xcodebuild -project Omnia.xcodeproj -scheme Omnia -configuration Release -destination 'generic/platform=iOS Simulator' build
~~~

- [ ] **Step 5: Commit**

~~~sh
git diff --check -- Omnia/Core/FeatureGates OmniaTests/FeatureGateTests.swift
git add -- Omnia/Core/FeatureGates OmniaTests/FeatureGateTests.swift
git commit --only -m "Enforce provider release gates" -- Omnia/Core/FeatureGates OmniaTests/FeatureGateTests.swift
~~~

### Task 6: Add Bounded HTTP Contracts and Fixtures

**Files:**
- Create: `Omnia/Core/Networking/HTTPRequestPolicy.swift`
- Create: `Omnia/Core/Networking/HTTPTransport.swift`
- Create: `OmniaTests/TestSupport/FixtureHTTPTransport.swift`
- Create: `OmniaTests/TestSupport/XCTAsyncAssertions.swift`
- Test: `OmniaTests/HTTPTransportContractTests.swift`

**Interfaces:**
- Produces: `HTTPRequestPolicy`, `HTTPRequestPolicy.publicAddOn`, `HTTPRequestPolicy.addOn(privateHosts:)`, `BoundedHTTPRequest`, `BoundedHTTPResponse`, `HTTPTransport`, `HTTPTransportError`, `FixtureHTTPTransport`, and `XCTAssertThrowsErrorAsync`.

- [ ] **Step 1: Write failing bounds/cancellation tests**

~~~swift
func testFixtureRejectsOversizedResponse() async {
    let transport = FixtureHTTPTransport(body: Data(repeating: 1, count: 9))
    let request = BoundedHTTPRequest.get(
        URL(string: "https://example.com/manifest.json")!,
        policy: try! .init(allowedHosts: ["example.com"], maximumResponseBytes: 8)
    )
    await XCTAssertThrowsErrorAsync(try await transport.send(request)) {
        XCTAssertEqual($0 as? HTTPTransportError, .responseTooLarge(limit: 8))
    }
}
~~~

Add cancelled, timeout, unacceptable content type, invalid limit, and retry-eligibility cases.

- [ ] **Step 2: Run RED**

~~~sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test -only-testing:OmniaTests/HTTPTransportContractTests
~~~

- [ ] **Step 3: Implement the closed request policy**

`HTTPRequestPolicy` validates nonempty normalized hosts, 1...5 redirects, positive deadlines, 1 byte...16 MiB response size, accepted content types, exact credential origin, retry eligibility, and an optional exact private-host grant.

~~~swift
protocol HTTPTransport: Sendable {
    func send(_ request: BoundedHTTPRequest) async throws -> BoundedHTTPResponse
}
~~~

The fixture enforces the same size and cancellation rules as production.

- [ ] **Step 4: Run GREEN and commit**

~~~sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test -only-testing:OmniaTests/HTTPTransportContractTests
git diff --check -- Omnia/Core/Networking OmniaTests/TestSupport OmniaTests/HTTPTransportContractTests.swift
git add -- Omnia/Core/Networking/HTTPRequestPolicy.swift Omnia/Core/Networking/HTTPTransport.swift OmniaTests/TestSupport/FixtureHTTPTransport.swift OmniaTests/TestSupport/XCTAsyncAssertions.swift OmniaTests/HTTPTransportContractTests.swift
git commit --only -m "Define bounded HTTP transport" -- Omnia/Core/Networking/HTTPRequestPolicy.swift Omnia/Core/Networking/HTTPTransport.swift OmniaTests/TestSupport/FixtureHTTPTransport.swift OmniaTests/TestSupport/XCTAsyncAssertions.swift OmniaTests/HTTPTransportContractTests.swift
~~~

### Task 7: Implement Endpoint and URLSession Hardening

**Files:**
- Create: `Omnia/Core/Networking/EndpointValidator.swift`
- Create: `Omnia/Core/Networking/HostAddressResolver.swift`
- Create: `Omnia/Core/Networking/URLSessionHTTPTransport.swift`
- Test: `OmniaTests/EndpointValidatorTests.swift`
- Test: `OmniaTests/URLSessionHTTPTransportTests.swift`

**Interfaces:**
- Consumes: Task 6 HTTP contracts.
- Produces: `EndpointValidator.validate(_:resolvedAddresses:policy:)`, `HostAddressResolver`, `SystemHostAddressResolver`, and `URLSessionHTTPTransport`.

- [ ] **Step 1: Write failing endpoint tests**

Cover HTTPS, URL user-info rejection, ports, IPv4/IPv6 loopback, link-local/private/unique-local addresses, public hosts, exact private-host approval, redirect escape, and credential-origin header stripping.

~~~swift
func testPrivateAddressRequiresExactHostGrant() throws {
    let url = URL(string: "https://media.home/manifest.json")!
    XCTAssertThrowsError(
        try EndpointValidator.validate(url, resolvedAddresses: [.ipv4("192.168.1.5")], policy: .publicAddOn)
    )
    XCTAssertNoThrow(
        try EndpointValidator.validate(
            url,
            resolvedAddresses: [.ipv4("192.168.1.5")],
            policy: .addOn(privateHosts: ["media.home"])
        )
    )
}
~~~

- [ ] **Step 2: Run RED and implement endpoint validation**

~~~sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test -only-testing:OmniaTests/EndpointValidatorTests
~~~

Use `inet_pton` for literal classification and an injected `HostAddressResolver`. `SystemHostAddressResolver` uses `getaddrinfo` off the main actor. Treat resolution failure as failure. Reject a public hostname if any answer is private unless the exact normalized hostname is granted. Revalidate immediately before the request and on every redirect.

- [ ] **Step 3: Write failing URLSession fixture tests**

Use a custom `URLProtocol`; make no network request. Verify ephemeral configuration, absent cookies/credential storage/cache, streaming byte cutoff, content type, timeout mapping, cancellation, redirect count, cross-origin header removal, and final URL.

- [ ] **Step 4: Implement production transport**

~~~swift
configuration.httpCookieStorage = nil
configuration.urlCredentialStorage = nil
configuration.urlCache = nil
configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
configuration.httpShouldSetCookies = false
~~~

Use `URLSession.bytes(for:)` and stop when the bound is exceeded. A per-request delegate validates redirects and never copies sensitive headers across origins. Record the unavoidable DNS resolution race as a known limitation; do not claim URLSession pins the validated address.

- [ ] **Step 5: Run GREEN and commit**

~~~sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test -only-testing:OmniaTests/EndpointValidatorTests -only-testing:OmniaTests/URLSessionHTTPTransportTests
git diff --check -- Omnia/Core/Networking OmniaTests/EndpointValidatorTests.swift OmniaTests/URLSessionHTTPTransportTests.swift
git add -- Omnia/Core/Networking OmniaTests/EndpointValidatorTests.swift OmniaTests/URLSessionHTTPTransportTests.swift
git commit --only -m "Harden provider network transport" -- Omnia/Core/Networking OmniaTests/EndpointValidatorTests.swift OmniaTests/URLSessionHTTPTransportTests.swift
~~~

### Task 8: Scope Credentials and Validate OAuth Callbacks

**Files:**
- Modify: `Omnia/Core/Security/KeychainStore.swift`
- Create: `Omnia/Core/Security/CredentialScope.swift`
- Create: `Omnia/Core/Security/OAuthCallbackValidator.swift`
- Test: `OmniaTests/CredentialScopeTests.swift`
- Test: `OmniaTests/OAuthCallbackValidatorTests.swift`

**Interfaces:**
- Consumes: `ProfileID`, `ProviderKind`, `OmniaClock`, and existing Keychain operations.
- Produces: `CredentialScope.keychainAccount`, `OAuthCallbackContract`, `OAuthTransaction`, and `OAuthCallbackValidator.validate`.

- [ ] **Step 1: Write failing isolation and callback tests**

~~~swift
func testCredentialAccountsDifferAcrossProfiles() {
    let first = CredentialScope(profileID: .fixtureA, provider: .trakt, kind: .accessToken)
    let second = CredentialScope(profileID: .fixtureB, provider: .trakt, kind: .accessToken)
    XCTAssertNotEqual(first.keychainAccount, second.keychainAccount)
}

func testCallbackRequiresExactURLAndConsumesStateOnce() async throws {
    let validator = OAuthCallbackValidator(
        contract: .init(scheme: "omnia", host: "oauth", path: "/openrouter"),
        clock: FixedOmniaClock(.fixture)
    )
    let transaction = OAuthTransaction.fixture(state: "state-a")
    let callback = URL(string: "omnia://oauth/openrouter?code=c&state=state-a")!
    _ = try await validator.validate(callback, transaction: transaction)
    await XCTAssertThrowsErrorAsync(try await validator.validate(callback, transaction: transaction))
}
~~~

Also test wrong/mixed-case components, duplicate/missing query items, state mismatch, expiration, wrong profile, and replay without logging the callback.

- [ ] **Step 2: Run RED**

~~~sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test -only-testing:OmniaTests/CredentialScopeTests -only-testing:OmniaTests/OAuthCallbackValidatorTests
~~~

- [ ] **Step 3: Implement scoped Keychain names and validation**

Keychain account names contain fixed labels, lowercase profile UUID, provider, and credential kind only. Preserve `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` on iPhone/iPad and non-synchronizing macOS login-Keychain behavior. Store only a SHA-256 state digest, allow one active transaction, enforce a ten-minute age, require exact URL components and exactly one `code`/`state`, then mark consumed before returning the code.

- [ ] **Step 4: Run GREEN and commit**

~~~sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test -only-testing:OmniaTests/CredentialScopeTests -only-testing:OmniaTests/OAuthCallbackValidatorTests
git diff --check -- Omnia/Core/Security OmniaTests/CredentialScopeTests.swift OmniaTests/OAuthCallbackValidatorTests.swift
git add -- Omnia/Core/Security OmniaTests/CredentialScopeTests.swift OmniaTests/OAuthCallbackValidatorTests.swift
git commit --only -m "Scope credentials and OAuth callbacks" -- Omnia/Core/Security OmniaTests/CredentialScopeTests.swift OmniaTests/OAuthCallbackValidatorTests.swift
~~~

### Task 9: Add Privacy-Safe Diagnostics

**Files:**
- Create: `Omnia/Core/Diagnostics/IntegrationDiagnostic.swift`
- Create: `Omnia/Core/Diagnostics/IntegrationDiagnosticSink.swift`
- Test: `OmniaTests/IntegrationDiagnosticTests.swift`

**Interfaces:**
- Produces: a closed `IntegrationDiagnostic` schema, `OSLogIntegrationDiagnosticSink`, and `RecordingDiagnosticSink`.

- [ ] **Step 1: Write a failing allow-list test**

~~~swift
func testEncodedDiagnosticContainsOnlyApprovedFields() throws {
    let data = try JSONEncoder().encode(IntegrationDiagnostic.fixture)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(
        Set(object.keys),
        ["integration", "operation", "outcome", "duration", "correlationID"]
    )
}
~~~

Add explicit equality coverage for each enum field and prove encoding never emits URL, query, body, token, prompt, subtitle-text, response, or model-output keys.

- [ ] **Step 2: Run RED and implement**

~~~sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test -only-testing:OmniaTests/IntegrationDiagnosticTests
~~~

Use closed enums, duration buckets, and no arbitrary metadata dictionary. `Logger` renders enum values publicly and correlation IDs privately.

- [ ] **Step 3: Run GREEN and commit**

~~~sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test -only-testing:OmniaTests/IntegrationDiagnosticTests
git diff --check -- Omnia/Core/Diagnostics OmniaTests/IntegrationDiagnosticTests.swift
git add -- Omnia/Core/Diagnostics OmniaTests/IntegrationDiagnosticTests.swift
git commit --only -m "Add privacy-safe diagnostics" -- Omnia/Core/Diagnostics OmniaTests/IntegrationDiagnosticTests.swift
~~~

### Task 10: Verify Phase 0A

**Files:**
- Modify: `docs/superpowers/evidence/2026-08-11-settings-phase-0-baseline.md`
- Modify only for verified policy changes: `SECURITY.md`

**Interfaces:**
- Consumes: Tasks 1–9.
- Produces: A reviewed Phase 0A handoff and pending-verification list.

- [ ] **Step 1: Run all focused tests**

~~~sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test -only-testing:OmniaTests/DeterminismTests -only-testing:OmniaTests/ProfileOwnershipTests -only-testing:OmniaTests/DomainContractTests -only-testing:OmniaTests/FeatureGateTests -only-testing:OmniaTests/HTTPTransportContractTests -only-testing:OmniaTests/EndpointValidatorTests -only-testing:OmniaTests/URLSessionHTTPTransportTests -only-testing:OmniaTests/CredentialScopeTests -only-testing:OmniaTests/OAuthCallbackValidatorTests -only-testing:OmniaTests/IntegrationDiagnosticTests
~~~

Expected: all listed tests pass without live network access.

- [ ] **Step 2: Run supported builds and frozen backend tests**

~~~sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' build
xcodebuild -project Omnia.xcodeproj -scheme Omnia -configuration Release -destination 'generic/platform=iOS Simulator' build
deno check --config supabase/functions/metadata/deno.json --lock supabase/functions/metadata/deno.lock --frozen supabase/functions/metadata/index.ts
deno test --config supabase/functions/metadata/deno.json --lock supabase/functions/metadata/deno.lock --frozen supabase/functions/metadata
git diff --quiet -- supabase/functions/metadata/deno.lock
~~~

- [ ] **Step 3: Review scope, whitespace, and secrets**

~~~sh
git status --short
git diff --check
git diff -- Omnia/Core Omnia/Domain OmniaTests docs/superpowers/evidence SECURITY.md
git grep -nE '(sk_live_[A-Za-z0-9]+|ghp_[A-Za-z0-9]+|Bearer[[:space:]]+[A-Za-z0-9._-]+)' -- Omnia OmniaTests docs
~~~

Expected: no credential-value match and no unrelated Phase 0A edit.

- [ ] **Step 4: Record pending gates and commit evidence**

Keep physical iPhone/iPad, iPad multitasking, accessibility UI, Release Instruments, archive/notarization, hosted Supabase, live-provider, legal, and production-credential checks pending.

~~~sh
git add -- docs/superpowers/evidence/2026-08-11-settings-phase-0-baseline.md
git commit --only -m "Verify Settings phase zero contracts" -- docs/superpowers/evidence/2026-08-11-settings-phase-0-baseline.md
~~~

If `SECURITY.md` changed for the verified DNS limitation, add it explicitly to both commands. Never stage unrelated documentation.
