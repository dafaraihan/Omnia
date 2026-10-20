# Settings Capability Overhaul Design

> **Automated-validation policy:** Follow the repository-root `AGENTS.md`. Instructions below that call for automated test targets, suites, fixtures, or scripts are historical and superseded; use builds, static checks, and focused manual evidence instead.

**Status:** Approved on 2026-08-11

**Delivery:** One cohesive implementation and release; no placeholder or user-facing phased rollout

**Platforms:** iPhone, iPad, and Mac

## Objective

Bring the applicable settings capabilities shown in the supplied Fusion screenshots into Omnia as working, native Apple-platform features. Fusion is a feature reference, not a visual template. Omnia uses system navigation, controls, typography, symbols, materials, focus, and accessibility behavior, adapting each surface to iPhone, iPad, and Mac.

Every visible setting must change real behavior on the current platform and player. Unsupported controls are omitted rather than displayed as decorative or permanently disabled rows.

This approved design replaces the earlier phase ordering for this request. The earlier Settings Phase 0A and 0B documents remain historical design evidence, but this delivery incorporates only the contracts required by the approved local-only scope. Full event sourcing and provider-delivery infrastructure are not required because remote progress/watchlist ownership and synchronization are explicitly excluded.

## Product Decisions

### Included

- HTTPS add-on installation, capability disclosure, refresh, enable/disable, reorder, timeout, import/export, and confirmed removal.
- Local Continue Watching and Watchlist ownership, limits, import/export, and destructive clearing controls.
- A local Upcoming Home row derived from locally saved series and Omnia metadata.
- IntroDB as a read-only external source for intro timestamps.
- In-app playback through AVPlayer on iPhone/iPad and libmpv on Mac.
- Skip Intro presentation and optional automatic skipping.
- Next-episode autoplay and configurable Up Next presentation timing.
- Remembered source selection with bounded retention, optional autoplay of a safe compatible source, direct Continue Watching behavior, and compatible-format filtering.
- Preferred and fallback audio/subtitle languages, SDH preference, and anime sub/dub preference.
- Subtitle appearance preview, system-default behavior, presets, validated custom styling, and reset.

### Excluded

- Trakt.
- AniList.
- PublicMetaDB.
- External playback applications.
- Per-media-type external player selection.
- Subtitle translation.
- User-selectable cache implementation modes.
- Home preview autoplay and preview sound, because Omnia has no authenticated direct-preview media contract and must not treat ordinary content streams as trailers.
- Remote progress or Watchlist synchronization, including Omnia-account sync.
- Hosted mutations, Supabase deployment, migrations, or secret changes.

Manual cache selection is excluded because it exposes an implementation detail that each player should adapt automatically. Existing unrelated provider behavior outside the affected surfaces is preserved unless it directly exposes one of the excluded integrations.

## Architecture

### `SettingsPreferencesStore`

Own small local preferences: toggles, limits, language identifiers, subtitle style, request timeouts, remembered-source duration, and playback behavior. Values use typed enums and bounded numeric ranges rather than raw strings throughout the UI. `UserDefaults` remains appropriate for these small preferences.

Preference dependency rules are centralized. Examples include auto-skip requiring Skip Intro and custom subtitle controls requiring an Omnia custom style rather than Follow System.

### Defaults and bounds

Defaults preserve current behavior where Omnia already has one and avoid enabling surprising automatic actions for new capabilities.

