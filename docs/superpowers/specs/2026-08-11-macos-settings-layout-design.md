# macOS Settings Layout Design

## Status

Approved direction: **Integrated centered pane**. Settings remains a destination in Omnia's main macOS sidebar. The macOS presentation changes; the iPhone and iPad hierarchy remains unchanged.

## Problem and Evidence

The current `SettingsView` places a bare SwiftUI `Form` directly in the main window's detail area. On macOS, that form adopts the full available width and vertically centers its natural-height content. In a large Omnia window this produces extremely long navigation rows, weak grouping, and a large empty region above the form. The supplied 1940×1276 screenshot reproduces this behavior.

Apple documents `Form` as a platform-adaptive container and notes that macOS forms use aligned vertical stacks rather than the grouped-list presentation used on iOS. Apple also recommends maintaining comfortable information density on large Mac displays. The fix must therefore constrain the Mac content region instead of treating the entire resizable detail column as the form's ideal reading width.

References:

- [Form — SwiftUI](https://developer.apple.com/documentation/swiftui/form)
- [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/)
- [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)

## Layout

On macOS, every root and pushed Settings screen is hosted in a reusable `MacSettingsContentContainer`:

- The container fills the detail area so the app background remains continuous.
- Settings content is top-aligned with at least 24 points of horizontal and vertical breathing room.
- The readable pane has a maximum width of 680 points and stays horizontally centered as the window grows.
- At narrower window sizes, the pane shrinks to the available width after the minimum outer margins; it never clips or creates horizontal scrolling.
- Forms use SwiftUI's grouped form style on macOS. Sections, controls, focus behavior, keyboard navigation, semantic colors, and accessibility remain system-provided.
- The root pane displays a visible `Settings` heading above the grouped form. Search remains a system search field rather than a custom control.
- iPhone and iPad keep their existing full-width native `Form` presentation.

The container is applied at the typed destination boundary, so all Settings pages receive the same Mac width and alignment without duplicating layout modifiers across every feature file. The Add Add-on sheet remains independent because it is a genuinely modal task with its own compact sizing and Cancel/Add actions.

## Navigation

The existing `NavigationStack` owned by the Settings tab remains the only nonmodal Settings stack. Root rows and nested category rows continue to use typed `NavigationLink(value:)`, and `SettingsView` continues to own the exhaustive `navigationDestination(for:)` map.

Pushed screens do not hide or replace the navigation toolbar. macOS therefore supplies its native Back button and keyboard/toolbar behavior. No child Settings screen creates another `NavigationStack`. The modal Add Add-on flow continues to use its own stack because Cancel/Add, not Back, dismisses that task.

## Components and Boundaries

- `SettingsView` continues to own summaries, filtering, and route-to-destination mapping.
- `SettingsRoute` remains the navigation and search model; route order and labels do not change.
- `MacSettingsContentContainer` owns only responsive Mac presentation. It has no store access and does not know which Settings route it contains.
- `MacSettingsLayout` provides the width calculation consumed by the container. This keeps the window-width contract deterministic and testable.
- Existing category screens continue to own their controls, validation, empty/error states, destructive confirmations, and toolbars.

## State and Accessibility

This change introduces no new loading, error, offline, destructive, or persistence state. Existing state handling remains within each category screen.

The layout uses system text styles and semantic colors, retains native focus order, and does not impose fixed heights. Dynamic Type and long localized labels can increase row height. The centered pane shrinks with the window and the form scrolls vertically when its content exceeds the available height. Increase Contrast, Reduce Transparency, light/dark appearance, VoiceOver, Full Keyboard Access, pointer interaction, and native focus rings remain under the system controls.

## Verification

1. Add a macOS layout regression test that proves available widths larger than the readable maximum resolve to 680 points and narrower widths preserve 24-point margins.
2. Run the focused regression test before implementation and confirm it fails because `MacSettingsLayout` does not yet exist.
3. Implement the layout container and route-boundary wrapping, then rerun the focused test.
4. Run the complete signed macOS XCTest suite.
5. Build the macOS app and the generic iOS Simulator destination.
6. Smoke-test Settings at narrow, medium, and wide Mac window sizes; verify the root and at least two pushed screens, native Back, keyboard focus, search, dark/light appearance, and no horizontal clipping.

## Out of Scope

- Moving Settings to a separate macOS `Settings` scene or removing it from Omnia's sidebar.
- Reordering, adding, or removing Settings categories.
- Replacing system forms, navigation links, search, or toolbar controls with custom components.
- Changing any setting's behavior, persistence, copy, provider integration, or modal workflow.
