# MDBList Rating Providers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let Omnia users enable or disable every external rating provider returned by MDBList and show enabled ratings, plus the always-visible MDBList aggregate score, directly below title metadata with native Apple-platform behavior.

**Architecture:** Keep the user-owned API key in the existing Keychain boundary and replace the ad-hoc request with a bounded `HTTPTransporting` client plus an in-memory TTL/coalescing cache. Model known providers through a typed registry while accepting bounded future identifiers through a dynamic fallback. Persist discovered and disabled IDs in `SettingsPreferences`, feed a testable presentation/load model into native SwiftUI settings rows and a wrapping title-detail rating group, and bundle only provider artwork whose official source and permitted use are documented.

**Tech Stack:** Swift 6, SwiftUI, Observation, XCTest, Foundation `URLComponents`, Security/Keychain through `ProviderCredentialStore`, the existing `HTTPTransporting` boundary, and asset-catalog vector/transparent artwork.

## Global Constraints

- Follow the approved design in `docs/superpowers/specs/2026-08-11-mdblist-rating-providers-design.md`.
- Treat MDBList's official API documentation and current response fixtures as the contract. Do not invent a logo field, provider catalog endpoint, value scale, or undocumented authentication mechanism.
- Display the returned aggregate score without rescaling it. MDBList's July 2026 product update changed aggregate presentation to a 0–10-style value.
- Accept every valid returned provider ID, enable newly discovered IDs by default, and preserve disabled unknown IDs.
- The aggregate MDBList score is informational, always enabled, and always ordered after external provider ratings.
- Use Apple's current Design Resources and HIG: native `Form`, `Section`, `Toggle`, semantic text/colors, Dynamic Type, native focus, and system accessibility behavior.
- Never log or persist an API key or a credential-bearing request URL. Require exact HTTPS origin `api.mdblist.com`, bounded identifiers, 15-second timeout, 512 KiB response limit, same-origin redirects, and cancellation.
- Reuse `HTTPTransporting`, `HTTPRequestPolicy`, `NormalizedOrigin`, `ClockProviding`, and the current Keychain store; add no dependency and make no Supabase or hosted change.
- Show partial valid data. A malformed provider entry must not erase valid siblings or the aggregate.
- Do not fetch logos at runtime, scrape favicons, redraw trademarks, or use a third-party logo package.
- A published official brand pack is not automatically a license for every use. Ship a provider image only after its official terms permit Omnia's use; otherwise use the provider-name text fallback.
- The repository is dirty. Before every commit, run `git diff --cached --name-only` and `git diff -- <task paths>`. The six currently staged `Contents.json` asset changes belong to the user and must remain staged but must not enter feature commits.
- `Omnia/Data/Metadata/UserManagedMetadataClients.swift`, `Omnia/Features/Settings/MetadataSettingsView.swift`, and other relevant paths are pre-existing untracked user work. Edit only the necessary ranges and do not commit an entire pre-existing untracked file merely to capture a small task change.
- Use `git commit --only <explicit task paths> -m '<subject>'` when a task is safely committable. If a task path contains inseparable pre-existing user work, leave it uncommitted and record that fact instead of absorbing it.
- Use four-space indentation in Swift and methods beginning with `test` in XCTest.

## Official References and Asset Gates

- MDBList API and quota: `https://docs.mdblist.com/docs/api`
- MDBList score behavior: `https://docs.mdblist.com/docs/score`
- MDBList current rating example: `https://mdblist.com/lists/lrs/personal-mdblist`
- MDBList product/API updates: `https://mdblist.com/new-features/`
- Apple Design Resources: `https://developer.apple.com/design/resources/`
- Apple HIG Settings: `https://developer.apple.com/design/human-interface-guidelines/settings`
- Apple HIG Toggles: `https://developer.apple.com/design/human-interface-guidelines/toggles`
- Apple HIG Accessibility: `https://developer.apple.com/design/human-interface-guidelines/accessibility/`
- Apple HIG Images: `https://developer.apple.com/design/human-interface-guidelines/images`
- TMDB attribution and logo requirements: `https://developer.themoviedb.org/docs/faq`
- Trakt official logo packs: `https://media-og.trakt.tv/branding`
- Letterboxd official brand assets and restrictions: `https://letterboxd.com/about/brand/`
- IMDb official brand toolkit and approval contact: `https://brand.imdb.com/`
- Rotten Tomatoes licensing and required brand approval: `https://www.rottentomatoes.com/help_desk/licensing`

The initial asset audit must classify every known provider as either `approved bundled mark` or `text fallback`. IMDb and Rotten Tomatoes remain text fallbacks unless the repository contains evidence of the required permission. Metacritic, MyAnimeList, Roger Ebert, and MDBList remain text fallbacks unless their official terms or existing repository provenance establish permitted redistribution. TMDB, Trakt, and Letterboxd may use their official packs only after the documented usage terms are satisfied. This gate preserves the user-visible provider and value in every case; it affects only whether the decorative mark is an image or provider-name text.

