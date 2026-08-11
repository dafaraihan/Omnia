# Native Settings Hierarchy Design

**Date:** 2026-08-11

**Status:** Approved in design review

**Platforms:** iPhone, iPad, and Mac

**Owner:** Omnia Settings experience

## Goal

Rebuild Omnia's complete Settings experience as an Apple-native hierarchy while preserving every currently exposed category and behavior. Settings remains a top-level tab/sidebar destination on all supported platforms. Every pushed settings menu uses system navigation chrome and therefore receives the platform-native Back button and backward-navigation gestures or commands.

## Design basis

The implementation follows Apple's current [Design Resources](https://developer.apple.com/design/resources/), [Settings guidance](https://developer.apple.com/design/human-interface-guidelines/settings), [Lists and tables guidance](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables), and SwiftUI [`NavigationStack`](https://developer.apple.com/documentation/swiftui/navigationstack) and [`Form`](https://developer.apple.com/documentation/swiftui/form) contracts.

Apple's design kits are references for component anatomy, state, platform scale, and safe-area behavior. Omnia implements the experience through system SwiftUI APIs and semantic values; it does not ship Apple kit artwork or copy fixed measurements from a design file. The project continues to compile for its current iOS 26.5 and macOS 26.5 deployment targets, so a design-kit component is used only when a deployment-compatible system API supplies it. No third-party UI dependency is added.

## Current evidence and problem

`OmniaRootView` already places `SettingsView` inside a `NavigationStack`, which is the correct owner for native backward navigation. The working tree, however, mixes two settings systems:

- Add-ons, Local Progress, Upcoming, Video Player, and Subtitle Appearance use native `Form` and `Section` containers.
- Catalogs, Metadata, Account, Appearance, resolver configuration, and legacy supporting flows use custom scroll stacks, glass surfaces, separators, navigation rows, and manually assembled controls inside a 1,356-line `SettingsView.swift`.

The rebuild removes that inconsistency without changing product capabilities or trust boundaries.

## Information architecture

The Settings root is a searchable native `Form` with the following fixed order:

1. **Account**
   - Account
2. **Media**
   - Add-ons
   - Catalogs
   - Metadata
   - Progress
   - Upcoming
3. **Playback**
   - Video Player
   - Subtitle
4. **App**
   - Appearance
5. **About**
   - About Omnia

Catalogs remains a first-class Media destination and is not nested under Add-ons. Settings remains in Omnia's main sidebar on Mac instead of moving into a separate settings window.

Each root row contains a text title, an SF Symbol supplied by name, and an optional current-value summary. A symbol supplements text and never carries the only indication of status. Search matches destination titles, summaries, and approved setting terms; selecting a search result pushes the same typed route used by the visible root row.

## Navigation contract

A single `SettingsRoute` value type or enumeration is the source of truth for every internal Settings destination. It supplies the destination title, root section, system image, summary/search metadata, and destination mapping. Root rows, search results, Metadata provider details, Video Player to Subtitle, and nested About menus use typed `NavigationLink` values resolved by one `navigationDestination` registration in the Settings navigation hierarchy.

Pushed screens must:

- set a meaningful `navigationTitle`;
- leave the system navigation bar and toolbar visible;
- never call `navigationBarBackButtonHidden(true)`;
- never draw a custom back chevron or intercept the standard backward gesture;
- preserve the default Back button on iPhone and the platform-native toolbar Back behavior on iPad and Mac.

Nested `NavigationStack` instances are not used for pushed menus. A nested stack is permitted only inside an independently presented sheet when that sheet owns a modal workflow. Modal tasks such as adding an add-on or reviewing an import use system sheets with Cancel and Done/Add actions instead of Back.

## Native component language

Every Settings page uses the smallest appropriate native component:

- `Form` and `Section` for grouped settings;
- `NavigationLink` for hierarchy;
- `Label` and `LabeledContent` for identity and values;
- `Toggle`, `Picker`, `Slider`, `TextField`, `SecureField`, and `TextEditor` for editable values;
- `Button` with semantic roles for actions;
- `ProgressView` for bounded or ongoing work;
- `ContentUnavailableView` for a true empty or unavailable state;
- `confirmationDialog` or `alert` before destructive changes;
- file importer/exporter presentations for backup workflows.