| Preference | Default | Allowed values or range |
| --- | --- | --- |
| Add-on request timeout | 20 seconds | 5, 10, 15, 20, or 30 seconds |
| Continue Watching limit | No Limit | 10, 20, 50, or No Limit |
| Local Watchlist action | On | On or Off |
| Show Upcoming on Home | On | On or Off |
| Upcoming look-ahead | 60 days | 7, 14, 30, 60, or 90 days |
| Upcoming item limit | No Limit | 10, 20, 50, or No Limit |
| Show Skip Intro | On | On or Off |
| Auto-skip intro | Off | On or Off; available only while Show Skip Intro is on |
| Autoplay next episode | Off | On or Off |
| Up Next timing | 30 seconds remaining | 15, 30, or 60 seconds remaining |
| Remember source selection | On | On or Off |
| Remembered-source retention | 3 days | 24 hours, 3 days, or 1 week |
| Autoplay first compatible source | Off | On or Off |
| Direct Continue Watching playback | Off | On or Off |
| Compatible formats only | On | On or Off |
| Preferred audio | Follow System | A supported `Locale.Language` identifier or Follow System |
| Audio fallback | None | A different supported language or None |
| Preferred subtitles | Follow System | A supported `Locale.Language` identifier or Follow System |
| Subtitle fallback | None | A different supported language or None |
| Prefer SDH | Follow System | Follow System, Prefer, or Do Not Prefer |
| Anime audio | Follow Preferred Audio | Follow Preferred Audio, Sub, or Dub |
| Subtitle appearance | Follow System | Follow System, preset, or Custom |
| Custom subtitle scale | 100% | 75% through 200%, in 5% steps |
| Subtitle background opacity | 0% | 0% through 100%, in 5% steps |
| Subtitle vertical position | System default | Higher, System Default, or Lower semantic positions |
| Subtitle horizontal margin | System default | 0% through 15% of video width, in 1% steps |

Text edge thickness, shadow, colors, font emphasis, and alignment use bounded enums or semantic choices rather than unconstrained numeric or arbitrary color input. Follow System continues to track later system preference changes.

### `LocalMediaStore`

Own growing local Watchlist, playback progress, remembered selections, and Upcoming inputs in SwiftData. Existing library/progress data is copied through a verified one-time migration:

1. Read and normalize the existing snapshot without modifying it.
2. Write the destination transaction.
3. Compare record counts and normalized values.
4. Mark migration complete only after verification.
5. Keep the previous snapshot intact if opening, writing, or verification fails.

Progress writes are coalesced rather than emitted from the current 250 ms playback observation loop. Pause, explicit stop, replacement playback, completion, and supported lifecycle transitions are forced flush boundaries.

### `AddonRegistry`

Own installed add-on order, enabled state, normalized manifest reference, last valid manifest, and declared capabilities. It coordinates installation and refresh through the hardened add-on client but never treats manifest text, artwork, URLs, headers, or capabilities as trusted.

Import/export uses a versioned Omnia document containing normalized manifest references, order, and enabled state only. It excludes credentials, resolver configuration, signed URLs, request headers, cached provider responses, and private playback data.

### `PlaybackPolicy`

Translate preferences into one platform-neutral playback policy used by both player adapters. The policy covers resume, source compatibility, remembered-source eligibility, autoplay, Up Next timing, intro behavior, language selection, and subtitle appearance capability.

Player adapters report their supported capabilities. Settings and playback omit behavior the active adapter cannot honor instead of pretending all formats and engines behave identically.

### `IntroDBClient`

Use the current read-only `GET /segments` contract with normalized IMDb ID, season, and episode query values. The client has an exact HTTPS origin, response and collection bounds, a short deadline, cooperative cancellation, content-type validation, and rate-limit handling. It does not submit data or require a credential.

Positive segment results are cached for seven days; empty results are cached for one day. Cache entries are keyed only by normalized episode identity and never contain media URLs or viewing progress. A failed lookup does not interrupt playback.

### `SubtitleAppearance`

Represent presets and custom values as a validated domain value. Adapters translate the value to their supported rendering path:

- Follow System is the default.
- Omnia-rendered external SRT/WebVTT subtitles receive the full supported custom style.
- libmpv text subtitles receive the supported corresponding options; image-based subtitles cannot be restyled.
- AVPlayer WebVTT receives supported `AVTextStyleRule` values.
- Embedded formats that cannot honor Omnia styling continue using native/system rendering.

Unsupported engine-specific controls, including a universal ASS override claim, are omitted. The UI explains the applicable rendering scope without exposing parser or engine jargon as a required choice.

### `UpcomingService`

Derive upcoming episodes from locally saved series and the existing metadata route. It does not infer remote tracking ownership or contact an excluded provider. The service filters by the configured look-ahead window and item limit, sorts chronologically with stable identity, retains usable cached entries during partial provider failure, and supports explicit retry.

## Settings Information Architecture

### Root areas

- **Library:** Progress & Watchlist, Upcoming, Add-ons, Catalogs, and existing applicable metadata configuration.
- **Playback:** Video Player and Subtitle Appearance.
- **Experience:** Existing appearance behavior.
- **Account/About:** Existing applicable Omnia account and attribution behavior, without a claim that viewing data synchronizes.