---

## File Map

### Create

- `Omnia/Domain/Metadata/MDBListRatingProvider.swift` — bounded provider identity, aliases, descriptors, ordering, formatting, and asset eligibility.
- `Omnia/Data/Metadata/MDBListRatingsCache.swift` — route-keyed successful-result TTL cache and in-flight request coalescing.
- `Omnia/Features/Library/MDBListRatingsPresentation.swift` — filtered rating items and typed loading/error presentation state.
- `Omnia/UI/Components/FlowLayout.swift` — reusable wrapping layout currently private to title detail.
- `OmniaTests/MDBListRatingProviderTests.swift` — normalization, aliases, ordering, fallback labels, formatting, and aggregate behavior.
- `OmniaTests/MDBListMetadataClientTests.swift` — response decoding, route validation, transport policy, error mapping, and no-request guards.
- `OmniaTests/MDBListRatingsCacheTests.swift` — TTL, cache credential gate, bypass, and coalescing.
- `OmniaTests/MDBListRatingsPresentationTests.swift` — filtering, partial results, aggregate order, errors, retry, and stale-result rejection.
- `Omnia/Assets.xcassets/RatingProviderMarks/` — only reviewed, original-color, transparent provider assets and their `Contents.json` files.
- `docs/provider-assets/mdblist-rating-provider-marks.md` — source, retrieval date, format/conversion, usage terms, attribution, and fallback decision for every known provider.

### Modify

- `Omnia/Data/Metadata/UserManagedMetadataClients.swift` — replace only the MDBList client/model range with bounded transport-backed behavior; leave AniList work intact.
- `Omnia/Domain/Settings/SettingsPreferences.swift` — add nested discovered/disabled MDBList rating preferences with backward-compatible decoding.
- `Omnia/Data/Settings/SettingsPreferencesStore.swift` — add idempotent discovery and enable/disable operations.
- `OmniaTests/SettingsPreferencesTests.swift` — defaults, legacy decode, normalization, rediscovery, unknown-ID, and persistence coverage.
- `Omnia/Features/Settings/MetadataSettingsView.swift` — add the native MDBList rating-provider section to the existing provider detail.
- `Omnia/Features/Library/MediaDetailView.swift` — load typed rating state, render beneath `HeroMetadataLine`, remove the lower score card, add retry/settings recovery, and use shared `FlowLayout`.
- `Omnia/Features/Settings/AboutSettingsView.swift` — add rating-source purposes, official/terms links, and required attribution text.
- `OmniaTests/AboutSettingsTests.swift` — assert complete source documentation and mandatory attribution/approval decisions.
- `DESIGN.md` — record the verified settings/detail/error/accessibility contract after implementation.

### No project-file or cloud change

`Omnia.xcodeproj` uses `PBXFileSystemSynchronizedRootGroup` for the app and tests, so new Swift files need no manual membership entry. Do not edit `Omnia.xcodeproj/project.pbxproj`, `supabase/`, entitlements, package locks, deployment settings, or signing configuration for this feature.

---

### Task 1: Provider Identity, Registry, Ordering, and Formatting

**Files:**

- Create: `Omnia/Domain/Metadata/MDBListRatingProvider.swift`
- Create: `OmniaTests/MDBListRatingProviderTests.swift`

**Produces:** `MDBListRatingProviderID`, `MDBListRatingProviderDescriptor`, `MDBListRatingValueFormat`, `MDBListRatingProviderRegistry`, and `MDBListRatingDisplayItem`.

- [ ] **Step 1: Write focused normalization and registry tests**

Cover these exact cases:

```swift
func testKnownAliasesNormalizeToCanonicalProviderIDs() {
    XCTAssertEqual(MDBListRatingProviderID("IMDb"), .imdb)
    XCTAssertEqual(MDBListRatingProviderID("tomatoes-audience"), .rottenTomatoesAudience)
    XCTAssertEqual(MDBListRatingProviderID("tomatoesaudience"), .rottenTomatoesAudience)
    XCTAssertEqual(MDBListRatingProviderID("popcorn"), .rottenTomatoesAudience)
    XCTAssertEqual(MDBListRatingProviderID("mal"), .myAnimeList)
    XCTAssertEqual(MDBListRatingProviderID("Roger Ebert"), .rogerEbert)
}

func testUnknownProviderUsesBoundedNormalizedIDAndReadableLabel() throws {
    let provider = try XCTUnwrap(MDBListRatingProviderID("Future_Source.2"))
    XCTAssertEqual(provider.rawValue, "future_source.2")
    XCTAssertEqual(MDBListRatingProviderRegistry.descriptor(for: provider).displayName, "Future Source 2")
}

func testInvalidProviderIDsAreRejected() {
    XCTAssertNil(MDBListRatingProviderID(""))
    XCTAssertNil(MDBListRatingProviderID("contains/slash"))
    XCTAssertNil(MDBListRatingProviderID(String(repeating: "a", count: 65)))
    XCTAssertNil(MDBListRatingProviderID("café"))
}
```

