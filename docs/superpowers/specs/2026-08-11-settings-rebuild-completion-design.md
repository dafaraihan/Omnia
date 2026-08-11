# Settings Rebuild Completion Design

**Date:** 2026-08-11

**Status:** Approved in design review

**Platforms:** iPhone, iPad, and Mac

## Goal

Finish and refine Omnia's existing Apple-native Settings rebuild. Preserve the current information architecture and behavior, complete the unfinished macOS presentation, and guarantee platform-native backward navigation for every pushed Settings menu.

This is a completion scope, not a replacement architecture. The detailed screen contracts remain owned by [Native Settings Hierarchy Design](2026-08-11-native-settings-hierarchy-design.md), and the Mac presentation remains owned by [macOS Settings Layout Design](2026-08-11-macos-settings-layout-design.md).

## Design basis

Use Apple's current Design Resources as a reference for component anatomy and platform conventions, together with the Human Interface Guidelines for Settings and the SwiftUI contracts for `NavigationStack`, `NavigationLink`, `navigationDestination`, `Form`, and `searchable`. Implement the result with deployment-compatible SwiftUI APIs, semantic system values, and SF Symbols by name. Do not copy fixed design-kit measurements or ship Apple design-resource artwork.

## Structure and navigation

Settings remains a top-level tab or sidebar destination. Its root sections remain Account, Media, Playback, App, and About, with the route ordering defined by `SettingsRoute`.

The `NavigationStack` in `OmniaRootView` remains the sole owner of nonmodal Settings navigation. Root rows and nested menus use typed `NavigationLink(value:)` values resolved by the existing centralized `navigationDestination(for:)` mapping. Pushed screens set meaningful titles and leave system navigation chrome visible. They must not create nested stacks, hide the native Back control, draw custom back chevrons, or intercept the standard backward gesture.

Independent modal tasks may own a nested stack when their correct controls are Cancel and Add or Done. These modals are not part of the pushed-menu Back contract.

On macOS, Settings remains integrated with Omnia's main sidebar. Root and pushed content uses the approved centered, top-aligned pane. On iPhone and iPad, forms remain platform-native and full width.

## Screens and component language

The searchable root and every child screen use native SwiftUI containers and controls: `Form`, `Section`, `NavigationLink`, `Label`, `LabeledContent`, `Toggle`, `Picker`, `Slider`, `TextField`, `SecureField`, `Button`, `ProgressView`, and `ContentUnavailableView` as appropriate.

The current screen inventory is preserved:

- Account, including provider authentication, progress, error, identity, and confirmed sign-out states.
- Add-ons, including empty, add, import/export, enablement, reorder, and confirmed removal flows.
- Catalogs, including built-in and add-on ownership and prerequisite explanations.
- Metadata, including primary providers, ordered fallbacks, provider details, Keychain credentials, and connection tests.
- Progress, including limits, import/export, replacement review, and confirmed clearing.
- Upcoming, including visibility and dependent range and limit controls.
- Video Player, including playback behavior and links to Subtitle and Playback Resolver.
- Subtitle, including an accessible live preview, presets, conditional custom controls, and confirmed reset.
- Appearance, preserving System, Light, and Dark.
- About Omnia, including version/build, resources, attributions, licenses, technologies, and privacy.

Remove or avoid custom cards, separators, disclosure indicators, and custom navigation chrome. Use system typography, semantic colors, native focus behavior, and platform-adaptive spacing.

## macOS layout

All root and pushed Settings screens receive a reusable presentation-only container. It fills the detail region, top-aligns its content, preserves at least 24 points of outer spacing, and centers a readable pane capped at 680 points. At narrow widths it shrinks without clipping or horizontal scrolling. iPhone and iPad do not receive these Mac-only layout modifiers.

The Add Add-on sheet retains its independent compact modal layout.

## State and ownership

This rebuild does not change data ownership or trust boundaries:

- `SettingsPreferencesStore` owns persisted preferences.
- `OmniaStore` owns add-ons, catalogs, appearance, and local media operations.
- `OmniaAccount` owns authentication state.
- Keychain-backed stores own provider and resolver secrets.
- Existing HTTPS, exact allow-list, timeout, cancellation, and redacted-diagnostic boundaries remain intact.

Successful content stays visible when a subsection fails. Loading is scoped to the affected operation. Errors are adjacent, actionable where possible, and redact credentials and private URLs. Empty states explain missing prerequisites. Disabled controls include a written reason. Destructive actions require native confirmation with a Cancel path.

No dependency, hosted Supabase mutation, provider capability, tvOS target, or unrelated refactor is part of this work.

## Accessibility and platform adaptation

System text styles must support Dynamic Type without truncating critical state. Form order defines a logical VoiceOver and keyboard focus order. Decorative symbols and provider marks do not duplicate spoken labels. Status and validation never rely on color alone.

Verification covers VoiceOver, Full Keyboard Access, pointer interaction, focus rings, Reduce Motion, Reduce Transparency, Increase Contrast, and light/dark appearance. iPhone smoke tests cover portrait, landscape, safe areas, and swipe-back. iPad tests cover compact and regular multitasking widths, pointer, and keyboard. Mac tests cover narrow and wide windows, focus, keyboard navigation, and native toolbar Back behavior.

## Verification

Automated regression coverage must demonstrate:

- approved route order, section membership, search terms, titles, and destination metadata;
- native pushed-navigation architecture without child Settings stacks or hidden Back controls;
- Mac pane width capping and minimum outer margins;
- dependent-control explanations and explicit destructive confirmation;
- existing preference decoding and normalization compatibility.

Run focused Settings tests first, followed by the signed macOS XCTest suite and build, then the generic iOS Simulator build. Finish with `git diff --check` and review only the intended Settings, test, and design paths. Device- or hosted-environment checks that cannot be established locally must be reported rather than inferred.

## Completion condition

The work is complete when every root and nested Settings route renders with the approved native component language, all nonmodal menus use platform-native Back behavior, the Mac hierarchy uses the centered readable pane, relevant automated checks pass, and the supported-platform smoke-test evidence is recorded without claiming unperformed device verification.