Empty service groups and rows for Trakt, AniList, or PublicMetaDB are removed rather than disabled.

### Add-ons

- Add an HTTPS manifest.
- Review installed add-ons with name, bounded description, version, and declared capabilities.
- Enable or disable an add-on.
- Expand capability detail without making the disclosure the row's primary action.
- Refresh, reorder, or remove through native actions with accessible alternatives to drag-only reordering.
- Configure request timeout from a bounded set.
- Export or import a sanitized add-on document.
- Confirm removal and disclose the affected catalogs/source availability before applying.

Loading, empty, partial-success, offline/error, retry, disabled, and destructive states remain scoped to the affected row or section.

### Progress & Watchlist

- Display storage ownership as **On This Device** without a provider selector.
- Configure the Continue Watching item limit.
- Enable or disable the local Watchlist action.
- Export or import local Watchlist and progress data.
- Clear watch history or Watchlist through separately confirmed actions.

Import presents valid, duplicate, conflicting, and rejected counts before one atomic apply. No import is partially written before confirmation.

### Upcoming

- Show or hide Upcoming on Home.
- Choose a bounded look-ahead duration.
- Choose a bounded item limit or No Limit.
- Explain that only locally saved series with known episode dates appear.

When no items qualify, the setting remains available and Home omits or explains the empty row according to context. Cached successes survive a partial metadata failure, accompanied by a concise Retry state.

### Video Player

- Show Skip Intro when an IntroDB segment applies.
- Auto-skip intro as a subordinate opt-in.
- Autoplay the next episode.
- Choose when the Up Next presentation appears.
- Remember the last source selection.
- Choose whether that selection remains eligible for 24 hours, 3 days, or 1 week.
- Optionally autoplay the first safe compatible source.
- Optionally start Continue Watching directly instead of opening Detail.
- Filter source results to compatible formats.
- Choose preferred and fallback audio languages.
- Choose preferred and fallback subtitle languages.
- Prefer SDH where available.
- Choose anime sub/dub preference.

External-player destination, per-media-type players, subtitle translation, Home preview autoplay, preview sound, and manual cache mode are absent.

### Subtitle Appearance

- Live preview against both light and dark representative video backgrounds.
- Follow System default.
- Standard, Boxed, Minimal, and High Contrast presets.
- Supported custom font size/scale and emphasis.
- Semantic text, edge, and background color choices.
- Supported edge style and background opacity.
- Vertical position, horizontal alignment, and horizontal margin.
- Reset to Defaults after native confirmation when a custom value would be lost.

Every custom value has a bounded range and readable accessibility value. Styling controls disabled by Follow System are grouped and explained, not merely dimmed without context.

## Platform Adaptation

### iPhone and iPad

Use the existing Settings destination with `NavigationStack`, `Form`, `Section`, `Toggle`, `Picker`, `Slider`, confirmation presentation, and SwiftUI file import/export. Validate portrait and landscape safe areas on iPhone and all iPad multitasking widths, pointer interaction, and keyboard navigation.

### Mac

Add the standard App-menu Settings command and Command-Comma Settings window using the same models and semantic sections. Remove a duplicate Mac sidebar Settings destination. Use platform-appropriate aligned forms, window sizing, focus, menu commands, and keyboard operation.

### Shared visual language

Use SF Symbols by name, semantic colors, system typography, system materials, and current SDK-supported controls. Apple Design Resources inform anatomy and platform scale; their artwork and measurements are not shipped or copied. The implementation targets the repository's Xcode 26.6 and deployment 26.5 baseline unless a separate reviewed SDK upgrade is approved.

## Runtime Flows

### Source and playback

1. Resolve candidates from enabled add-ons with the configured deadline.
2. Reject unsupported or unapproved candidates before ranking.
3. Prefer a nonexpired remembered source when it is still available and compatible.
4. Autoplay only after explicit opt-in and only when a validated compatible HTTPS source is available.
5. Otherwise present source selection with provenance and compatibility state.
6. Apply audio/subtitle preferences while preserving manual track selection.
7. Persist progress through the local store's coalesced writer.

### Skip Intro

