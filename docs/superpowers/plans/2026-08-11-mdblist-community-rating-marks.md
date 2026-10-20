# MDBList Community Rating Marks Implementation Plan

> **Automated-validation policy:** Follow the repository-root `AGENTS.md`. Instructions below that call for automated test targets, suites, fixtures, or scripts are historical and superseded; use builds, static checks, and focused manual evidence instead.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace text-only known MDBList rating sources with bundled transparent provider marks, including value-dependent Rotten Tomatoes artwork, without changing rating retrieval or preference behavior.

**Architecture:** Keep provider identity and asset selection in `MDBListRatingProviderRegistry`, pass the selected asset through display-ready presentation models, and let SwiftUI remain provider-agnostic. Vendor a fixed, provenance-recorded SVG set in the asset catalog; never fetch artwork at runtime and keep text fallback for unknown sources.

**Tech Stack:** Swift 6, SwiftUI, XCTest, Xcode asset catalogs, SVG, macOS/iOS app targets.

## Global Constraints

- Do not add a package dependency or runtime icon/CDN request.
- Preserve all existing MDBList API, cache, loading, preference, ordering, and aggregate behavior.
- Every known source and the MDBList aggregate receives a bundled transparent mark; unknown sources remain text.
- Use original rendering mode, preserve SVG geometry/aspect ratio, and do not tint artwork in SwiftUI.
- `tomatoes` and `popcorn` select negative artwork below 60 and positive artwork at 60 or above.
- Never infer Certified Fresh or Verified Hot status.
- Artwork is decorative; VoiceOver continues to announce the full provider name and formatted value.
- Record HTTPS source, pinned version where applicable, SHA-256, and the user-approved trademark override.
- Preserve unrelated working-tree and staged changes. Do not deploy or mutate hosted services.

---

## File Map

- `Omnia/Domain/Metadata/MDBListRatingProvider.swift`: provider descriptors, deterministic value-based asset selection, aggregate mark, provenance records.
- `Omnia/Features/Library/MDBListRatingsPresentation.swift`: display-ready selected asset names for title details and Settings.
- `Omnia/Features/Library/MediaDetailView.swift`: provider-agnostic mark rendering at intrinsic aspect ratio.
- `Omnia/Features/Settings/MetadataSettingsView.swift`: native Settings row rendering with mark plus full name.
- `Omnia/Assets.xcassets/RatingProviderMarks/`: pinned transparent SVG assets and image-set manifests.
- `docs/provider-assets/mdblist-rating-provider-marks.md`: source URLs, hashes, colors, restrictions, and explicit override.
- `OmniaTests/MDBListRatingProviderTests.swift`: registry and threshold behavior.
- `OmniaTests/MDBListRatingsPresentationTests.swift`: selected assets, aggregate, settings defaults, fallback, and accessibility.
- `OmniaTests/AboutSettingsTests.swift`: provenance/registry completeness.

### Task 1: Model deterministic provider artwork

**Files:**
- Modify: `OmniaTests/MDBListRatingProviderTests.swift`
- Modify: `Omnia/Domain/Metadata/MDBListRatingProvider.swift`

**Interfaces:**
- Produces: `MDBListRatingProviderDescriptor.defaultAssetName: String?`
- Produces: `MDBListRatingProviderDescriptor.negativeAssetName: String?`
- Produces: `MDBListRatingProviderDescriptor.negativeBelow: Double?`
- Produces: `MDBListRatingProviderRegistry.assetName(for:value:) -> String?`
- Produces: `MDBListRatingProviderRegistry.aggregateAssetName: String`

- [ ] **Step 1: Add failing registry and threshold tests**

Add these focused assertions to `MDBListRatingProviderTests`:

