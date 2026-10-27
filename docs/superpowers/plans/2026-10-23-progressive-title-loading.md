# Progressive Title Loading Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline. Repository policy prohibits automated test infrastructure.

**Goal:** Keep visible content while starting ratings, logos and enrichment concurrently and stabilizing Home actions.
**Architecture:** Reuse existing request caches. Ratings request identities use actual lookup routes, with title-scoped presentation. Home enriches add-on titles concurrently and prewarms only its next hero; no new disk cache or credentials boundary.
**Tech Stack:** Existing SwiftUI, structured concurrency, metadata/artwork caches.
**Spec:** ../specs/2026-10-23-coordinated-title-presentation-design.md, amended by user choice to keep content visible while loading.

## Global Constraints

- Preserve content visibility, add-on precedence, integration toggles and preview side-effect suppression.
- Preserve Keychain helper edits; no backend changes, dependencies, tests, commits, push or release.
- No instant-network or measured-performance claims.

## Review Focus

- Ratings from the previous title must never appear under a new hero.
- Identifier enrichment must not restart the same effective rating route.
- Disabled enrichment and hidden/preview Home must not start speculative work.
- Next-title preparation must not publish visible metadata or preference changes.
- Missing episode data must retain the current button geometry with a disabled watch action.

## Tasks

- [x] Share lookup-route identity between client and view request keys; retain same-title loaded ratings during route enrichment.
- [x] Start Home ratings from current catalog IDs; enrich add-on heroes concurrently while retaining owning add-on fields.
- [x] Prewarm only next hero metadata/ratings/logo through existing caches; stop further stages on cancellation.
- [x] Use a fixed watch-control slot for Home, including pending/unavailable episode information.
- [x] Build signed canonical macOS app; check whitespace and focused review. Attempt native UI checks and record unavailable runtime/performance evidence.

Final signed macOS build and whitespace checks passed. Focused reviewer confirmed the final targeted fixes. Visual runtime and Release Instruments checks remain pending; see [validation](../../research/progressive-title-loading-validation-2026-10-23.md).