Also assert the approved known order: IMDb, TMDB, Rotten Tomatoes critics, Metacritic, Trakt, Letterboxd, Rotten Tomatoes audience/Popcorn, MyAnimeList, Roger Ebert; unknown providers follow lexically.

- [ ] **Step 2: Write formatting and aggregate tests**

Assert finite values in `0...100`, no rescaling, at most one fractional digit, `%` only for Rotten Tomatoes critic/audience values, and aggregate order last:

```swift
XCTAssertEqual(registry.formattedValue(7.2, for: .imdb), "7.2")
XCTAssertEqual(registry.formattedValue(76, for: .tmdb), "76")
XCTAssertEqual(registry.formattedValue(65, for: .rottenTomatoes), "65%")
XCTAssertEqual(registry.formattedAggregate(8.0), "8")
XCTAssertEqual(registry.formattedAggregate(8.1), "8.1")
```

- [ ] **Step 3: Run tests and verify RED**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia \
  -destination 'platform=macOS' \
  -only-testing:OmniaTests/MDBListRatingProviderTests test
```

Expected: compile failure because the provider types do not exist.

- [ ] **Step 4: Implement the minimum registry**

Use a value type rather than an enum so future IDs survive:

```swift
struct MDBListRatingProviderID: RawRepresentable, Codable, Hashable, Comparable, Sendable {
    let rawValue: String

    init?(_ source: String) {
        // Trim, stable ASCII lowercase, normalize known punctuation/spacing
        // aliases, then require 1...64 characters in [a-z0-9._-].
    }
}

struct MDBListRatingProviderDescriptor: Identifiable, Hashable, Sendable {
    let id: MDBListRatingProviderID
    let displayName: String
    let order: Int?
    let valueFormat: MDBListRatingValueFormat
    let approvedAssetName: String?
}
```

Keep the registry pure and deterministic. `approvedAssetName` is optional and must match the provenance audit from Task 8; do not assume all known providers have a bundled image.

- [ ] **Step 5: Run the tests and verify GREEN**

Run the Task 1 test command again. Expected: all provider tests pass.

- [ ] **Step 6: Review and commit only safe new paths**

```bash
git diff --check -- Omnia/Domain/Metadata/MDBListRatingProvider.swift OmniaTests/MDBListRatingProviderTests.swift
git diff --cached --name-only
git commit --only Omnia/Domain/Metadata/MDBListRatingProvider.swift OmniaTests/MDBListRatingProviderTests.swift \
  -m 'Model MDBList rating providers'
```

---

### Task 2: Persistent Discovery and Disabled-Provider Preferences

**Files:**

- Modify: `Omnia/Domain/Settings/SettingsPreferences.swift`
- Modify: `Omnia/Data/Settings/SettingsPreferencesStore.swift`
- Modify: `OmniaTests/SettingsPreferencesTests.swift`

**Produces:** `MDBListRatingPreferences` and store operations that never re-enable a disabled provider during discovery.

- [ ] **Step 1: Add failing preference tests**

Add assertions for:

1. `.default.mdblistRatings.discoveredProviderIDs` and `disabledProviderIDs` are empty.
2. Decoding a current settings JSON object with `mdblistRatings` removed yields `.default` for the new nested value.
3. Invalid IDs are removed during normalization.
4. `isEnabled` is true for known and newly discovered IDs unless disabled.
5. Discovering an ID unions it without changing its disabled state.
6. A disabled unknown ID round-trips through `SettingsPreferencesStore`.
7. Removing a credential does not alter these preferences.

Use the domain ID type at mutation boundaries, while persistence remains a compact `Set<String>` representation:

```swift
struct MDBListRatingPreferences: Codable, Equatable, Sendable {
    var discoveredProviderIDs: Set<String> = []
    var disabledProviderIDs: Set<String> = []

    func isEnabled(_ id: MDBListRatingProviderID) -> Bool {
        !disabledProviderIDs.contains(id.rawValue)
    }
}
```

- [ ] **Step 2: Run preference tests and verify RED**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia \
  -destination 'platform=macOS' \
  -only-testing:OmniaTests/SettingsPreferencesTests test
```

Expected: compile failures for the missing nested preference and store methods.

- [ ] **Step 3: Extend `SettingsPreferences` backward-compatibly**

Add `mdblistRatings` to stored properties, `CodingKeys`, the memberwise initializer, `.default`, and normalization. Decode it with `decodeIfPresent(... ) ?? .default`; do not increment the existing envelope version because the JSON evolution is backward-compatible.

Normalization must canonicalize every persisted string with `MDBListRatingProviderID`, retain valid disabled IDs even if undiscovered, and never add known providers to `discoveredProviderIDs` merely because the app recognizes them.

- [ ] **Step 4: Add store-level intent methods**