```swift
func testEveryKnownProviderHasDefaultArtworkAndUnknownProviderDoesNot() throws {
    XCTAssertTrue(
        MDBListRatingProviderRegistry.knownDescriptors.allSatisfy {
            $0.defaultAssetName != nil
        }
    )
    let unknown = try XCTUnwrap(MDBListRatingProviderID("future_source"))
    XCTAssertNil(MDBListRatingProviderRegistry.descriptor(for: unknown).defaultAssetName)
    XCTAssertEqual(MDBListRatingProviderRegistry.aggregateAssetName, "RatingMDBListMark")
}

func testRottenTomatoesArtworkChangesAtSixtyPercentBoundary() {
    XCTAssertEqual(
        MDBListRatingProviderRegistry.assetName(for: .rottenTomatoes, value: 59.9),
        "RatingRottenTomatoesRottenMark"
    )
    XCTAssertEqual(
        MDBListRatingProviderRegistry.assetName(for: .rottenTomatoes, value: 60),
        "RatingRottenTomatoesFreshMark"
    )
    XCTAssertEqual(
        MDBListRatingProviderRegistry.assetName(for: .rottenTomatoesAudience, value: 59.9),
        "RatingRottenTomatoesAudienceStaleMark"
    )
    XCTAssertEqual(
        MDBListRatingProviderRegistry.assetName(for: .rottenTomatoesAudience, value: 60),
        "RatingRottenTomatoesAudienceHotMark"
    )
}

func testInvalidValuesCannotSelectArtwork() {
    XCTAssertNil(MDBListRatingProviderRegistry.assetName(for: .imdb, value: -1))
    XCTAssertNil(MDBListRatingProviderRegistry.assetName(for: .imdb, value: .infinity))
}
```

- [ ] **Step 2: Run the provider tests and verify the new API fails to compile**

Run:

```sh
[Automated validation command removed by repository policy.]
```

Expected: FAIL because `defaultAssetName`, `assetName(for:value:)`, and `aggregateAssetName` do not exist.

- [ ] **Step 3: Replace approval-only asset metadata with display metadata**

Change the descriptor to:

```swift
nonisolated struct MDBListRatingProviderDescriptor: Identifiable, Hashable, Sendable {
    let id: MDBListRatingProviderID
    let displayName: String
    let order: Int?
    let valueFormat: MDBListRatingValueFormat
    let defaultAssetName: String?
    let negativeAssetName: String?
    let negativeBelow: Double?
}
```

Configure known providers with these exact names:

```swift
descriptor(.imdb, "IMDb", order: 0, assetName: "RatingIMDbMark")
descriptor(.tmdb, "TMDB", order: 1, assetName: "RatingTMDBMark")
descriptor(
    .rottenTomatoes,
    "Rotten Tomatoes",
    order: 2,
    format: .percentage,
    assetName: "RatingRottenTomatoesFreshMark",
    negativeAssetName: "RatingRottenTomatoesRottenMark",
    negativeBelow: 60
)
descriptor(.metacritic, "Metacritic", order: 3, assetName: "RatingMetacriticMark")
descriptor(.trakt, "Trakt", order: 4, assetName: "RatingTraktMark")
descriptor(.letterboxd, "Letterboxd", order: 5, assetName: "RatingLetterboxdMark")
descriptor(
    .rottenTomatoesAudience,
    "Rotten Tomatoes Audience",
    order: 6,
    format: .percentage,
    assetName: "RatingRottenTomatoesAudienceHotMark",
    negativeAssetName: "RatingRottenTomatoesAudienceStaleMark",
    negativeBelow: 60
)
descriptor(.myAnimeList, "MyAnimeList", order: 7, assetName: "RatingMyAnimeListMark")
descriptor(.rogerEbert, "Roger Ebert", order: 8, assetName: "RatingRogerEbertMark")
```

Add deterministic selection and validate before selecting:

```swift
static let aggregateAssetName = "RatingMDBListMark"

static func assetName(for id: MDBListRatingProviderID, value: Double) -> String? {
    guard validatedValue(value) != nil else { return nil }
    let descriptor = descriptor(for: id)
    if let threshold = descriptor.negativeBelow,
       value < threshold,
       let negativeAssetName = descriptor.negativeAssetName {
        return negativeAssetName
    }
    return descriptor.defaultAssetName
}
```

Unknown descriptors set all three artwork properties to `nil`.

- [ ] **Step 4: Run provider tests and verify they pass**

Run the Step 2 command. Expected: PASS.

- [ ] **Step 5: Commit the registry change**

```sh
git add Omnia/Domain/Metadata/MDBListRatingProvider.swift \
  OmniaTests/MDBListRatingProviderTests.swift
git commit -m "Select MDBList rating marks"
```

### Task 2: Carry selected artwork through presentation and UI

