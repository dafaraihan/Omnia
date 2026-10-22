# Fresh Sign-out and Onboarding Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline, task by task. Repository policy forbids automated test infrastructure.

**Goal:** Return successful sign-out to a clean welcome flow and use production screens in onboarding.
**Architecture:** Explicit local reset operations coordinated after Auth sign-out; account-bound encrypted credential recovery remains separate. Shared environment preview mode suppresses production-screen side effects without duplicating presentation.
**Tech Stack:** SwiftUI, Observation, existing Keychain and local persistence.
**Spec:** ../specs/2026-10-22-sign-out-onboarding-design.md (approved by user).

## Global Constraints

- Preserve cloud data; never invoke profile deletion APIs during reset.
- Preserve encrypted unsynced credential recovery for its owning account.
- No tests, dependencies, custom DerivedData, commits, or hosted deployment.

## Review Focus

- Late async responses must not restore signed-out state.
- Failed Auth sign-out must not clear ordinary profile data.
- Relaunch must remain in welcome onboarding.
- Preview must not start playback, consume transitions, or mutate preferences.
- Missing discovery data and reduced-motion settings remain usable.

### Task 1: Local sign-out reset

- [x] Add explicit local detachment/reset methods to ProfileStore, ProfileDataSync and OmniaStore.
- [x] Guard in-flight profile sync across identity changes and suspend change recording during reset.
- [x] Coordinate successful sign-out cleanup through OmniaApp; clear active credentials and guest snapshot, stop playback, reset settings/add-ons/plugins/collections and onboarding/navigation.
- [x] Update confirmation copy to distinguish local reset from cloud deletion and pending encrypted recovery.
- [x] Inspect failure and stale-response paths; build macOS.

### Task 2: Production onboarding preview

- [x] Add a shared read-only preview environment flag, suppressing production Home/detail side effects.
- [x] Replace AppPreview mock with scaled real HomeView and MediaDetailView, manual screen selection and discovery fallback/retry.
- [x] Adapt onboarding feature layout to available width and remove continuous preview movement.
- [x] Check whitespace, build macOS, inspect current app products and attempt native UI checks; record any checks unavailable.

Validation record: [evidence and pending runtime checks](../../research/sign-out-onboarding-validation-2026-10-22.md). Manual visual and signed-in flow checks remain pending because Computer Use screen capture failed.