```swift
func recordMDBListRatingProviders(_ ids: Set<MDBListRatingProviderID>)
func setMDBListRatingProvider(_ id: MDBListRatingProviderID, enabled: Bool)
```

Both methods call `update`. Discovery unions `ids.map(\.rawValue)` only. Disabling inserts the canonical ID; enabling removes it. These methods must be idempotent so repeated title loads do not cause needless preference writes; skip persistence when the resulting value is unchanged.

- [ ] **Step 5: Run tests and verify GREEN**

Run the Task 2 command again. Expected: all preference tests pass.

- [ ] **Step 6: Review dirty-path ownership**

```bash
git diff --check -- Omnia/Domain/Settings/SettingsPreferences.swift Omnia/Data/Settings/SettingsPreferencesStore.swift OmniaTests/SettingsPreferencesTests.swift
git diff -- Omnia/Domain/Settings/SettingsPreferences.swift Omnia/Data/Settings/SettingsPreferencesStore.swift OmniaTests/SettingsPreferencesTests.swift
git diff --cached --name-only
```

These files already contain user work. Do not commit them unless the MDBList hunks can be isolated without absorbing unrelated modifications; otherwise leave the tested changes uncommitted and note them in the final handoff.

---

### Task 3: Bounded MDBList Decoding, Route Construction, and Transport Errors

**Files:**

- Modify: `Omnia/Data/Metadata/UserManagedMetadataClients.swift` (MDBList range only)
- Create: `OmniaTests/MDBListMetadataClientTests.swift`

**Produces:** `MDBListLookupRoute`, `MDBListTitleRatings`, `MDBListRating`, `MDBListMetadataError`, `MDBListRatingServing`, and an injected transport/credential client.

- [ ] **Step 1: Create deterministic contract fixtures inside the test file**

Use inline `Data` fixtures containing no real key:

```json
{
  "score": "8.1",
  "ratings": [
    {"source":"imdb","value":"7.2","votes":"190005"},
    {"source":"trakt","value":78,"votes":20216},
    {"source":"tomatoes","value":65,"votes":358},
    {"source":"future_source","value":"9.4","votes":null}
  ]
}
```

Add sibling fixtures for one malformed entry, more than 64 entries, invalid source IDs, negative/over-100/nonfinite strings, missing ratings, and malformed root JSON.

- [ ] **Step 2: Write a fake transport and credential reader**

The fake records `HTTPRequestPolicy` without printing its URL and returns or throws a configured result. Add tests proving:

- no credential means no transport call;
- no supported external identifier means no transport call;
- positive decimal TMDB/TVDB IDs up to 20 digits and IMDb `tt` plus 5...12 digits are accepted;
- invalid/zero/signed/overlong identifiers are rejected before transport;
- route priority is TMDB, then TVDB, then IMDb;
- URL scheme/host/path/query are exact when inspected as components;
- policy timeout is 15 seconds, maximum is 512 KiB, accepted type contains `application/json`, and origin is exact `https://api.mdblist.com`.

Use a synthetic key such as `test-key-not-secret` and never include the full URL in assertion failure text.

- [ ] **Step 3: Add decoding and typed-error tests**

Assert:

- numeric strings and JSON numbers decode;
- one malformed item is dropped while valid siblings and aggregate survive;
- only the first 64 entries are inspected/accepted;
- invalid/nonfinite/out-of-range values are dropped;
- 401/403 map to `.authenticationRequired`;
- 404 maps to `.notFound`;
- 429 maps to `.rateLimited`;
- 5xx and transport failure map to `.temporarilyUnavailable`;
- content-type/malformed response maps to `.malformedResponse`;
- oversized maps to `.responseTooLarge`;
- transport cancellation maps to `CancellationError` or a distinct cancellation state that the loader silently discards.

- [ ] **Step 4: Run client tests and verify RED**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia \
  -destination 'platform=macOS' \
  -only-testing:OmniaTests/MDBListMetadataClientTests test
```

Expected: compile/test failure because the current client uses `URLSession.shared`, accepts unbounded identifiers, decodes the entire ratings array as all-or-nothing, and lacks typed mappings.

- [ ] **Step 5: Replace only the MDBList range with injected bounded behavior**

Use this dependency shape:

```swift
typealias MDBListCredentialReader = @Sendable () throws -> String?

protocol MDBListRatingServing: Sendable {
    func titleRatings(for item: MediaItem, bypassCache: Bool) async throws -> MDBListTitleRatings?
}

final class MDBListMetadataClient: MDBListRatingServing, @unchecked Sendable {
    init(
        transport: any HTTPTransporting = HTTPTransport(),
        credentialReader: @escaping MDBListCredentialReader = {
            try ProviderCredentialStore.value(for: .mdblist)
        },
        cache: MDBListRatingsCache = MDBListRatingsCache()
    )