1. When an episode has normalized IMDb, season, and episode identity, request IntroDB segments concurrently with playback startup.
2. Accept only bounded, valid intro ranges within the media duration.
3. Present Skip Intro only while the current position is inside or immediately approaching the applicable range.
4. Auto-skip only when explicitly enabled.
5. Cancellation, timeout, malformed data, missing identity, or no segment leaves ordinary playback unchanged.

Only normalized episode identifiers leave the device. Title text, progress, source/add-on details, media URL, request headers, subtitle text, and credentials are not sent.

### Up Next

Resolve the next local episode and show Up Next at the selected remaining-time threshold. Autoplay prefers the prior add-on and equivalent source characteristics. If no safe compatible match exists, return to source selection rather than silently choosing an incompatible or less-trusted path.

### Import

Decode into bounded temporary values, validate schema and every entry, classify results, and present a review summary. Apply the accepted operation in one transaction only after confirmation. Cancellation or failure leaves current state unchanged.

## Failure and Recovery

- Add-on refresh failure retains the last valid manifest and exposes inline Retry.
- Add-on removal cancels owned requests before confirmed deletion.
- IntroDB failure keeps playback uninterrupted and omits the unavailable skip action.
- Upcoming partial failure preserves successful cached items and labels the affected refresh state.
- Subtitle download or parse failure disables only that track; video and audio continue.
- A failed data migration leaves the existing snapshot authoritative and provides recovery guidance.
- A remembered source that expired, disappeared, or became incompatible is ignored without blocking source selection.
- Ordinary preference changes apply immediately and can be changed back. Subtitle Reset and destructive data operations require confirmation before applying.

## Security and Privacy

- Treat add-on manifests, payloads, subtitle files, media metadata, IntroDB responses, imports, redirects, and final media URLs as untrusted.
- Require HTTPS, exact normalized origins, content-type checks, request/response byte limits, collection/string/nesting limits, deadlines, cancellation, and bounded concurrency.
- Revalidate redirects before following and never forward credentials or add-on-supplied headers across origins.
- Keep user secrets in Keychain; preferences and exports never contain them.
- Redact URLs with queries, headers, subtitle dialogue, media identity/history, provider bodies, and credentials from diagnostics.
- No new dependency is required. Any later dependency proposal must pass the repository's provenance, license, lock, and supply-chain review.
- IntroDB use remains read-only and within its published fair-usage terms.

## Performance Policy

- Do not claim improved speed, memory, smoothness, or energy use without comparable Release evidence required by `PERFORMANCE.md`.
- Move parsing, import decoding, migration normalization, and subtitle preparation away from the main actor; publish only observable state on the main actor.
- Coalesce progress persistence and avoid deriving settings from the playback observation timer.
- Cache bounded IntroDB results and deduplicate identical in-flight lookups.
- Cancel add-on, subtitle, Upcoming, and IntroDB work when its owner disappears or inputs change.
- Add deterministic metric coverage for migration, large imports, and bounded subtitle parsing where the current test target supports it. These measurements are engineering evidence, not product performance claims.

## Accessibility Acceptance

- VoiceOver labels, values, hints, grouping, and reading order describe purpose and state without relying on symbols or color.
- Dynamic Type and larger Mac text settings do not clip critical state or make controls unreachable.
- Full Keyboard Access and visible focus cover every setting, reordering alternative, confirmation, and file flow.
- Pointer and context-menu actions have visible or keyboard-accessible alternatives.
- Reduce Motion removes nonessential transition motion; Reduce Transparency and Increase Contrast preserve hierarchy.
- Light/dark appearance and color-independent status are verified.
- Subtitle presets are evaluated on light and dark representative frames, and Follow System remains the default.
- Async updates never steal focus; destructive confirmations return focus predictably.

## Test Strategy

Implementation follows test-driven development. Automated coverage includes:

- typed preference defaults, validation, dependency rules, and persistence;
- migration success, verification failure, retry, interruption, and idempotency;
- progress coalescing and forced flush boundaries;
- Watchlist/progress/add-on export, hostile import, conflict classification, and atomicity;
- add-on HTTPS, exact-origin redirects, timeout, cancellation, content type, and response bounds;
- IntroDB valid, empty, malformed, oversized, slow, cancelled, cached, and rate-limited responses;
- source filtering, remembered-source expiry, autoplay safety, next-episode fallback, and incompatible candidates;
- preferred audio/subtitle selection through AVPlayer and libmpv adapters;
- bounded SRT/WebVTT parsing and subtitle-style normalization;
- Upcoming filtering, ordering, limits, empty state, cached partial failure, and retry;
- destructive-action presentation state and feature dependency behavior;
- absence of excluded providers, external-player controls, translation, Home preview controls, and manual cache controls.