**Files:**
- Modify: `OmniaTests/MDBListRatingsPresentationTests.swift`
- Modify: `Omnia/Features/Library/MDBListRatingsPresentation.swift`
- Modify: `Omnia/Features/Library/MediaDetailView.swift`
- Modify: `Omnia/Features/Settings/MetadataSettingsView.swift`

**Interfaces:**
- Consumes: `MDBListRatingProviderRegistry.assetName(for:value:)`
- Consumes: `MDBListRatingProviderRegistry.aggregateAssetName`
- Produces: `MDBListRatingPresentationItem.assetName: String?`
- Produces: `MDBListRatingSettingsRow.assetName: String?`

- [ ] **Step 1: Add failing presentation tests**

Add exact asset assertions:

```swift
func testPresentationSelectsValueDependentAndAggregateArtwork() throws {
    let presentation = MDBListRatingsPresentation(
        response: MDBListTitleRatings(
            score: 8.2,
            ratings: [
                MDBListRating(providerID: .imdb, value: 7.4),
                MDBListRating(providerID: .rottenTomatoes, value: 59),
                MDBListRating(providerID: .rottenTomatoesAudience, value: 60)
            ]
        ),
        preferences: .default
    )

    XCTAssertEqual(
        presentation.items.map(\.assetName),
        [
            "RatingIMDbMark",
            "RatingRottenTomatoesRottenMark",
            "RatingRottenTomatoesAudienceHotMark",
            "RatingMDBListMark"
        ]
    )
}

func testUnknownProviderKeepsTextFallback() throws {
    let unknown = try XCTUnwrap(MDBListRatingProviderID("future_source"))
    let presentation = MDBListRatingsPresentation(
        response: MDBListTitleRatings(ratings: [
            MDBListRating(providerID: unknown, value: 8)
        ]),
        preferences: .default
    )

    XCTAssertNil(presentation.items.first?.assetName)
    XCTAssertEqual(presentation.items.first?.displayName, "Future Source")
}

func testSettingsUseDefaultArtworkForEveryKnownSourceAndAggregate() {
    let rows = MDBListRatingSettingsModel.rows(preferences: .default)
    XCTAssertEqual(
        rows.first { $0.id == "tomatoes" }?.assetName,
        "RatingRottenTomatoesFreshMark"
    )
    XCTAssertEqual(
        rows.first { $0.id == "popcorn" }?.assetName,
        "RatingRottenTomatoesAudienceHotMark"
    )
    XCTAssertEqual(rows.last?.assetName, "RatingMDBListMark")
}
```

- [ ] **Step 2: Run focused presentation tests and verify failure**

Run:

```sh
[Automated validation command removed by repository policy.]
```

Expected: FAIL because the presentation models still expose `approvedAssetName` and do not select value-dependent or aggregate assets.

- [ ] **Step 3: Rename the presentation property and select assets from values**

Use this shape in both presentation item and Settings row:

```swift
let assetName: String?
```

For each rating item assign:

```swift
assetName: MDBListRatingProviderRegistry.assetName(
    for: descriptor.id,
    value: rating.value
)
```

For the aggregate and Settings aggregate row assign:

```swift
assetName: MDBListRatingProviderRegistry.aggregateAssetName
```

For provider Settings rows use `descriptor.defaultAssetName`. Preserve `displayName` so unknown-provider text fallback and accessibility never depend on artwork.

- [ ] **Step 4: Make SwiftUI consume `assetName` without provider branches**

In both views, keep `renderingMode(.original)` and replace fixed-width distortion with height-led aspect fit:

```swift
if let assetName = item.assetName {
    Image(assetName)
        .resizable()
        .renderingMode(.original)
        .scaledToFit()
        .frame(height: 14)
        .accessibilityHidden(true)
} else {
    Text(item.displayName)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white.opacity(0.8))
}
```

Settings uses a 20-point image height, a 72-point maximum width, and always retains the adjacent full provider name. Do not add a capsule, background, tint, or provider switch in either SwiftUI view.

- [ ] **Step 5: Run focused provider and presentation tests**

```sh
[Automated validation command removed by repository policy.]
```

Expected: PASS, including existing accessibility, ordering, toggles, unknown fallback, and aggregate tests.