    func titleRatings(for item: MediaItem, bypassCache: Bool = false) async throws -> MDBListTitleRatings?
    func verifyStoredCredential() async throws
}
```

If strict-concurrency checking rejects the class shape, prefer an `actor` or explicitly `Sendable` immutable dependency wrapper; do not paper over mutable unsafe state with `@unchecked Sendable` unless a review proves the state is immutable/thread-safe.

Build paths with `URLComponents`, add exactly one `apikey` query item, and pass the result to `HTTPTransport`. Read and trim the current Keychain value before consulting any cache. Keep the existing Fight Club TMDB `550` connection check but route it through the same production validation/transport.

Decode `ratings` through a lossy element wrapper so malformed elements are skipped independently. Limit work to 64 array elements and validate every provider through `MDBListRatingProviderID`.

- [ ] **Step 6: Run tests and verify GREEN**

Run the Task 3 command again. Expected: all client tests pass, with no real network or Keychain access.

- [ ] **Step 7: Review without committing unrelated AniList work**

```bash
git diff --check -- Omnia/Data/Metadata/UserManagedMetadataClients.swift OmniaTests/MDBListMetadataClientTests.swift
git diff -- Omnia/Data/Metadata/UserManagedMetadataClients.swift
git diff --cached --name-only
```

Commit the new test path alone if desired. Leave the pre-existing untracked production file uncommitted unless its ownership is resolved.

---

### Task 4: Successful-Result TTL Cache and In-Flight Coalescing

**Files:**

- Create: `Omnia/Data/Metadata/MDBListRatingsCache.swift`
- Create: `OmniaTests/MDBListRatingsCacheTests.swift`
- Modify: `Omnia/Data/Metadata/UserManagedMetadataClients.swift` (MDBList wiring only)

**Produces:** a cache keyed only by `MDBListLookupRoute`, with a 30-minute success TTL and no credential material.

- [ ] **Step 1: Write cache tests with a mutable `ClockProviding` fake**

Prove:

1. A successful nonempty or aggregate-only result is returned before expiry.
2. Advancing exactly past 30 minutes invokes the loader again.
3. A thrown failure is not cached as success.
4. `bypassCache: true` invokes the loader and replaces the successful entry.
5. Two concurrent calls for the same route invoke the loader exactly once and receive the same value.
6. Different routes do not coalesce.
7. Cancellation of one waiter does not publish a stale result into a different route.
8. The key's reflected/debug description contains provider/media type/identifier but never the credential.

- [ ] **Step 2: Run cache tests and verify RED**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia \
  -destination 'platform=macOS' \
  -only-testing:OmniaTests/MDBListRatingsCacheTests test
```

Expected: compile failure because `MDBListRatingsCache` does not exist.

- [ ] **Step 3: Implement the cache as an actor**

Use dictionaries for successful entries and in-flight tasks, evict expired entries on access, and remove the matching in-flight task in `defer`. Do not cache thrown failures. A nil/no-usable-result response may be treated as a successful empty result only if the API actually returned a valid 2xx response; keep its TTL the same initially to protect quota.

The MDBList client must perform the credential read before calling the cache so deleting the Keychain item prevents cached results from being returned immediately.

- [ ] **Step 4: Run cache and client tests and verify GREEN**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia \
  -destination 'platform=macOS' \
  -only-testing:OmniaTests/MDBListRatingsCacheTests \
  -only-testing:OmniaTests/MDBListMetadataClientTests test
```

- [ ] **Step 5: Commit safe new paths only**

```bash
git diff --check -- Omnia/Data/Metadata/MDBListRatingsCache.swift OmniaTests/MDBListRatingsCacheTests.swift
git diff --cached --name-only
git commit --only Omnia/Data/Metadata/MDBListRatingsCache.swift OmniaTests/MDBListRatingsCacheTests.swift \
  -m 'Cache MDBList rating responses'
```

---

### Task 5: Presentation Filtering and Cancellable Load State

**Files:**

- Create: `Omnia/Features/Library/MDBListRatingsPresentation.swift`
- Create: `OmniaTests/MDBListRatingsPresentationTests.swift`

**Produces:** `MDBListRatingsPresentation`, `MDBListRatingsLoadState`, `MDBListRatingsLoader`, and `MDBListRatingsRecoveryAction`; consumes `MDBListRatingServing` from Task 3.

- [ ] **Step 1: Write pure presentation tests**

Given a mixed response and preferences, prove:

- every valid enabled external provider appears once;
- aliases deduplicate to the canonical ID deterministically;
- disabled providers disappear without gaps;
- absent values do not become zero;
- unknown valid providers appear after known providers in lexical order;
- the aggregate appears last even when every external provider is disabled;
- aggregate-only is a valid visible result;
- no values yields an empty presentation;
- accessibility labels use the provider's full display name and formatted value/known scale.

When duplicate canonical entries occur, retain the first valid MDBList response entry rather than averaging or selecting by vote count.

- [ ] **Step 2: Write loader-state and stale-result tests**

Inject an `MDBListRatingServing` fake with controllable continuations. Assert these transitions:

- not configured/no supported ID -> `.empty` without visible error;
- request start -> `.loading`;
- partial/success -> `.loaded`;
- 401/403 -> `.failed(.authenticationRequired)` with `.openSettings`;
- 429 -> `.failed(.rateLimited)` without automatic retry;
- transient/malformed/oversized -> `.failed(... )` with `.retry`;
- retry is ignored while already loading and calls `bypassCache: true` otherwise;
- cancellation is silent;
- completing title A after title B has started cannot replace title B's state.

- [ ] **Step 3: Run tests and verify RED**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia \
  -destination 'platform=macOS' \
  -only-testing:OmniaTests/MDBListRatingsPresentationTests test
```