The custom Settings glass surfaces, custom separators, custom disclosure chevrons, and custom row containers are removed. System semantic colors, text styles, materials, spacing, selection, focus, and control states replace them. Settings contains no cinematic artwork.

## Screen contracts

### Account

When signed out, Account presents Apple, Google, and Facebook as authentication actions using their existing approved provider marks and the provider's supported authentication flow. Authentication rows are buttons, not navigation links. While a request is active, provider actions are disabled and progress is visible. A failure remains inline, uses non-secret language, and permits retry.

When signed in, the page shows the available account identifier and provider. Sign Out requires confirmation before changing session state. Discovery, local progress, and local settings remain usable without an account. The redesign does not invent account linking, account deletion, cloud-sync status, or provider capabilities that the current repository does not implement.

### Add-ons

Add-ons preserves request timeout, add, enable/disable, reorder, import, export, and remove behavior. An empty installation uses a native unavailable state. Reordering works through system edit mode and also exposes Move Earlier and Move Later commands in each row's actions or context menu plus matching accessibility actions. Removal requires confirmation. Import validation precedes installation; partial success retains successful installations and reports failures without discarding prior state. Add remains a modal sheet with Cancel and Add.

### Catalogs

Catalogs identifies built-in catalogs separately from add-on catalogs. Add-on catalog toggles are grouped by owning add-on and become disabled with an explanatory footer when that add-on is disabled. No-add-on and no-declared-catalog states remain explicit. Catalog status is communicated with text/control state, not color alone.

### Metadata

Metadata preserves per-content primary provider selection, optional fallback providers, fallback order, provider information, user-managed credentials, and connection tests. Fallback reordering supports pointer/drag interaction plus keyboard and accessibility move commands. Provider credentials remain in Keychain, are never displayed after saving, and use non-secret success/failure messages. Destructive credential removal requires confirmation.

### Progress

Progress preserves on-device storage explanation, Continue Watching limits, import/export, merge/replace review, Clear Progress, and Clear Watchlist. Replace, Clear Progress, and Clear Watchlist require confirmation. Work disables conflicting actions and shows progress. Invalid imports and persistence failures retain existing data and show a retryable or actionable explanation.

### Upcoming

Upcoming preserves Home visibility, look-ahead range, and item limit. Dependent controls disable when Upcoming is hidden and an explanatory state remains visible. No remote or hosted mutation is introduced.

### Video Player

Video Player preserves Skip Intro, Up Next, playback destination/engine information, source-selection behavior, preferred audio, anime audio, subtitle preferences, and the link to Subtitle. Dependent controls disable together with a written reason. IntroDB attribution and data-use explanation remain visible. Playback continues to identify AVPlayer on iPhone/iPad and libmpv on Mac.

### Subtitle

Subtitle preserves the live semantic preview, system/preset/custom styles, text/background/edge/position controls, and reset. Custom controls appear only for Custom mode. Reset requires confirmation and restores Follow System plus default custom values. The preview has a stable accessibility label and value.

### Appearance

Appearance uses native selection controls for the existing System, Light, and Dark choices and reports the resolved selection. It does not add redundant controls for system accessibility settings. Appearance changes continue to use Omnia's semantic colors and existing app-level appearance state.

### About Omnia

About is a pushed native form. It begins with the app version/build and supported platforms, then exposes typed submenus for:

- Metadata & Discovery;
- Playback;
- Add-on Technology;
- Cloud & Authentication;
- Apple Technologies;
- Open-Source Software;
- Attributions;
- Licenses; and
- Privacy.

The resource inventory is derived from repository evidence rather than marketing copy. At design time it includes:

- **Metadata and discovery:** TMDB, TheTVDB, MDBList, AniList, and YouTube trailer handoff;
- **Playback assistance:** IntroDB;
- **Add-on technology:** the supported Stremio-compatible HTTPS manifest, catalog, metadata, and stream subset;
- **Playback:** AVPlayer/AVFoundation on iPhone and iPad, and libmpv plus its bundled native dependency closure on Mac;
- **Cloud and authentication:** Supabase and Apple, Google, and Facebook authentication;
- **Apple technologies currently imported:** SwiftUI, Foundation, Observation, SwiftData, AVFoundation, AVKit, AuthenticationServices, CryptoKit, Security, Uniform Type Identifiers, UIKit where iOS-specific, and AppKit where Mac-specific;
- **Open source:** the declared Supabase Swift package dependency and libmpv/native libraries actually present in the built product.