- [ ] **Step 6: Commit presentation and UI wiring**

```sh
git add Omnia/Features/Library/MDBListRatingsPresentation.swift \
  Omnia/Features/Library/MediaDetailView.swift \
  Omnia/Features/Settings/MetadataSettingsView.swift \
  OmniaTests/MDBListRatingsPresentationTests.swift
git commit -m "Render MDBList provider marks"
```

### Task 3: Vendor transparent SVG assets and provenance

**Files:**
- Create: `Omnia/Assets.xcassets/RatingProviderMarks/RatingIMDbMark.imageset/`
- Create: `Omnia/Assets.xcassets/RatingProviderMarks/RatingRottenTomatoesFreshMark.imageset/`
- Create: `Omnia/Assets.xcassets/RatingProviderMarks/RatingRottenTomatoesRottenMark.imageset/`
- Create: `Omnia/Assets.xcassets/RatingProviderMarks/RatingMetacriticMark.imageset/`
- Create: `Omnia/Assets.xcassets/RatingProviderMarks/RatingTraktMark.imageset/`
- Create: `Omnia/Assets.xcassets/RatingProviderMarks/RatingLetterboxdMark.imageset/`
- Create: `Omnia/Assets.xcassets/RatingProviderMarks/RatingRottenTomatoesAudienceHotMark.imageset/`
- Create: `Omnia/Assets.xcassets/RatingProviderMarks/RatingRottenTomatoesAudienceStaleMark.imageset/`
- Create: `Omnia/Assets.xcassets/RatingProviderMarks/RatingMyAnimeListMark.imageset/`
- Create: `Omnia/Assets.xcassets/RatingProviderMarks/RatingRogerEbertMark.imageset/`
- Create: `Omnia/Assets.xcassets/RatingProviderMarks/RatingMDBListMark.imageset/`
- Modify: `Omnia/Domain/Metadata/MDBListRatingProvider.swift`
- Modify: `docs/provider-assets/mdblist-rating-provider-marks.md`
- Modify: `OmniaTests/AboutSettingsTests.swift`

**Interfaces:**
- Consumes: exact asset names established in Tasks 1 and 2.
- Produces: `MDBListRatingProviderProvenanceRecord.assetNames: Set<String>`.

- [ ] **Step 1: Add a failing provenance completeness test**

Replace approval-only comparison with the full registry set:

```swift
func testEveryRatingAssetIsInReviewedProvenanceMatrix() {
    let reviewed = Set(
        MDBListRatingProviderProvenance.records.flatMap(\.assetNames)
    )
    let registry = Set(
        MDBListRatingProviderRegistry.knownDescriptors.flatMap { descriptor in
            [descriptor.defaultAssetName, descriptor.negativeAssetName].compactMap { $0 }
        }
    ).union([MDBListRatingProviderRegistry.aggregateAssetName])

    XCTAssertEqual(registry, reviewed)
}
```

- [ ] **Step 2: Run About/provider tests and verify failure**

```sh
[Automated validation command removed by repository policy.]
```

Expected: FAIL because provenance records still expose only `approvedAssetName` and cover only TMDB.

- [ ] **Step 3: Acquire and pin the exact source files**

Use these HTTPS sources and retain their geometry:

```text
IMDb: https://cdn.jsdelivr.net/npm/simple-icons@16.21.0/icons/imdb.svg
TMDB: existing RatingTMDBMark asset
Rotten Tomatoes: SVG paths embedded by score-icon-critics and score-icon-audience in
  https://www.rottentomatoes.com/assets/pizza-pie/javascripts/bundles/roma/default.d8b650ef4ad.js
Metacritic: https://www.metacritic.com/a/img/favicon.svg
Trakt: https://trakt.tv/favicon.svg
Letterboxd: https://a.ltrbxd.com/logos/letterboxd-decal-dots-neg-rgb.svg
MyAnimeList: https://myanimelist.net/wrap-up/anime-logo-mobile.svg
Roger Ebert: https://brandfetch.com/rogerebert.com
MDBList: https://mdblist.com/static/safari-pinned-tab.svg
```

For the Simple Icons IMDb file, add only the package metadata color `#F5C518` to the root SVG fill; do not change its path. Extract the four Rotten Tomatoes paths exactly from the delivered custom-element source and preserve their original fills. Do not create a substitute Roger Ebert mark: use the downloaded community wordmark chosen in the approved specification.