- [ ] **Step 4: Implement a small main-actor loader**

```swift
@MainActor
@Observable
final class MDBListRatingsLoader {
    private(set) var state: MDBListRatingsLoadState = .idle

    func load(for item: MediaItem) async
    func retry(for item: MediaItem) async
    func cancel()
}
```

Use a monotonically changing request token or route identity before applying a result. The loader owns its task/cancellation; it does not own settings persistence. It returns discovered provider IDs alongside the loaded presentation input so `MediaDetailView` can record them through `SettingsPreferencesStore` on the main actor.

- [ ] **Step 5: Run tests and verify GREEN**

Run the Task 5 command again.

- [ ] **Step 6: Commit safe new paths**

```bash
git diff --check -- Omnia/Features/Library/MDBListRatingsPresentation.swift OmniaTests/MDBListRatingsPresentationTests.swift
git diff --cached --name-only
git commit --only Omnia/Features/Library/MDBListRatingsPresentation.swift OmniaTests/MDBListRatingsPresentationTests.swift \
  -m 'Present MDBList rating states'
```

---

### Task 6: Native MDBList Rating Settings

**Files:**

- Modify: `Omnia/Features/Settings/MetadataSettingsView.swift`
- Modify: `OmniaTests/MDBListRatingsPresentationTests.swift`

**Produces:** an always-available `Ratings on Title Details` section on the MDBList provider screen.

- [ ] **Step 1: Add settings-list model tests**

Test a pure helper that creates the settings rows from `known registry ∪ discovered IDs`. Assert stable known order, lexical unknown order, all rows present without a credential, disabled state preserved, and the aggregate informational row present without a toggle.

- [ ] **Step 2: Run the presentation test target and verify RED**

Use the Task 5 test command. Expected: failure for the missing settings-row helper.

- [ ] **Step 3: Add `SettingsPreferencesStore` to `MetadataProviderDetailView`**

Add `@Environment(SettingsPreferencesStore.self) private var settings`. For `provider.id == "mdblist"`, place this section after Connection:

```swift
Section {
    ForEach(MDBListRatingProviderRegistry.settingsDescriptors(
        discovered: settings.preferences.mdblistRatings.discoveredProviderIDs
    )) { descriptor in
        Toggle(isOn: providerBinding(descriptor.id)) {
            MDBListRatingProviderLabel(descriptor: descriptor)
        }
    }

    LabeledContent("MDBList Score", value: "Always shown")
} header: {
    Text("Ratings on Title Details")
} footer: {
    Text("New rating sources discovered from MDBList are enabled by default.")
}
```

Use native toggle styling; do not set a custom switch color, fixed text height, or web-card background. The provider image, when approved, is decorative and `.accessibilityHidden(true)`; the `Toggle` label exposes the full name and native on/off value. Text fallback must remain legible at accessibility sizes.

- [ ] **Step 4: Verify settings behavior manually in previews or a local build**

Check no credential, stored credential, known disabled, discovered unknown, long fallback name, macOS keyboard traversal, iPad pointer/focus, VoiceOver row name/value, and accessibility Dynamic Type wrapping.