Tests use deterministic fixtures and injected transports only. They do not call live add-ons, IntroDB, metadata providers, Supabase, or hosted services.

## Verification Matrix

Required local evidence:

1. macOS build.
2. Signed macOS XCTest suite.
3. Generic iOS Simulator build.
4. Focused iPhone and iPad Simulator smoke flows.
5. Local multi-track playback fixture covering audio, subtitles, seeking, intro skipping, next-episode behavior, and completion persistence.
6. Settings loading, empty, partial, offline/error, retry, disabled, import-review, and destructive states.
7. VoiceOver, Dynamic Type, Full Keyboard Access, pointer, Reduce Motion, Reduce Transparency, Increase Contrast, light/dark, iPhone orientation, iPad multitasking, and Mac resizing checks.
8. `git diff --check`, intended-path review, and filename-only secret scanning.

Physical-device, archive, signing-distribution, notarization, and comparative Instruments validation remain explicitly pending if this environment cannot perform them. Local code or test success never authorizes a hosted mutation.

## Completion Criteria

The overhaul is complete only when:

1. Every included setting changes verified behavior on at least one supported adapter and is omitted where inapplicable.
2. Excluded integrations and placeholder rows are absent from the affected settings experience.
3. The local data migration is verified and recoverable.
4. Add-on and local-data import/export are versioned, bounded, reviewed, and credential-free.
5. IntroDB lookup is read-only, bounded, cancellable, cached, privacy-minimal, and playback-safe on failure.
6. Playback, language selection, skip, Up Next, Upcoming, and subtitle appearance satisfy their automated and platform-specific checks.
7. Every applicable UI state and accessibility requirement passes or is reported with exact remaining device evidence.
8. Supported builds/tests pass, `git diff --check` passes, and the final diff contains no unrelated cleanup or hosted mutation.

## Primary References

- Apple, [Apple Design Resources](https://developer.apple.com/design/resources/)
- Apple, [Settings](https://developer.apple.com/design/human-interface-guidelines/settings)
- Apple, [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- Apple, [Playing video](https://developer.apple.com/design/human-interface-guidelines/playing-video)
- Apple, [`Form`](https://developer.apple.com/documentation/swiftui/form)
- Apple, [Selecting subtitles and alternative audio tracks](https://developer.apple.com/documentation/avfoundation/selecting-subtitles-and-alternative-audio-tracks)
- Apple, [`AVPlayerMediaSelectionCriteria`](https://developer.apple.com/documentation/avfoundation/avplayermediaselectioncriteria)
- Apple, [`AVPlayer.appliesMediaSelectionCriteriaAutomatically`](https://developer.apple.com/documentation/avfoundation/avplayer/appliesmediaselectioncriteriaautomatically)
- Apple, [`AVPlayerItem.textStyleRules`](https://developer.apple.com/documentation/avfoundation/avplayeritem/textstylerules)
- Apple, [`AVTextStyleRule`](https://developer.apple.com/documentation/avfoundation/avtextstylerule)
- Apple, [Media Accessibility](https://developer.apple.com/documentation/mediaaccessibility)
- Apple, [SwiftUI file import and export](https://developer.apple.com/documentation/swiftui/view-file-presentation)
- IntroDB, [API documentation](https://introdb.app/docs/api)
- IntroDB, [Terms and policy](https://introdb.app/docs/terms)
- Stremio, [add-on protocol](https://github.com/Stremio/stremio-addon-sdk/blob/master/docs/protocol.md)
- Stremio, [stream response contract](https://github.com/Stremio/stremio-addon-sdk/blob/master/docs/api/responses/stream.md)
- Omnia, [`DESIGN.md`](../../../DESIGN.md)
- Omnia, [`SECURITY.md`](../../../SECURITY.md)
- Omnia, [`PERFORMANCE.md`](../../../PERFORMANCE.md)
- Omnia, [`INFRASTRUCTURE.md`](../../../INFRASTRUCTURE.md)
