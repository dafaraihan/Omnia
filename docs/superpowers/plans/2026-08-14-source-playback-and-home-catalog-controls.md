# Source Playback and Home Catalog Controls Implementation Plan

> **Automated-validation policy:** Follow the repository-root `AGENTS.md`. Instructions below that call for automated test targets, suites, fixtures, or scripts are historical and superseded; use builds, static checks, and focused manual evidence instead.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make configured MediaFusion results recoverable, make Torrentio locally playable in macOS Debug development, expose add-on removal, and provide per-shelf Home controls.

**Architecture:** Preserve source results per add-on and retry only the failed batch. Reuse the existing Objective-C++ torrent bridge with the documented Homebrew Debug dependency path, and keep UI preferences in small deterministic domain models consumed by SwiftUI settings and Home.

**Tech Stack:** Swift 6, SwiftUI, Observation, XCTest, Objective-C++, libtorrent 2.x, OpenSSL 3, libmpv, Xcode build settings, shell staging scripts.

## Global Constraints

- macOS is the only local-torrent target; iPhone and iPad must continue to compile with torrent actions disabled.
- Preserve bounded HTTPS policies and never persist or print private add-on endpoints or stream capabilities.
- Release continues to require `OMNIA_NATIVE_PLAYBACK_ROOT` and the strict native artifact gate.
- No hosted Supabase mutation or deployment.
- Preserve all unrelated working-tree changes and do not stage or commit without a separate user request.

---

### Task 1: Per-add-on source resolution and retry

**Files:**
- Modify: `Omnia/Domain/Playback/PlaybackSource.swift`
- Modify: `Omnia/Features/Playback/PlaybackViews.swift`
- Test: `OmniaTests/StremioAddonClientTests.swift`
- Test: `OmniaTests/PlaybackSourcePresentationTests.swift`

**Interfaces:**
- Consumes: `StremioAddonClient.fetchStreamCandidates(from:mediaTypes:identifiers:)`.
- Produces: `AddonSourceResolution` with `addonID`, `candidates`, and an optional redacted failure; `PlaybackSourceResolution.addonResults`; merge-by-add-on retry behavior.

- [ ] **Step 1: Write failing tests** proving one malformed/failed add-on cannot erase another add-on's candidates, and replacing one add-on result preserves every other batch.
[Historical automated-validation command removed by repository policy.]
- [ ] **Step 3: Implement** the minimal result value, ordered flattening, replacement helper, status row, and retry task. Keep error strings redacted and reuse the existing bounded client.
- [ ] **Step 4: Rerun the focused command** and require zero failures.

### Task 2: macOS Debug local torrent engine

**Files:**
- Modify: `Omnia.xcodeproj/project.pbxproj`
- Modify: `Omnia/Platform/Playback/stage-native-playback.sh`
- Modify: `README.md`
[Historical automated-validation reference removed by repository policy.]

**Interfaces:**
- Consumes: Homebrew Debug headers/libraries for libmpv, libtorrent-rasterbar, and OpenSSL 3.
- Produces: a macOS Debug app where `OMLocalTorrentEngine.isAvailable == true`; Release staging behavior is unchanged.

- [ ] **Step 1: Extend the staging contract test** so macOS Debug requires and copies the local torrent/OpenSSL runtime closure while iOS exits without native staging.
[Historical automated-validation reference removed by repository policy.]
- [ ] **Step 3: Install the already-reviewed development formula if missing** with `brew install libtorrent-rasterbar`, then add macOS Debug compiler definitions, header/library search paths, linker inputs, and known runtime-copy rules. Do not alter Release’s strict manifest path.
- [ ] **Step 4: Run the shell test and** `xcodebuild -project Omnia.xcodeproj -scheme Omnia -configuration Debug -destination 'platform=macOS' build`; require the app binary to link libtorrent and the staged dylibs to exist in `Contents/Frameworks`.

### Task 3: Visible add-on removal

**Files:**
- Modify: `Omnia/Features/Settings/AddonsSettingsView.swift`
- Test: `OmniaTests/SettingsPresentationTests.swift`
- Test: `OmniaTests/AddonRegistryTests.swift`

**Interfaces:**
- Consumes: existing `addonToRemove` confirmation and `AddonRegistry.remove(id:)`.
- Produces: `AddonSettingsRow` remove action with an accessible, visible trash button.

- [ ] **Step 1: Write a failing presentation test** whose mutation is removal of the visible remove action while registry behavior remains covered independently.
- [ ] **Step 2: Run** the two focused test classes and confirm the presentation test fails.
- [ ] **Step 3: Add** a bordered, destructive trash button labeled `Remove <name>` that only sets `addonToRemove`; keep the existing confirmation as the sole mutation point.
- [ ] **Step 4: Rerun** the focused tests and require zero failures.

### Task 4: Per-shelf Home controls

**Files:**
- Create: `Omnia/Domain/Settings/HomeShelfPreferences.swift`
- Modify: `Omnia/Data/Metadata/LiveMetadataStore.swift`
- Modify: `Omnia/Features/Home/HomeView.swift`
- Modify: `Omnia/Features/Settings/CatalogsSettingsView.swift`
- Test: `OmniaTests/HomeShelfPreferencesTests.swift`

**Interfaces:**
- Consumes: `BuiltInHomeCatalog.id` and `[BuiltInHomeCatalog]`.
- Produces: `HomeShelfPreferences.disabledShelfIDs`, `isEnabled(_:)`, `set(_:enabled:)`, and deterministic filtering used by Home and hero candidates.

- [ ] **Step 1: Write failing tests** for default-enabled shelves, disabling exactly one shelf, persistence round-trip, ignoring unknown IDs safely, and filtering hero inputs consistently.
- [ ] **Step 2: Run** the new test class and confirm failure because the preferences type does not exist.
- [ ] **Step 3: Implement** stable catalog IDs from kind/category/title, a versioned UserDefaults envelope, a small observable store, per-shelf toggles in Catalog Settings, and Home filtering. Existing Continue Watching and Upcoming settings remain independent.
- [ ] **Step 4: Rerun** the new and settings test classes and require zero failures.

### Task 5: Integrated verification

**Files:**
- Review only every intended path from Tasks 1–4 and the prior identifier fix.

**Interfaces:**
- Consumes: all completed tasks.
- Produces: fresh evidence for supported platforms and server-side metadata checks.

- [ ] **Step 1: Run focused XCTest** for source resolution, source presentation, local torrent, add-on registry, settings presentation, and shelf preferences.
[Historical automated-validation command removed by repository policy.]
- [ ] **Step 3: Build iOS Simulator** with `xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'generic/platform=iOS Simulator' build`.
- [ ] **Step 4: Run Deno checks** using the frozen commands in `AGENTS.md`.
- [ ] **Step 5: Run** `git diff --check`, inspect `git status --short`, and confirm no private endpoint or credential entered the diff.