- [ ] **Step 5: Run tests and affected builds**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia \
  -destination 'platform=macOS' \
  -only-testing:OmniaTests/MDBListRatingsPresentationTests \
  -only-testing:OmniaTests/SettingsPreferencesTests test
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' build
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'generic/platform=iOS Simulator' build
```

- [ ] **Step 6: Review dirty path and leave uncommitted if inseparable**

`MetadataSettingsView.swift` is pre-existing untracked user work. Do not commit the whole file without resolving ownership.

---

### Task 7: Title-Detail Rating Group, Loading, and Recovery

**Files:**

- Create: `Omnia/UI/Components/FlowLayout.swift`
- Modify: `Omnia/Features/Library/MediaDetailView.swift`
- Modify: `OmniaTests/MDBListRatingsPresentationTests.swift`

**Produces:** responsive provider ratings immediately below `HeroMetadataLine`, plus compact state/recovery UI that does not block the title.

- [ ] **Step 1: Move `FlowLayout` without behavior change**

Copy the existing private layout into `Omnia/UI/Components/FlowLayout.swift`, make it module-internal, delete the private duplicate, and run the macOS build. The Genres section must remain visually/behaviorally unchanged.

- [ ] **Step 2: Replace raw optional state with the loader and settings environment**

In `MediaDetailView`, add `@Environment(SettingsPreferencesStore.self)`, a state-owned `MDBListRatingsLoader`, and a Boolean for presenting MDBList settings. After metadata/add-on resolution, ask the loader to load the resolved title. Record every returned valid source through `recordMDBListRatingProviders` even if that source is currently disabled.

The enclosing `.task(id: item.id)` must cancel/reset ratings before a new title result can be applied. Do not use `try?`; typed failures drive visible state.

- [ ] **Step 3: Add a compact `MDBListRatingsView` beneath metadata**

Place it in `detailIdentity` immediately after `HeroMetadataLine` and before the synopsis. For loaded state, build presentation from the latest preferences so toggles take effect without a new network call.

Each item uses a tight `HStack` with an optional original-color transparent mark and formatted value. Use semantic foreground styles and no decorative animation. Apply an explicit combined accessibility label such as `IMDb rating 7.2` or `Rotten Tomatoes audience score 90 percent`; hide the decorative image.

Use shared `FlowLayout(spacing: 8)` with a width no larger than the current cinematic hero column. Do not introduce a horizontal scroller. Remove the existing `MDBListScoreView` from `detailInformation` so the aggregate appears only once.

- [ ] **Step 4: Implement every approved state**

- `.idle` / not configured / no supported identifier / valid empty: render nothing.
- `.loading`: small `ProgressView` plus accessible `Loading ratings`, without blocking actions or synopsis.
- authentication: `Ratings need your MDBList key` plus `Open MDBList Settings`.
- rate limit: `MDBList request limit reached`; no automatic retry.
- transient/malformed/oversized: `Ratings unavailable` plus `Retry`.
- retry: disabled while loading and calls `bypassCache: true`.
- cancellation/title change: render no stale error or result.

Present the existing `MetadataProviderDetailView` for MDBList in a `NavigationStack` sheet from the authentication action; reuse the settings screen rather than duplicating credential controls. Supply a native Done/cancellation toolbar item if the reused view is modal.

- [ ] **Step 5: Verify hero sizing with evidence before changing it**

Test existing `detailHeroHeight` at iPhone portrait/landscape, iPad full-screen and narrow multitasking, and Mac narrow/wide windows with no ratings, one line, wrapped ratings, and accessibility Dynamic Type. Change the fixed hero height only if screenshots or clipping demonstrate the need; use a responsive minimum rather than provider-count magic numbers.

- [ ] **Step 6: Run focused tests and builds**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia \
  -destination 'platform=macOS' \
  -only-testing:OmniaTests/MDBListRatingsPresentationTests test
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' build
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'generic/platform=iOS Simulator' build
```

- [ ] **Step 7: Review and commit only the safe new layout path if needed**

`MediaDetailView.swift` contains existing user changes. Do not sweep them into a feature commit.

---

### Task 8: Official Provider Marks, Provenance, and About Attributions

**Files:**

- Create: `Omnia/Assets.xcassets/RatingProviderMarks/*`
- Create: `docs/provider-assets/mdblist-rating-provider-marks.md`
- Modify: `Omnia/Domain/Metadata/MDBListRatingProvider.swift`
- Modify: `Omnia/Features/Settings/AboutSettingsView.swift`
- Modify: `OmniaTests/AboutSettingsTests.swift`

**Produces:** reviewed original-color marks where permitted, deterministic text fallback everywhere else, and inspectable provenance/attribution.

- [ ] **Step 1: Write the provenance matrix before downloading assets**

For IMDb, TMDB, Rotten Tomatoes critics, Metacritic, Trakt, Letterboxd, Rotten Tomatoes audience/Popcorn, MyAnimeList, Roger Ebert, and MDBList, record:

- canonical source ID and display name;
- official brand/terms URL;
- retrieval/review date `2026-08-11`;
- whether in-app redistribution/use is permitted;
- official filename/format and any lossless packaging conversion;
- required attribution, link-back, registered-mark, minimum-size, clear-space, color, or approval condition;
- final decision: exact asset-catalog name or `text fallback`.

Do not mark a provider approved from visual availability alone. IMDb's toolkit directs partners to approval; Rotten Tomatoes directs data/logo integrations through its Business Proposal Form and requires attribution wherever scores display. Until evidence is stored, their decision is `text fallback`.

- [ ] **Step 2: Add only approved official files**

Prefer the official SVG/PDF. If Xcode cannot package the supplied SVG correctly, convert losslessly to a vector PDF and record the command/tool and SHA-256 of both source and packaged file. Use transparent PNG only when it is the official form. Preserve aspect ratio and brand colors; do not tint.

Create distinct `Rating<Provider>Mark` assets rather than changing the rendering intent of existing metadata/account marks. This avoids colliding with the six pre-staged user `Contents.json` edits and keeps rating art `.renderingMode(.original)`.