For every image set use this manifest shape, substituting its SVG filename:

```json
{
  "images": [
    {
      "filename": "provider.svg",
      "idiom": "universal"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  },
  "properties": {
    "preserves-vector-representation": true
  }
}
```

- [ ] **Step 4: Validate every SVG and calculate hashes**

```sh
find Omnia/Assets.xcassets/RatingProviderMarks -name '*.svg' -print0 | \
  xargs -0 -n1 xmllint --noout
find Omnia/Assets.xcassets/RatingProviderMarks -name '*.svg' -print0 | \
  sort -z | xargs -0 shasum -a 256
find Omnia/Assets.xcassets/RatingProviderMarks -name 'Contents.json' -print0 | \
  xargs -0 -n1 jq empty
```

Expected: every command exits 0. Copy the hash output into the provenance document beside the matching source URL.

- [ ] **Step 5: Expand the provenance model to all packaged assets**

Change the record field to:

```swift
let assetNames: Set<String>
```

Each source record lists its exact image-set names. Rotten Tomatoes owns four names; every other known source owns one. Retain HTTPS validation and About resource IDs. Document that the assets are bundled under the user-approved trademark override rather than describing them as licensed or approved.

- [ ] **Step 6: Run asset/provenance tests and compile the asset catalog**

```sh
[Automated validation command removed by repository policy.]
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' build
```

Expected: tests PASS and the asset catalog compiles without missing-image warnings.

- [ ] **Step 7: Commit assets and provenance**

```sh
git add Omnia/Assets.xcassets/RatingProviderMarks \
  Omnia/Domain/Metadata/MDBListRatingProvider.swift \
  OmniaTests/AboutSettingsTests.swift \
  docs/provider-assets/mdblist-rating-provider-marks.md
git commit -m "Bundle MDBList rating provider marks"
```

### Task 4: Visual and repository verification

**Files:**
- Modify only if verification exposes a defect in files already in scope.

**Interfaces:**
- Consumes: the complete implementation from Tasks 1–3.
- Produces: fresh completion evidence for supported builds and the full test suite.

- [ ] **Step 1: Run the complete macOS XCTest suite**

```sh
[Automated validation command removed by repository policy.]
```

Expected: 0 failed tests.

- [ ] **Step 2: Build both supported platform families**

```sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' build
xcodebuild -project Omnia.xcodeproj -scheme Omnia \
  -destination 'generic/platform=iOS Simulator' build
```

Expected: both commands exit 0.

- [ ] **Step 3: Perform visual smoke checks**

Open a detail fixture that returns all known providers and verify on a compact iPhone width, iPad split-view width, and resizable Mac window:

- every known source uses transparent artwork;
- ratings remain immediately below title facts and wrap without clipping;
- IMDb, TMDB, Metacritic, Trakt, Letterboxd, MyAnimeList, Roger Ebert, and MDBList retain recognizable proportions;
- `tomatoes` at 59/60 and `popcorn` at 59/60 select the correct marks;
- Settings shows mark plus full provider name and native toggles;
- VoiceOver announces provider names and values, not asset filenames;
- unknown sources remain readable text.

- [ ] **Step 4: Run final hygiene checks**

```sh
git diff --check
git status --short
git diff --cached --name-only
```

Expected: no whitespace errors; only intended implementation paths changed; the six pre-existing staged asset manifests remain staged and untouched.

- [ ] **Step 5: Commit only verification-driven corrections, if any**

```sh
git add Omnia/Domain/Metadata/MDBListRatingProvider.swift \
  Omnia/Features/Library/MDBListRatingsPresentation.swift \
  Omnia/Features/Library/MediaDetailView.swift \
  Omnia/Features/Settings/MetadataSettingsView.swift \
  Omnia/Assets.xcassets/RatingProviderMarks \
  OmniaTests/MDBListRatingProviderTests.swift \
  OmniaTests/MDBListRatingsPresentationTests.swift \
  OmniaTests/AboutSettingsTests.swift \
  docs/provider-assets/mdblist-rating-provider-marks.md
git commit -m "Polish MDBList rating marks"
```

Skip this commit when verification requires no correction.