Each resource row states what Omnia uses it for and links only to a verified official project, terms, attribution, privacy, or license location. Provider marks are supplementary. TMDB and TheTVDB attribution language remains compliant and does not imply endorsement. Build-time discovery should provide the app version/build. The resource registry is static, typed, reviewable, and covered by tests; it must not make network requests merely to render About.

## Data flow and ownership

The rebuild changes presentation and routing, not data ownership:

- `SettingsPreferencesStore` continues to own persisted user preferences.
- `OmniaStore` continues to own add-ons, catalog enablement, appearance, and local media operations.
- `OmniaAccount` continues to own authentication session state.
- Keychain-backed stores continue to own provider and resolver secrets.
- Platform playback code continues to report the active playback engine.

Views bind to these existing owners through focused bindings and small presentation models. No duplicate Settings state store, speculative service layer, hosted mutation, new provider API, or new package dependency is introduced.

## Error, empty, and recovery behavior

The root Settings page is local and immediate. Child pages keep successful content visible when one section fails. Loading replaces only the action or section doing work. Errors appear next to the affected operation, redact credentials and private URLs, and provide retry when retry is safe. Empty states explain the missing prerequisite and offer the relevant action when one exists. Disabled controls include a written reason. Destructive operations require an explicit native confirmation and retain Cancel.

## Accessibility and platform adaptation

All text uses system styles and supports Dynamic Type without truncating critical labels or state. Form order defines a logical VoiceOver and keyboard focus order. Icons and provider marks are hidden when decorative or combined with a complete text label. Validation and selection never depend on color. Controls remain operable through touch, pointer, keyboard, Full Keyboard Access, VoiceOver, and switch access.

Native forms and semantic colors supply opaque, contrast-preserving behavior when Reduce Transparency or Increase Contrast is active. The Settings hierarchy introduces no essential animation; any incidental transition respects Reduce Motion. iPhone validation covers portrait, landscape, safe areas, and backward swipe. iPad validation covers compact and regular multitasking widths, pointer, and keyboard. Mac validation covers the main sidebar flow, window resizing, menus, hover, focus, and native toolbar Back behavior.

## File boundaries

The implementation splits the legacy file by responsibility:

- Settings root, route metadata, destination mapping, and search;
- Account;
- Catalogs;
- Metadata routing and provider detail;
- Appearance;
- About and its resource registry;
- existing dedicated Add-ons, Progress, Upcoming, Video Player, and Subtitle screens;
- small shared presentation models or native helpers only where more than one screen requires them.

Files that already contain uncommitted user work are edited narrowly. Unrelated working-tree changes are preserved.

## Verification

Automated coverage must demonstrate:

- the route registry includes every approved root and nested destination exactly once;
- root order and section membership match this specification;
- search finds every category through its title and approved terms;
- every route resolves to a destination with a nonempty navigation title;
- the About resource registry contains every required evidence-derived category and resource;
- dependent Video Player, Upcoming, Metadata, and Subtitle states expose their disabled reason or resolved value;
- destructive operations require an explicit confirmation state before execution;
- existing preference decoding and normalization remain compatible.

Verification commands are the repository's signed macOS test/build and iOS Simulator build commands. UI smoke checks cover every root row, at least one nested About route, Video Player to Subtitle, native backward navigation, modal Cancel/Done, loading, empty, failure, disabled, and destructive-confirmation states. Final validation includes `git diff --check` and review of only the intended Settings, test, project-membership, and design paths.

## Non-goals

- Moving Mac Settings to a separate window.
- Adding tvOS support.
- Adding account linking, deletion, or cloud-sync capabilities.
- Adding new metadata, playback, authentication, or add-on providers.
- Changing hosted Supabase configuration or deploying backend code.
- Shipping Apple Design Resource artwork or a pixel copy of Apple's Settings app.
- Refactoring unrelated application features.
