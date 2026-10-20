# iPadOS-Style Top Tab Bar in Omnia's Native macOS Build

> **Automated-validation policy:** Follow the repository-root `AGENTS.md`. Instructions below that call for automated test targets, suites, fixtures, or scripts are historical and superseded; use builds, static checks, and focused manual evidence instead.

Date: 2026-09-16

## Conclusion

The clarified Fusion reference is a floating **top tab bar**, not a navigation toolbar. Omnia can implement this natively in its existing SwiftUI macOS target: Apple documents that `TabBarPlacement.topBar` is used by the `tabBarOnly` `TabView` style on both iPad and macOS.

The system will render the platform-appropriate version rather than copying iPad pixels onto Mac, but it is the same native tab-bar component and current Liquid Glass design family. No Mac Catalyst target or custom glass capsule is required.

## What Apple Supports

### 1. Native top tab bar — supported and recommended for the clarified reference

Use a `TabView` containing Omnia's top-level destinations and apply `.tabViewStyle(.tabBarOnly)`. Apple explicitly documents that this style can place the tab bar at the top on iPad and macOS. A `Tab` with `role: .search` receives the platform's dedicated search-tab treatment, which places Search separately at the trailing edge in the current design.

For Omnia, the proposed order is Home, Library, Discover, and Settings in the main group, with Search as the dedicated trailing tab. This remains five destinations, consistent with Apple's recommendation to default to five or fewer tabs.

Primary sources:

- [`TabBarPlacement.topBar`](https://developer.apple.com/documentation/swiftui/tabbarplacement/topbar)
- [`TabViewStyle.tabBarOnly`](https://developer.apple.com/documentation/swiftui/tabviewstyle/tabbaronly)
- [Tab bars — Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/tab-bars)
- [Searching — Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/searching)

### 2. Native macOS toolbar — a different component

SwiftUI's toolbar model is cross-platform: `toolbar(content:)` populates a toolbar or navigation bar, and the system chooses where and how to present it according to platform and context. Apple documents the placement difference explicitly: a `.navigation` item goes into the leading edge of the window toolbar on macOS and Mac Catalyst, but into the navigation bar on iOS and iPadOS.

For a Mac window, `windowToolbarStyle(.unified)` places the toolbar and title bar inline; `.unifiedCompact` provides the corresponding compact-height Mac variant. These remain macOS toolbars, not iPadOS navigation bars.

Apple's current design guidance intentionally gives iPadOS and macOS related toolbar behavior and visual language, while retaining platform-specific chrome. Apple says the Mac toolbar lives in the window frame, below or integrated with the title bar. Its WWDC25 SwiftUI guidance also describes shared Liquid Glass updates across iPad and Mac and says search appears at the top-trailing position on both.

Primary sources:

- [Toolbars — SwiftUI](https://developer.apple.com/documentation/swiftui/toolbars)
- [`ToolbarItemPlacement.navigation`](https://developer.apple.com/documentation/swiftui/toolbaritemplacement/navigation)
- [`WindowToolbarStyle`](https://developer.apple.com/documentation/swiftui/windowtoolbarstyle)
- [Toolbars — Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/toolbars)
- [Build a SwiftUI app with the new design — WWDC25](https://developer.apple.com/videos/play/wwdc2025/323/)

### 3. iPadOS `NavigationStack` / navigation bar — shared declaration, platform-specific rendering

Using `NavigationStack`, `navigationTitle`, `searchable`, and `.toolbar` in shared SwiftUI code does not force the iPad presentation onto macOS. The same declarations resolve into the bar owned by the active platform and container. On iPadOS that is typically a navigation bar; on macOS it is the window toolbar.

This is the best way to share actions, titles, grouping, search, and navigation intent. Platform conditionals should be reserved for genuine behavioral differences instead of duplicating a custom bar.

Primary sources:

- [Navigation — SwiftUI](https://developer.apple.com/documentation/swiftui/navigation)
- [Toolbars — SwiftUI](https://developer.apple.com/documentation/swiftui/toolbars)
- [`ToolbarItemPlacement.navigation`](https://developer.apple.com/documentation/swiftui/toolbaritemplacement/navigation)

### 4. Mac Catalyst — unnecessary for this tab-bar design

Apple defines Mac Catalyst as creating a Mac version of an iPad app. In a Catalyst app, UIKit navigation bars can either be bridged into an `NSToolbar` for Mac behavior or retain iPad-style behavior. Apple documents `UIBehavioralStyle.pad` as making a control appear and behave as it does in iPadOS, and documents opting out of `NSToolbar` hosting by setting a navigation bar's preferred behavioral style to `.pad`.

That option applies to UIKit controls in a Mac Catalyst app; it does not make `UINavigationBar` available inside a native AppKit/macOS SwiftUI target. Moving Omnia to Catalyst would therefore be an architectural migration or an additional target, not a toolbar modifier. Its native playback libraries, AppKit integrations, signing, entitlements, window/full-screen behavior, and tests would all need separate compatibility review.

Primary sources:

- [Mac Catalyst](https://developer.apple.com/documentation/uikit/mac-catalyst)
- [Building a desktop-class iPad app](https://developer.apple.com/documentation/uikit/building-a-desktop-class-ipad-app)
- [`UIBehavioralStyle`](https://developer.apple.com/documentation/uikit/uibehavioralstyle)
- [`UINavigationBar`](https://developer.apple.com/documentation/uikit/uinavigationbar)

### 5. Visual emulation — possible, but not needed

A custom SwiftUI view can be drawn at the top of the content area to resemble an iPad bar. This is an implementation inference, not a system-provided iPadOS bar. It would need to recreate title/back behavior, safe-area handling, window resizing, keyboard focus, accessibility, overflow, search, scroll-edge effects, and toolbar/menu command parity.

Apple's HIG recommends system toolbars, automatic overflow, standard Back and Close controls, and avoiding custom backgrounds that interfere with system effects. For Omnia, emulation would add maintenance while weakening the “Apple native” design requirement.

Primary sources:

- [Toolbars — Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/toolbars)
- [Scroll views: scroll edge effects — Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/scroll-views)

## Current Omnia Evidence

Omnia already has the required destination model, but the Mac branch currently chooses a sidebar instead of a tab bar:

- `OmniaApp` uses a macOS `WindowGroup` with `.windowToolbarStyle(.unified(showsTitle: true))` in `Omnia/App/OmniaApp.swift`.
- `OmniaRootView` uses a macOS `NavigationSplitView` with Search, Home, Library, Discover, and Settings in a custom sidebar.
- The iOS branch already expresses the same destinations as SwiftUI `Tab` values and uses `.sidebarAdaptable`; this is close to the desired model.
- `OmniaNavigationTitle` puts Back, spacing, and title content in SwiftUI `.navigation` toolbar placements in `Omnia/UI/Components/OmniaNavigationTitle.swift`.
- The app build configurations currently set `SUPPORTED_PLATFORMS = macosx` and `SUPPORTS_MACCATALYST = NO` in `Omnia.xcodeproj/project.pbxproj`.

Consequently, this is a focused root-navigation change rather than a platform migration. The Mac branch can replace its `NavigationSplitView` sidebar with a `TabView` using `.tabBarOnly`, while keeping a separate `NavigationStack` inside every destination so each tab preserves its own navigation state.

## Recommendation

Keep the native macOS target and use the system tab bar rather than drawing a replica.

1. Share one `TabView` declaration for Home, Library, Discover, Settings, and Search where practical.
2. Give Search `role: .search` so the system presents it as the trailing search control.
3. Use `.tabViewStyle(.tabBarOnly)` for the Mac presentation shown in the reference. Keep `.sidebarAdaptable` on iPad only if Omnia still wants the user-selectable sidebar there; otherwise use `.tabBarOnly` there too.
4. Preserve Mac menu commands, full-screen playback, focused destination state, and per-tab navigation stacks.
5. Validate narrow and wide Mac windows, iPad multitasking widths, keyboard/focus order, VoiceOver, Reduce Transparency, Increase Contrast, and tab overflow.
