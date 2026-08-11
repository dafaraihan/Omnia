# macOS Settings Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the stretched macOS Settings presentation with a centered, top-aligned native form pane while retaining Omnia's main sidebar and the system Back button for every pushed Settings screen.

**Architecture:** Keep the existing Settings `NavigationStack`, typed routes, forms, and destination map. Add one macOS-only responsive width model plus one reusable container in `SettingsSupportViews.swift`, then apply that container around the Settings root and destination boundary in `SettingsView.swift`; iOS passes through unchanged.

**Tech Stack:** Swift 6, SwiftUI, XCTest, macOS 26.5, iOS/iPadOS 26.5

## Global Constraints

- Follow `docs/superpowers/specs/2026-08-11-settings-rebuild-completion-design.md` and its linked hierarchy and macOS layout designs.
- Use Apple's current Design Resources and Human Interface Guidelines as references, implemented through deployment-compatible SwiftUI APIs and semantic system values.
- Settings remains in Omnia's main macOS sidebar.
- macOS Settings content is centered, top-aligned, grouped, limited to 680 points, and retains at least 24 points of horizontal margin.
- Every nonmodal submenu continues to use the existing typed `NavigationLink(value:)` hierarchy and system navigation toolbar Back button.
- The Add Add-on task remains a sheet with its own Cancel/Add actions.
- iPhone and iPad layout and behavior remain unchanged.
- No new dependency, custom navigation control, custom search field, or settings behavior is introduced.

---

### Task 1: Center the complete macOS Settings hierarchy

**Files:**

- Modify: `OmniaTests/SettingsPresentationTests.swift`
- Modify: `Omnia/Features/Settings/SettingsSupportViews.swift`
- Modify: `Omnia/Features/Settings/SettingsView.swift`
- Modify: `DESIGN.md`

**Interfaces:**

- Produces: `MacSettingsLayout.maximumContentWidth: CGFloat`
- Produces: `MacSettingsLayout.minimumOuterMargin: CGFloat`
- Produces: `MacSettingsLayout.contentWidth(for availableWidth: CGFloat) -> CGFloat`
- Produces: `MacSettingsContentContainer<Content: View>` with `init(@ViewBuilder content: () -> Content)`
- Preserves: `SettingsView.destination(for:)`, `SettingsRoute`, and every existing typed navigation value

- [ ] **Step 1: Add failing regression tests for wide and narrow Mac windows**

Append these tests to `SettingsPresentationTests`:

```swift
#if os(macOS)
    func testMacSettingsLayoutCapsWideContentAtReadableWidth() {
        XCTAssertEqual(MacSettingsLayout.contentWidth(for: 1_800), 680)
    }

    func testMacSettingsLayoutPreservesMarginsInNarrowWindow() {
        XCTAssertEqual(MacSettingsLayout.contentWidth(for: 600), 552)
        XCTAssertEqual(MacSettingsLayout.contentWidth(for: 40), 0)
    }
#endif
```

The production mutation these tests catch is returning the full detail-column width, which recreates the screenshot's stretched rows.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' \
  -only-testing:OmniaTests/SettingsPresentationTests test
```

Expected: compilation fails with `cannot find 'MacSettingsLayout' in scope`. A signing or host-application error is environmental and must be resolved before proceeding; it is not the expected RED result.

- [ ] **Step 3: Implement the deterministic Mac width contract**

Append this macOS-only model to `SettingsSupportViews.swift`:

```swift
#if os(macOS)
enum MacSettingsLayout {
    static let maximumContentWidth: CGFloat = 680
    static let minimumOuterMargin: CGFloat = 24

