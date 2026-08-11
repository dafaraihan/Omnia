# MDBList Community Rating Marks Design

**Date:** 2026-08-11
**Status:** Approved for implementation
**Scope:** Provider artwork shown by the existing MDBList ratings feature

## Decision

Omnia will replace the text-only presentation of known MDBList rating providers with pinned transparent brand artwork. The user explicitly accepted the trademark and licensing risk of community or otherwise unapproved assets after reviewing the official restrictions. This decision does not change how ratings are requested, decoded, cached, ordered, enabled, or disabled.

Assets are bundled in `Assets.xcassets`; Omnia must not download provider artwork at runtime and must not add an icon-package dependency. Every asset remains decorative to accessibility, while the existing provider name and formatted value remain in the combined VoiceOver label.

## Source Matrix

| MDBList source | Artwork | Source | Rendering |
| --- | --- | --- | --- |
| `imdb` | IMDb glyph | Simple Icons 16.21.0, sourced from IMDb Brand | Original IMDb yellow |
| `tmdb` | Existing TMDB vector | Official TMDB logo package | Existing original gradient |
| `tomatoes` | Fresh tomato or rotten splat | Score artwork delivered by the Rotten Tomatoes licensing page | Select at the 60% threshold |
| `metacritic` | Metacritic glyph | Metacritic's delivered transparent favicon SVG | Preserve the source artwork |
| `trakt` | Trakt glyph | Trakt-delivered `favicon.svg` | Original Trakt purple |
| `letterboxd` | Letterboxd three-dot decal | Official Letterboxd transparent RGB SVG | Original green, orange, and blue |
| `popcorn` | Hot popcorn or stale popcorn | Score artwork delivered by the Rotten Tomatoes licensing page | Select at the 60% threshold |
| `myanimelist` | MyAnimeList glyph | MyAnimeList-delivered `anime-logo-mobile.svg` | Original MyAnimeList blue |
| `rogerebert` | Roger Ebert wordmark | Pinned Brandfetch community vector | Original source color |
| MDBList aggregate | MDBList glyph | MDBList-delivered `safari-pinned-tab.svg` | Original MDBList blue |

Simple Icons is distributed under CC0, but its own disclaimer states that CC0 does not grant third-party trademark rights. First-party file delivery likewise does not override a provider's usage terms. Rotten Tomatoes requires proposal approval, attribution, and title links; Letterboxd restricts its marks to specified link contexts; RogerEbert.com prohibits mark use without prior consent. The user selected these assets despite those restrictions. Omnia's provenance document must record the source URL, package version where applicable, file SHA-256, source color, and this explicit override.

Unknown future providers continue to use their readable text fallback because Omnia cannot safely infer a matching brand from an arbitrary MDBList source identifier.

## Presentation

### Title details

Each known source renders as its transparent mark followed by the formatted score. Artwork uses original rendering mode, aspect-fit sizing, and no background capsule, tint, shadow, or geometric alteration. Marks share a visual height while retaining intrinsic width. Ratings continue to wrap as intact provider/value pairs immediately below the title facts.

Rotten Tomatoes artwork is value-dependent:

- `tomatoes` values from 60 through 100 use the fresh tomato; values below 60 use the rotten splat.
- `popcorn` values from 60 through 100 use the hot popcorn; values below 60 use the stale popcorn.

The threshold is based only on the bounded numeric value returned by MDBList. Omnia must not infer Certified Fresh or Verified Hot status.

### Settings

Every known provider row renders its default brand mark followed by the full provider name. Rotten Tomatoes settings use the positive tomato and positive popcorn variants because no title score exists in that context. Toggles and the always-visible MDBList aggregate row retain the existing native Form behavior.

### Accessibility and Apple-platform behavior

Artwork is hidden from VoiceOver and never carries the provider identity alone. The combined accessibility label continues to announce the full provider name, whether the value is a rating or aggregate score, and the spoken numeric value. The layout must support Dynamic Type, Increase Contrast, Reduce Transparency, keyboard focus, pointer interaction, dark/light settings appearances, iPhone safe areas, iPad multitasking widths, and resizable Mac windows.

## Architecture

`MDBListRatingProviderDescriptor` will describe a default asset and, where needed, value-dependent variants. Asset selection belongs in the provider registry as a deterministic function of provider ID and value; SwiftUI views consume the selected name without encoding provider-specific thresholds.

The presentation model carries the selected asset name for each returned value. Settings rows carry the default asset name. This preserves the existing boundaries:

- decoding validates untrusted MDBList data;
- the provider registry owns identity, order, formatting, and artwork selection;
- presentation applies preferences and produces display-ready items;
- SwiftUI renders the supplied asset and accessibility text.

## Failure and Fallback Behavior

Missing or invalid packaged artwork must not hide a rating. A descriptor without an asset uses the full provider name. Invalid rating values remain rejected by the existing validation rather than being clamped to choose an icon. Loading, empty, authentication, rate-limit, retry, cancellation, cache, and provider-preference behavior remain unchanged.

## Verification

Automated coverage must prove:

- every known provider and the MDBList aggregate resolve to the intended bundled asset;
- Rotten Tomatoes and Popcornmeter choose the correct asset immediately below and at the 60% boundary;
- unknown providers keep the text fallback;
- settings use stable default marks;
- every bundled mark has a provenance record and a valid HTTPS source;
- ratings remain available when artwork is absent;
- accessibility labels contain the full provider name and formatted value.

Verification also requires the complete macOS XCTest suite, macOS build, generic iOS Simulator build, asset-catalog compilation, SVG/XML validation, `git diff --check`, and visual smoke checks at compact and wide detail widths.

## Out of Scope

- Runtime icon downloads or CDN dependencies
- A general-purpose brand-icon framework
- Logos for arbitrary future MDBList source identifiers
- Provider title-page linking or direct provider API integrations
- Certified Fresh or Verified Hot inference
- Hosted configuration or deployment changes