- [ ] **Step 3: Add failing About/provenance tests**

Assert that every known provider has an About resource or rating-source link, all links are HTTPS, TMDB's required notice remains exact, and every registry `approvedAssetName` appears in the documented approved matrix. Represent asset approval in a small tested Swift registry rather than parsing Markdown at runtime.

- [ ] **Step 4: Update `AboutCatalog`**

Add the rating sources under Metadata & Discovery and Attributions/Terms where appropriate. Do not claim Omnia directly integrates each provider API; wording must state that MDBList supplies the displayed rating. Include required trademark/attribution/link-back text only as established by official terms.

- [ ] **Step 5: Inspect assets visually**

Render each approved mark on light and dark semantic backgrounds at the actual title-detail and settings sizes. Check transparency, clipping, aspect ratio, original colors, Increase Contrast, and no unintended template tint. Text fallbacks must fit/wrap at accessibility Dynamic Type and remain clear without color.

- [ ] **Step 6: Run tests and builds**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia \
  -destination 'platform=macOS' \
  -only-testing:OmniaTests/AboutSettingsTests \
  -only-testing:OmniaTests/MDBListRatingProviderTests test
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' build
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'generic/platform=iOS Simulator' build
```

- [ ] **Step 7: Commit with an explicit path list only after inspecting the staged set**

```bash
git diff --cached --name-only
git diff --check -- docs/provider-assets/mdblist-rating-provider-marks.md Omnia/Domain/Metadata/MDBListRatingProvider.swift Omnia/Features/Settings/AboutSettingsView.swift OmniaTests/AboutSettingsTests.swift
```

Never include the six pre-staged asset `Contents.json` files. Commit only the new rating asset directory and explicitly reviewed code/docs paths with `git commit --only ...`.

---

### Task 9: Full Regression, Accessibility, and Supported-Platform Verification

**Files:**

- Modify: `DESIGN.md`
- Review: all Task 1–8 paths

- [ ] **Step 1: Run the complete macOS test bundle with fresh evidence**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test
```

Expected: all existing and new tests pass. If signing prevents the hosted test bundle, report the exact signing blocker; do not bypass signing.

- [ ] **Step 2: Build every affected supported destination**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' build
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'generic/platform=iOS Simulator' build
```

- [ ] **Step 3: Smoke-test the complete flow**

Use deterministic fixtures/previews for network states and a user-owned key only for optional device verification. Cover:

- no credential and configure-before-connection settings;
- movie and series route resolution;
- all known sources, an unknown source, and duplicate aliases;
- one-line and wrapped ratings;
- all external sources disabled with aggregate still visible;
- partial response and aggregate-only response;
- title not found/no supported identifier;
- authentication, rate limit, offline/server, malformed, oversized, Retry recovery;
- credential removal immediately hiding cached results;
- rapid title navigation with no stale result;
- playback, library, seasons, synopsis, and detail facts unchanged.

- [ ] **Step 4: Perform the Apple-platform UI/accessibility matrix**

Verify VoiceOver, accessibility Dynamic Type sizes, Full Keyboard Access, focus order, Reduce Motion, Reduce Transparency, Increase Contrast, light/dark appearance, and color-independent state. Check iPhone portrait/landscape and safe areas; iPad full-screen/multitasking, pointer, and keyboard; Mac narrow/wide resizing, menus, hover, keyboard, windowed, and full screen.

Capture screenshots for settings and title detail at representative iPhone, iPad, and Mac widths, including a wrapped Dynamic Type case and an error/recovery case.

- [ ] **Step 5: Update the durable design contract from verified behavior**

In `DESIGN.md`, document the ratings placement, native setting location, dynamic provider fallback, aggregate-always-visible rule, error/retry states, and asset provenance policy. Link to the approved spec and provenance matrix rather than duplicating security/performance runbooks.

- [ ] **Step 6: Run final hygiene checks**

```bash
git diff --check
git status --short
git diff --cached --name-only
git diff --stat
```

Review every intended hunk and confirm no API key, request URL, generated build output, unrelated user edit, Supabase change, or pre-staged asset edit entered a feature commit.

- [ ] **Step 7: Use verification-before-completion before making any passing claim**

Report exact commands, exit status, test counts where available, supported destinations built, manual scenarios verified, any device/hosted checks not performed, logo permission fallbacks, dirty paths intentionally left uncommitted, and residual risks. Do not describe inspection alone as performance evidence.

## Execution Notes

- Tasks 1–5 establish behavior without relying on logo availability, so provider data and text fallbacks can ship safely even while a mark awaits permission.
- Tasks 6–7 should be executed together as the user-visible slice, but retain their separate RED/GREEN checkpoints.
- Task 8 is a legal/provenance gate, not a reason to omit a returned provider: a denied or unavailable mark resolves to the tested text fallback.
- No task authorizes a live MDBList account mutation, Supabase deployment, secret change, release promotion, or external permission request on the user's behalf.