    static func contentWidth(for availableWidth: CGFloat) -> CGFloat {
        max(
            0,
            min(
                maximumContentWidth,
                availableWidth - (minimumOuterMargin * 2)
            )
        )
    }
}
#endif
```

- [ ] **Step 4: Implement the reusable native Mac container**

Below `MacSettingsLayout`, add a presentation-only container:

```swift
#if os(macOS)
struct MacSettingsContentContainer<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { geometry in
            content
                .formStyle(.grouped)
                .frame(width: MacSettingsLayout.contentWidth(for: geometry.size.width))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, MacSettingsLayout.minimumOuterMargin)
        }
    }
}
#endif
```

The outer frame fills the detail column; only the form pane is width-limited. The grouped form remains the scroll owner and retains system focus, keyboard, accessibility, and control behavior.

- [ ] **Step 5: Apply the container once at the root and typed destination boundary**

In `SettingsView`, add a pass-through helper so iOS does not receive Mac layout modifiers:

```swift
@ViewBuilder
private func settingsContent<Content: View>(
    @ViewBuilder content: () -> Content
) -> some View {
#if os(macOS)
    MacSettingsContentContainer(content: content)
#else
    content()
#endif
}
```

Wrap the root form in `settingsContent`. On macOS only, place a visible system-title heading above the root form:

```swift
settingsContent {
    VStack(alignment: .leading, spacing: 12) {
#if os(macOS)
        Text("Settings")
            .font(.title)
            .fontWeight(.semibold)
            .padding(.horizontal, 20)
#endif

        Form {
            ForEach(SettingsRoute.filteredRootGroups(query: searchText)) { group in
                Section(group.section.title) {
                    ForEach(group.routes, id: \.self) { route in
                        NavigationLink(value: route) {
                            SettingsRouteLabel(route: route, summary: summary(for: route))
                        }
                    }
                }
            }
        }
    }
}
```

Wrap the existing exhaustive switch inside `destination(for:)` in the same helper:

```swift
@ViewBuilder
private func destination(for route: SettingsRoute) -> some View {
    settingsContent {
        switch route {
        case .account:
            AccountSettingsView()
        case .addons:
            AddonsSettingsView()
        case .catalogs:
            CatalogsSettingsView()
        case .metadata:
            MetadataSettingsView()
        case .progress:
            ProgressSettingsView()
        case .upcoming:
            UpcomingSettingsView()
        case .videoPlayer:
            VideoPlayerSettingsView()
        case .subtitle:
            SubtitleAppearanceSettingsView()
        case .playbackResolver:
            PlaybackResolverSettingsView()
        case .appearance:
            AppearanceSettingsView()
        case .about:
            AboutSettingsView()
        case let .metadataProvider(id):
            if let provider = MetadataProvider.supported.first(where: { $0.id == id }) {
                MetadataProviderDetailView(provider: provider)
            } else {
                ContentUnavailableView(
                    "Provider Unavailable",
                    systemImage: "rectangle.3.group",
                    description: Text("This metadata provider is not supported by this version of Omnia.")
                )
            }
        case let .aboutSection(section):
            AboutSectionSettingsView(section: section)
        }
    }
}
```

Do not add a navigation stack, toolbar Back item, dismissal button, or `navigationBarBackButtonHidden`. The existing Settings tab stack must continue to supply native Mac Back behavior.

- [ ] **Step 6: Run the focused test and verify GREEN**

Run:

```sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' \
  -only-testing:OmniaTests/SettingsPresentationTests test
```

Expected: `SettingsPresentationTests` passes with no new warnings or errors.

- [ ] **Step 7: Update the canonical design status**

In `DESIGN.md` under `### Settings — SettingsView`, update the current platform-interaction description to state that macOS hosts the root and pushed forms in a centered, top-aligned 680-point pane with grouped system styling, while iPhone and iPad retain their platform-native full-width form behavior. Keep the existing typed navigation and modal-flow statements.

- [ ] **Step 8: Run full automated verification**

Run:

```sh
rg -n 'NavigationStack|navigationBarBackButtonHidden|Image\(systemName: "chevron\.(left|backward)' \
  Omnia/Features/Settings Omnia/App/OmniaRootView.swift
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' build
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'generic/platform=iOS Simulator' build
git diff --check
```

Expected: the navigation audit reports the Settings-tab stack and only the Add Add-on modal child stack, with no hidden or custom Back control. All build and test commands exit successfully. Review `git status --short` and the diff for only the four intended paths from this task; preserve all pre-existing user changes elsewhere.

- [ ] **Step 9: Smoke-test the actual macOS flow**

Launch the newly built Mac app and verify:

1. Settings at a wide window no longer stretches past 680 points and begins near the top.
2. Narrow and medium windows retain at least 24 points of horizontal margin without clipping.
3. Root search still filters sections and routes.
4. Push Account, then use the native toolbar Back button.
5. Push Video Player, then Subtitle, and use native Back at both levels.
6. Add Add-on still appears modally with Cancel/Add rather than Back.
7. Keyboard focus order and focus rings work across rows; VoiceOver announces row labels and summaries.
8. Light and dark appearances, Increase Contrast, Reduce Transparency, and window resizing retain readable grouping.

If Computer Use cannot start, report this smoke test as unverified rather than inferring success from the build.

- [ ] **Step 10: Smoke-test iPhone and iPad adaptation**

On an iPhone simulator, verify the Settings root, search, Account push and swipe/Back return, Video Player to Subtitle and two-level Back return, one destructive confirmation, portrait, landscape, safe areas, and a large Dynamic Type size. On an iPad simulator, repeat the hierarchy in compact and regular multitasking widths with keyboard and pointer input.

If simulator or physical-device interaction is unavailable, record each unverified item explicitly rather than inferring visual, input, or accessibility success from compilation.

- [ ] **Step 11: Commit the scoped implementation when explicitly authorized**

After reviewing the dirty worktree and receiving commit authorization, stage only the four files named by this task and commit:

```sh
git add Omnia/Features/Settings/SettingsSupportViews.swift \
  Omnia/Features/Settings/SettingsView.swift \
  OmniaTests/SettingsPresentationTests.swift \
  DESIGN.md
git commit -m "Fix macOS settings layout"
```

Do not stage the design/plan documents or any pre-existing unrelated work unless the user explicitly expands the commit scope.
