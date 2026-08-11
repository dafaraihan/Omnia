# MDBList Rating Providers Design

## Status

Approved direction: **native Apple-platform controls with a typed provider registry and dynamic fallback**. Omnia displays every usable rating source returned by MDBList, enables newly discovered sources by default, lets the user disable individual external sources, and always shows MDBList's aggregate score when it is available.

## Problem and Evidence

Omnia already has the beginnings of a user-managed MDBList integration:

- `ProviderCredentialStore` keeps the user's MDBList API key in Keychain.
- `MDBListMetadataClient` resolves a title through TMDB, TVDB, or IMDb identity and decodes MDBList's aggregate score and provider ratings.
- `MediaDetailView` currently places only the aggregate MDBList score in the lower Details area.
- `MetadataProviderDetailView` provides credential save, remove, and connection-test controls but no per-rating-source preferences.

The supplied Nuvio screenshots demonstrate the requested interaction: rating-source switches live with the MDBList credential settings, and enabled ratings appear as compact official provider marks and values directly below the title's release metadata. The implementation must adopt that information hierarchy without copying Nuvio's web styling or navigation.

MDBList's official documentation establishes the public API origin, user-owned API key, and current account request limits. Its official product changelog also documents newer authentication options and the July 2026 change that presents the aggregate score on a 0–10-style scale. Omnia must display the returned aggregate value rather than assuming the older 0–100 representation.

References:

- [MDBList API documentation](https://docs.mdblist.com/docs/api)
- [MDBList product and API updates](https://mdblist.com/new-features/)
- [Apple Design Resources](https://developer.apple.com/design/resources/)
- [Apple Human Interface Guidelines — Settings](https://developer.apple.com/design/human-interface-guidelines/settings)
- [Apple Human Interface Guidelines — Toggles](https://developer.apple.com/design/human-interface-guidelines/toggles)
- [Apple Human Interface Guidelines — Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility/)
- [Apple Human Interface Guidelines — Images](https://developer.apple.com/design/human-interface-guidelines/images)
- Repository [DESIGN.md](../../../DESIGN.md), [SECURITY.md](../../../SECURITY.md), and [PERFORMANCE.md](../../../PERFORMANCE.md)

MDBList's interactive API page did not expose its schema to the available documentation crawler during discovery. This design therefore does not invent undocumented logo URLs, provider catalogs, or response fields. It extends the response shape already represented in Omnia (`score`, `ratings[].source`, `ratings[].value`, and `ratings[].votes`) and requires deterministic contract fixtures before production behavior changes.

## Goals

- Display every valid rating entry MDBList returns for a title.
- Show enabled external ratings below the title's year, runtime, and age rating.
- Always show the aggregate MDBList score when returned.
- Give users native per-provider toggles in MDBList settings.
- Enable newly discovered provider identifiers by default and persist their discovery.
- Use reviewed official transparent provider marks for known sources.
- Preserve partial results and the rest of the title-detail experience when MDBList is slow, unavailable, malformed, or rate-limited.
- Keep the user's MDBList credential on the existing direct Keychain-to-MDBList trust path.

## Non-Goals

- MDBList account synchronization, lists, watch history, ratings submission, OAuth, or PKCE.
- A Supabase migration, hosted secret, Edge Function change, or deployment.
- User-controlled provider reordering.
- Runtime logo scraping, favicon lookup, or a third-party logo package/service.
- Rescaling or combining external provider values into a new Omnia score.
- Caching provider credentials or full credential-bearing request URLs.

## Provider Model

The provider layer has two identities:

1. The normalized identifier persisted in preferences and used for filtering.
2. A presentation descriptor that supplies a display name, aliases, official mark asset, ordering rank, and value format when Omnia recognizes the source.

Normalization trims whitespace, lowercases using a stable locale-independent rule, and accepts 1–64 ASCII characters matching `[a-z0-9._-]`. Known aliases collapse to one identifier. At minimum, the registry recognizes:

- IMDb;
- TMDB;
- Rotten Tomatoes critics;
- Metacritic;
- Trakt;
- Letterboxd;
- Rotten Tomatoes audience/Popcorn;
- MyAnimeList;
- Roger Ebert.

Aliases such as `popcorn`, `tomatoesaudience`, and equivalent punctuation/casing variants map to the same audience-score provider. `mal` maps to MyAnimeList. Equivalent spelling variants for Rotten Tomatoes and Roger Ebert map to their canonical identifiers.

A valid unknown source is not discarded. Omnia derives a safe human-readable label from its returned identifier, assigns it after the known providers in deterministic lexical order, records it as discovered, enables it by default, and presents its raw valid value. Until an official asset is reviewed, the unknown provider uses a neutral text fallback rather than an unofficial or fabricated logo.

The aggregate MDBList `score` is not an external provider preference. It is a separate always-visible item placed after the enabled external ratings. Omnia displays the returned finite value with at most one fractional digit and does not multiply, divide, or clamp it into an assumed scale.

Provider values remain on their source's native returned scale. Recognized percentage sources may append `%`; other known and unknown values use the returned number with at most one fractional digit. Omnia never derives a value from `votes` and never substitutes the aggregate score for a missing provider rating.

## Preferences and Discovery

`SettingsPreferences` gains a nested, Codable MDBList rating-preferences value containing:

- the set of normalized provider identifiers encountered in successful responses; and
- the set of normalized provider identifiers the user has disabled.

The default contains no disabled providers. Backward-compatible decoding uses that default when an existing payload lacks the new field. Normalization removes invalid or empty identifiers but retains disabled unknown identifiers so a user's choice survives temporary provider absence.

The settings list is the union of the reviewed known-provider registry and valid discovered identifiers. Known providers appear in a stable human-designed order; unknown discovered providers follow lexically. Receiving a successful response unions its valid sources into the discovered set. This update must not re-enable a provider the user previously disabled.

All provider toggles remain available even when the MDBList credential is not currently connected, allowing a user to configure presentation before or after credential entry. Removing the credential stops requests and ratings presentation but does not erase provider preferences. The aggregate-score row is informational and has no toggle.

## Networking, Credential, and Cache Boundary

The MDBList title lookup remains a direct, user-managed integration:

1. `MediaDetailView` resolves built-in and add-on metadata so the title has its best available external identifiers.
2. The MDBList ratings service reads the current API key from Keychain immediately before use.
3. It selects a bounded TMDB, TVDB, or IMDb lookup route and sends one HTTPS request to the exact normalized host `api.mdblist.com`. TMDB and TVDB identifiers are positive decimal strings of at most 20 digits; IMDb identifiers match `tt` followed by 5–12 digits.
4. It validates status, content type, response size, and decoded fields.
5. It returns partial valid ratings plus the optional aggregate score.
6. The view records newly discovered sources, filters disabled external providers, and builds the presentation rows.

The networking client uses an injected session/transport for deterministic tests. The live configuration is ephemeral, has an explicit timeout, does not use a disk URL cache, cooperates with task cancellation, bounds the decompressed response accepted into memory, and does not follow a credential-bearing redirect to another host. No diagnostic includes the API key or the full credential-bearing URL.

The service provides an in-memory, title-route-keyed TTL cache and coalesces concurrent lookups for the same title. Cache keys contain provider type, media type, and title identifier, never the credential. A current Keychain credential is still required before a cache entry can be returned, so removing the credential immediately hides ratings. Retry bypasses a cached failure; failures are not cached as successful empty results.

The initial implementation uses a 15-second request timeout, a 512 KiB maximum decoded response body, and a 30-minute successful-result TTL. These are explicit safety and quota controls, not performance claims. Any later tuning requires evidence under the repository performance policy.

## Decoding and Validation

The response decoder remains tolerant at the provider-entry boundary:

- numeric values may arrive as JSON numbers or finite numeric strings;
- malformed entries are dropped individually;
- valid siblings and the aggregate score survive an invalid optional provider entry;
- source identifiers are length-bounded and normalized before storage or display;
- nonfinite values and values outside the inclusive range 0–100 are rejected;
- votes may be decoded for future descriptive accessibility text but do not control whether a score is displayed;
- no more than 64 provider entries are accepted from one response, in addition to the 512 KiB body-size bound.

The client maps HTTP and transport outcomes into typed, non-secret-bearing states. It must distinguish at least unauthenticated/forbidden, rate-limited, title-not-found or no usable result, transient network/server failure, cancellation, oversized response, and malformed response.

## Settings UI

MDBList remains a destination inside Omnia's existing Metadata settings hierarchy. Its screen continues to use a native SwiftUI `Form` and gains a `Section` titled **Ratings on Title Details**.

Each external provider is a labeled native `Toggle` row:

- official mark or safe textual fallback at the leading edge;
- provider name as the control label;
- platform-native switch/checkbox treatment supplied by SwiftUI;
- a minimum semantic row height with no fixed text height;
- native focus, keyboard, pointer, and VoiceOver behavior.

Apple's HIG recommends switch-style toggles in list rows on iOS and iPadOS, which this structure provides automatically. The section footer explains that newly discovered MDBList sources appear enabled by default. A noninteractive row states that the aggregate MDBList score is always shown when available.

The section is visible whether or not a credential is stored. Credential guidance, secure entry, save, remove, connection testing, destructive confirmation, and status copy remain in their existing Connection section.

## Title-Detail UI

The ratings group belongs in `detailIdentity`, immediately after `HeroMetadataLine` and before the synopsis. It is not a separate card in the lower Details section.

Each visual item contains the provider's transparent mark followed by its formatted value. The mark retains its official colors and is not rendered as a template. Text uses semantic hero foreground styles; status never depends on color alone. The group uses Omnia's existing flow-layout behavior so it remains one line on a wide Mac or iPad when space permits and wraps naturally on iPhone, split view, narrow Mac windows, localization, and larger Dynamic Type sizes.

Known provider order is stable. Unknown sources follow the known sources lexically. The aggregate MDBList score follows all enabled external providers. Disabled providers are absent without leaving gaps. Providers that do not return a valid value for the current title are absent.

The fixed cinematic hero must accommodate the wrapped rating group without clipping or overlapping the synopsis and actions. Implementation must verify the existing supported size classes before changing the hero's height contract; it may make the hero's minimum height responsive if evidence shows that wrapping or accessibility text otherwise clips.

## Loading, Empty, Partial, and Error States

- **Not configured:** Do not request MDBList and do not show a ratings row.
- **Loading:** Show a small semantic progress indicator in the ratings position without blocking the rest of the title detail.
- **Success:** Show enabled valid external ratings and the aggregate score.
- **Empty/title not found/no supported identifier:** Omit the ratings group; do not represent missing values as zero.
- **Partial response:** Show every valid enabled rating and omit only invalid or missing entries.
- **Authentication failure:** Show a compact message with an `Open MDBList Settings` action that presents the existing MDBList provider-settings content; do not duplicate credential controls in the detail view.
- **Rate limit:** State that the MDBList request limit was reached; do not spin or retry automatically.
- **Transient network/server/malformed/oversized response:** Show `Ratings unavailable` with an explicit Retry action.
- **Cancellation/title change:** Silently discard stale work and never apply the previous title's response.
- **Offline recovery:** The rest of the detail remains usable; Retry performs a fresh lookup when connectivity returns.

Retry is disabled while a retry is already in flight. A later successful retry replaces the error state. No rating-state transition changes playback, library, synopsis, season, or metadata state.

## Accessibility and Platform Adaptation

- Use semantic SwiftUI text styles and colors; do not hardcode web pixel typography.
- Provider marks are decorative and hidden from accessibility.
- Each combined rating announces provider name, formatted value, and known scale where appropriate.
- The loading indicator, error text, settings route, and Retry action receive distinct labels and predictable focus order.
- Native toggles expose their on/off value without using color as the only signal.
- Dynamic Type may wrap settings rows and rating items rather than truncate critical labels or values.
- Full Keyboard Access and macOS keyboard navigation can reach every toggle, settings link, and Retry action.
- Increase Contrast and light/dark appearance preserve legibility; provider marks receive no unreviewed tint transformation.
- Reduce Motion prevents decorative rating transitions; functional state changes remain immediate.
- Reduce Transparency falls back through existing Omnia materials and semantic foregrounds without obscuring rating values.
- iPad multitasking and Mac resizing use the same responsive flow behavior; no horizontal ratings scroller is introduced.

## Provider Marks and Provenance

Known-provider marks are bundled in `Assets.xcassets` using official provider-supplied artwork. Prefer vector PDF/SVG for flat marks and transparent PNG only when that is the official available format. Preserve aspect ratio, transparency, safe area, and official brand colors. Do not redraw marks, scrape search results, use a runtime favicon, or introduce a logo dependency.

For every added asset, record:

- provider and canonical source identifier;
- official download or brand-guideline URL;
- retrieval date;
- original format and any lossless packaging conversion;
- applicable attribution or trademark requirement.

The About/Attributions surface links to providers and includes any attribution their official terms require. If official artwork cannot be obtained or its permitted in-app use cannot be established, Omnia uses the provider's textual fallback until that review is complete.

## Verification

### Automated tests

1. Decode aggregate and provider values from both JSON numbers and numeric strings.
2. Prove one malformed provider entry does not erase valid siblings or the aggregate score.
3. Reject invalid, empty, overlong, negative, and nonfinite values and source identifiers.
4. Normalize known aliases and preserve distinct valid unknown providers.
5. Prove stable provider ordering and raw/source-specific formatting without rescaling the aggregate.
6. Prove newly discovered providers are enabled, a disabled provider remains disabled after rediscovery, and an unknown disabled identifier round-trips.
7. Decode a pre-feature settings payload with the new defaults and persist the updated preference round-trip.
8. Prove the aggregate score remains visible regardless of external-provider toggles.
9. Prove missing credentials or supported identifiers produce no network request.
10. Verify exact HTTPS origin and bounded route construction without exposing the API key in test output.
11. Verify authentication, rate-limit, not-found, server, malformed, oversized, redirect, timeout, and cancellation mappings.
12. Verify TTL cache hits, expiration, retry bypass, and concurrent in-flight deduplication.
13. Verify title changes cannot apply stale rating results.

Production behavior follows test-driven development: each behavior begins with a focused failing test, the failure is observed for the intended reason, and only then is the minimum production change made.

### Build and smoke verification

Run from the repository root:

```sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' build
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'generic/platform=iOS Simulator' build
git diff --check
```

Smoke-test at least one movie, one series, a partial-rating title, a title with an unknown provider fixture, a missing-result title, authentication failure, rate limiting, offline failure, and retry recovery. Check iPhone portrait/landscape and safe areas; iPad full-screen and multitasking widths; and Mac narrow/wide resizing, pointer, keyboard, and full screen.

Accessibility review covers VoiceOver, Dynamic Type through accessibility sizes, Full Keyboard Access, focus order, Reduce Motion, Reduce Transparency, Increase Contrast, light/dark appearance, and color-independent state. Provider images are inspected at target scale for transparency, clipping, incorrect tinting, and low-contrast failure.

## Operational Boundary

This feature requires no hosted mutation. Local implementation and verification do not authorize `supabase db push`, secret changes, live configuration changes, or Edge Function deployment. MDBList connection and quota behavior requiring a real user key remain device/user verification; automated tests use redacted deterministic fixtures and an injected transport.
