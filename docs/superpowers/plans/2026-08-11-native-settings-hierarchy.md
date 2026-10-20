# Native Settings Hierarchy Implementation Plan

> **Automated-validation policy:** Follow the repository-root `AGENTS.md`. Instructions below that call for automated test targets, suites, fixtures, or scripts are historical and superseded; use builds, static checks, and focused manual evidence instead.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild every Omnia Settings screen as a searchable, Apple-native typed navigation hierarchy with system Back behavior on iPhone, iPad, and Mac.

**Architecture:** Keep the existing `NavigationStack` in `OmniaRootView` as the sole owner of pushed Settings navigation. Introduce a typed `SettingsRoute` registry for root order, search, and nested destinations; split the legacy settings monolith into focused native `Form` screens backed by existing stores and small testable presentation models. Preserve all existing preference, credential, add-on, resolver, and account ownership boundaries.

**Tech Stack:** Swift 6, SwiftUI, Observation, XCTest, AuthenticationServices, Supabase Swift, Keychain-backed credential stores, AVFoundation/AVKit, and macOS libmpv.

## Global Constraints

- Follow the approved design in `docs/superpowers/specs/2026-08-11-native-settings-hierarchy-design.md`.
- Keep Settings in Omnia's main tab/sidebar on iPhone, iPad, and Mac.
- Continue to support iOS 26.5 and macOS 26.5; do not use a design-kit component without a deployment-compatible SwiftUI API.
- Use `Form`, `Section`, and native SwiftUI controls; do not recreate the removed custom glass-card Settings language.
- Use one typed route system for every pushed Settings menu and keep system navigation bars visible.
- Do not hide or replace the native Back button or backward gesture.
- Use nested `NavigationStack` only inside independently presented modal sheets.
- Preserve Apple/Google/Facebook authentication, Add-ons, Catalogs, Metadata, Progress, Upcoming, Video Player, Subtitle, Appearance, resolver, and About behavior.
- Preserve Keychain ownership of user secrets and the existing HTTPS, allow-list, timeout, cancellation, and redacted-error boundaries.
- Do not mutate hosted Supabase state, deploy code, add a dependency, add tvOS, or invent provider/account capabilities.
- Use four-space indentation in Swift and name XCTest methods with `test`.
- The repository is dirty. Before every commit, run `git diff --cached --name-only` and `git diff -- <task paths>`; never include the six pre-staged provider asset files or unrelated working-tree changes. If a path contains inseparable pre-existing user changes, leave the task uncommitted and report it instead of absorbing those changes into a commit.

---

## File Map

### Create

- `Omnia/Features/Settings/SettingsRoute.swift` — typed root/nested routes, section ordering, titles, symbols, and search matching.
- `Omnia/Features/Settings/AboutSettingsView.swift` — About root/detail forms and the evidence-backed resource registry.
- `Omnia/Features/Settings/AccountSettingsView.swift` — signed-out provider actions, signed-in identity, errors, progress, and confirmed sign out.
- `Omnia/Features/Settings/AppearanceSettingsView.swift` — native appearance selection.
- `Omnia/Features/Settings/CatalogsSettingsView.swift` — built-in and add-on catalog forms.
- `Omnia/Features/Settings/MetadataSettingsView.swift` — native routing controls, fallback ordering, provider detail, and credential confirmation.
- `Omnia/Features/Settings/PlaybackResolverSettingsView.swift` — resolver endpoint, exact allow-lists, Keychain token state, and confirmed token removal.
- `OmniaTests/SettingsRouteTests.swift` — route order, metadata, search, and nested-title coverage.
- `OmniaTests/AboutSettingsTests.swift` — complete About category/resource/link inventory.
- `OmniaTests/SettingsConfirmationTests.swift` — confirmation state cannot execute an action before explicit approval.
- `OmniaTests/MetadataRoutingTests.swift` — keyboard/accessibility fallback movement behavior.

### Modify

- `Omnia/Features/Settings/SettingsView.swift` — reduce to the searchable native root and centralized destination switch; delete migrated legacy/custom code.
- `Omnia/Features/Settings/SettingsSupportViews.swift` — remove `SettingsCapability`; retain bindings/models and add the shared confirmation state.
- `Omnia/Features/Settings/AddonsSettingsView.swift` — visible/context/accessibility reorder commands and unchanged modal add flow.
- `Omnia/Features/Settings/ProgressSettingsView.swift` — explicit confirmation before replacing an import.
- `Omnia/Features/Settings/VideoPlayerSettingsView.swift` — typed links to Subtitle and Playback Resolver.
- `Omnia/Domain/Metadata/MetadataRouting.swift` — bounded move-earlier/move-later operation used by non-drag input.
- `OmniaTests/SettingsPresentationTests.swift` — retain dependent-control and excluded-provider assertions; remove obsolete `SettingsCapability` assertions.
- `DESIGN.md` — update the Settings contract from mixed custom surfaces/current gaps to the verified native hierarchy.

### No project-file change

`Omnia.xcodeproj` uses `PBXFileSystemSynchronizedRootGroup` for both application and test folders. New `.swift` files are discovered automatically; do not edit `project.pbxproj` for membership.

---

### Task 1: Typed Settings Route and Search Registry

**Files:**

- Create: `Omnia/Features/Settings/SettingsRoute.swift`
- Create: `OmniaTests/SettingsRouteTests.swift`
- Modify: `Omnia/Features/Settings/SettingsSupportViews.swift`

**Interfaces:**

- Produces: `SettingsSection`, `SettingsRouteGroup`, `SettingsRoute`, `SettingsRoute.rootGroups`, `SettingsRoute.matches(_:)`, and `SettingsRoute.allVerificationRoutes`.
- Consumes later: `AboutSection`, represented in this task as the nested-route payload declared beside `SettingsRoute` and populated by Task 3.

- [ ] **Step 1: Write route-order, route-title, and search tests**

```swift
import XCTest
@testable import Omnia

final class SettingsRouteTests: XCTestCase {
    func testRootGroupsFollowApprovedOrder() {
        XCTAssertEqual(SettingsRoute.rootGroups.map(\.section), [.account, .media, .playback, .app, .about])
        XCTAssertEqual(
            SettingsRoute.rootGroups.flatMap(\.routes),
            [.account, .addons, .catalogs, .metadata, .progress, .upcoming,
             .videoPlayer, .subtitle, .appearance, .about]
        )
    }

    func testEveryVerificationRouteHasNavigationMetadata() {
        for route in SettingsRoute.allVerificationRoutes {
            XCTAssertFalse(route.title.isEmpty, "Missing title for \(route)")
            XCTAssertFalse(route.systemImage.isEmpty, "Missing symbol for \(route)")
        }
    }

    func testSearchFindsEveryRootCategoryByApprovedTerms() {
        let expectations: [(String, SettingsRoute)] = [
            ("Apple", .account), ("sources", .addons), ("catalog", .catalogs),
            ("TMDB", .metadata), ("watchlist", .progress), ("episodes", .upcoming),
            ("skip intro", .videoPlayer), ("captions", .subtitle),
            ("theme", .appearance), ("libmpv", .about)
        ]

        for (query, expectedRoute) in expectations {
            XCTAssertTrue(expectedRoute.matches(query), "\(query) must find \(expectedRoute)")
        }
    }

    func testBlankSearchMatchesEveryRootRoute() {
        XCTAssertTrue(SettingsRoute.rootGroups.flatMap(\.routes).allSatisfy { $0.matches("  ") })
    }
}
```

- [ ] **Step 2: Run the new tests and verify RED**

Run:

```bash
[Automated validation command removed by repository policy.]
```

Expected: compile failure because `SettingsRoute`, `SettingsSection`, and `SettingsRouteGroup` do not exist.

- [ ] **Step 3: Implement the route registry**

Use this public shape and exact root order:

```swift
import Foundation

enum SettingsSection: Int, CaseIterable, Identifiable, Sendable {
    case account, media, playback, app, about

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .account: "Account"
        case .media: "Media"
        case .playback: "Playback"
        case .app: "App"
        case .about: "About"
        }
    }
}

enum AboutSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case metadataAndDiscovery
    case playback
    case addonTechnology
    case cloudAndAuthentication
    case appleTechnologies
    case openSourceSoftware
    case attributions
    case licenses
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .metadataAndDiscovery: "Metadata & Discovery"
        case .playback: "Playback"
        case .addonTechnology: "Add-on Technology"
        case .cloudAndAuthentication: "Cloud & Authentication"
        case .appleTechnologies: "Apple Technologies"
        case .openSourceSoftware: "Open-Source Software"
        case .attributions: "Attributions"
        case .licenses: "Licenses"
        case .privacy: "Privacy"
        }
    }

    var systemImage: String {
        switch self {
        case .metadataAndDiscovery: "rectangle.3.group"
        case .playback: "play.rectangle"
        case .addonTechnology: "puzzlepiece.extension"
        case .cloudAndAuthentication: "cloud"
        case .appleTechnologies: "apple.logo"
        case .openSourceSoftware: "chevron.left.forwardslash.chevron.right"
        case .attributions: "text.quote"
        case .licenses: "doc.text"
        case .privacy: "hand.raised"
        }
    }
}

struct SettingsRouteGroup: Identifiable, Equatable, Sendable {
    let section: SettingsSection
    let routes: [SettingsRoute]
    var id: SettingsSection { section }
}

enum SettingsRoute: Hashable, Sendable {
    case account, addons, catalogs, metadata, progress, upcoming
    case videoPlayer, subtitle, playbackResolver, appearance, about
    case metadataProvider(String)
    case aboutSection(AboutSection)

    static let rootGroups: [SettingsRouteGroup] = [
        .init(section: .account, routes: [.account]),
        .init(section: .media, routes: [.addons, .catalogs, .metadata, .progress, .upcoming]),
        .init(section: .playback, routes: [.videoPlayer, .subtitle]),
        .init(section: .app, routes: [.appearance]),
        .init(section: .about, routes: [.about])
    ]

    static let allVerificationRoutes: [SettingsRoute] =
        rootGroups.flatMap(\.routes)
        + [.playbackResolver]
        + MetadataProvider.supported.map { .metadataProvider($0.id) }
        + AboutSection.allCases.map { .aboutSection($0) }

    var title: String {
        switch self {
        case .account: "Account"
        case .addons: "Add-ons"
        case .catalogs: "Catalogs"
        case .metadata: "Metadata"
        case .progress: "Progress"
        case .upcoming: "Upcoming"
        case .videoPlayer: "Video Player"
        case .subtitle: "Subtitle"
        case .playbackResolver: "Playback Resolver"
        case .appearance: "Appearance"
        case .about: "About Omnia"
        case let .metadataProvider(id):
            MetadataProvider.supported.first { $0.id == id }?.name ?? "Metadata Provider"
        case let .aboutSection(section): section.title
        }
    }

    var systemImage: String {
        switch self {
        case .account: "person.crop.circle"
        case .addons: "puzzlepiece.extension"
        case .catalogs: "rectangle.stack"
        case .metadata, .metadataProvider(_): "rectangle.3.group"
        case .progress: "clock.arrow.circlepath"
        case .upcoming: "calendar"
        case .videoPlayer: "play.rectangle"
        case .subtitle: "captions.bubble"
        case .playbackResolver: "lock.shield"
        case .appearance: "circle.lefthalf.filled"
        case .about: "info.circle"
        case let .aboutSection(section): section.systemImage
        }
    }

    var searchTerms: [String] {
        switch self {
        case .account: ["Apple", "Google", "Facebook", "sign in", "sign out"]
        case .addons: ["sources", "manifest", "timeout", "import", "export"]
        case .catalogs: ["catalog", "discover", "TMDB", "TVDB"]
        case .metadata: ["TMDB", "TVDB", "MDBList", "AniList", "providers", "fallback"]
        case .progress: ["local progress", "continue watching", "watchlist", "backup"]
        case .upcoming: ["episodes", "look ahead", "Home"]
        case .videoPlayer: ["skip intro", "up next", "audio", "source selection"]
        case .subtitle: ["subtitles", "captions", "SDH", "appearance"]
        case .playbackResolver: ["endpoint", "bearer token", "approved add-ons", "approved HTTPS hosts"]
        case .appearance: ["theme", "system", "light", "dark"]
        case .about: ["resources", "TMDB", "TVDB", "libmpv", "Supabase", "licenses", "privacy"]
        case .metadataProvider(_): ["metadata provider", title]
        case let .aboutSection(section): [section.title]
        }
    }

    func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return ([title] + searchTerms).contains {
            $0.localizedCaseInsensitiveContains(needle)
        }
    }
}
```

Remove the obsolete `SettingsCapability` enum from `SettingsSupportViews.swift`; retain `VideoPlayerSettingsModel`, `SubtitleAppearanceSettingsModel`, and both binding extensions.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the Step 2 command. Expected: all `SettingsRouteTests` pass.

- [ ] **Step 5: Commit only the route files if their diffs contain no inseparable user work**

```bash
git diff --check -- Omnia/Features/Settings/SettingsRoute.swift Omnia/Features/Settings/SettingsSupportViews.swift OmniaTests/SettingsRouteTests.swift
git commit --only Omnia/Features/Settings/SettingsRoute.swift Omnia/Features/Settings/SettingsSupportViews.swift OmniaTests/SettingsRouteTests.swift -m "Add typed settings routes"
```

---

### Task 2: Shared Explicit-Confirmation State

**Files:**

- Modify: `Omnia/Features/Settings/SettingsSupportViews.swift`
- Create: `OmniaTests/SettingsConfirmationTests.swift`

**Interfaces:**

- Produces: `SettingsConfirmation<Action>` with `request(_:)`, `cancel()`, and `confirm() -> Action?`.
- Consumed by: Account sign out, Metadata credential removal, Progress replacement, resolver-token removal, and existing destructive flows where adopting it simplifies state without changing behavior.

- [ ] **Step 1: Write tests proving actions require explicit approval**

```swift
import XCTest
@testable import Omnia

final class SettingsConfirmationTests: XCTestCase {
    private enum Action: Equatable { case signOut, replaceImport }

    func testConfirmDoesNothingWithoutPendingAction() {
        var confirmation = SettingsConfirmation<Action>()
        XCTAssertNil(confirmation.confirm())
    }

    func testConfirmReturnsAndClearsRequestedAction() {
        var confirmation = SettingsConfirmation<Action>()
        confirmation.request(.signOut)

        XCTAssertEqual(confirmation.confirm(), .signOut)
        XCTAssertNil(confirmation.pending)
    }

    func testCancelClearsRequestedAction() {
        var confirmation = SettingsConfirmation<Action>()
        confirmation.request(.replaceImport)
        confirmation.cancel()

        XCTAssertNil(confirmation.pending)
        XCTAssertNil(confirmation.confirm())
    }
}
```

- [ ] **Step 2: Run the tests and verify RED**

Run:

```bash
[Automated validation command removed by repository policy.]
```

Expected: compile failure because `SettingsConfirmation` does not exist.

- [ ] **Step 3: Implement the minimal generic state**

```swift
struct SettingsConfirmation<Action> {
    private(set) var pending: Action?

    mutating func request(_ action: Action) {
        pending = action
    }

    mutating func cancel() {
        pending = nil
    }

    mutating func confirm() -> Action? {
        defer { pending = nil }
        return pending
    }
}
```

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run the Step 2 command. Expected: three tests pass.

- [ ] **Step 5: Commit the confirmation model and tests through the dirty-tree gate**

```bash
git diff --check -- Omnia/Features/Settings/SettingsSupportViews.swift OmniaTests/SettingsConfirmationTests.swift
git commit --only Omnia/Features/Settings/SettingsSupportViews.swift OmniaTests/SettingsConfirmationTests.swift -m "Require explicit settings confirmation"
```

---

### Task 3: Evidence-Backed About Registry and Typed Submenus

**Files:**

- Create: `Omnia/Features/Settings/AboutSettingsView.swift`
- Create: `OmniaTests/AboutSettingsTests.swift`
- Modify: `Omnia/Features/Settings/SettingsRoute.swift`

**Interfaces:**

- Produces: `AboutResource`, `AboutResourceLink`, `AboutResourceLink.Kind`, `AboutCatalog.resources`, `AboutSettingsView`, and `AboutSectionSettingsView`.
- Consumes: `AboutSection` and `SettingsRoute.aboutSection` from Task 1.

- [ ] **Step 1: Write completeness and link-safety tests**

```swift
import XCTest
@testable import Omnia

final class AboutSettingsTests: XCTestCase {
    func testEveryApprovedAboutSectionHasContent() {
        for section in AboutSection.allCases {
            XCTAssertFalse(AboutCatalog.items(for: section).isEmpty, "Missing \(section)")
        }
    }

    func testDirectRuntimeResourcesAreDocumented() {
        let ids = Set(AboutCatalog.resources.map(\.id))
        let required: Set<String> = [
            "tmdb", "tvdb", "mdblist", "anilist", "youtube", "introdb",
            "stremio-addons", "avplayer", "libmpv", "supabase",
            "sign-in-with-apple", "google-auth", "facebook-auth",
            "swiftui", "foundation", "observation", "swiftdata",
            "avfoundation", "avkit", "authenticationservices", "cryptokit",
            "security", "uniformtypeidentifiers", "uikit", "appkit",
            "supabase-swift", "native-playback-libraries"
        ]
        XCTAssertTrue(required.isSubset(of: ids), "Missing \(required.subtracting(ids))")
    }

    func testEveryExternalResourceLinkUsesHTTPS() {
        for resource in AboutCatalog.resources {
            for link in resource.links {
                XCTAssertEqual(link.url.scheme, "https", "Unsafe About link: \(link.url)")
            }
        }
    }

    func testTMDBRequiredNoticeIsExact() {
        let tmdb = try! XCTUnwrap(AboutCatalog.resources.first { $0.id == "tmdb" })
        XCTAssertEqual(
            tmdb.attribution,
            "This product uses the TMDB API but is not endorsed or certified by TMDB."
        )
    }
}
```

- [ ] **Step 2: Run the tests and verify RED**

Run:

```bash
[Automated validation command removed by repository policy.]
```

Expected: compile failure because the About registry types do not exist.

- [ ] **Step 3: Implement a static, non-networked resource registry**

Use this shape:

```swift
struct AboutResourceLink: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable { case official, attribution, terms, privacy, license }
    let kind: Kind
    let title: String
    let url: URL
    var id: String { "\(kind.rawValue):\(url.absoluteString)" }
}

struct AboutResource: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let purpose: String
    let sections: Set<AboutSection>
    let attribution: String?
    let links: [AboutResourceLink]
}

enum AboutCatalog {
    static func items(for section: AboutSection) -> [AboutResource] {
        resources.filter { $0.sections.contains(section) }
    }
}
```

Populate `AboutCatalog.resources` from this exact evidence table. The section abbreviations are MD (Metadata & Discovery), PB (Playback), AO (Add-on Technology), CA (Cloud & Authentication), AT (Apple Technologies), OS (Open-Source Software), AU (Attributions), LI (Licenses), and PR (Privacy).

| ID | Visible name and purpose | Sections | Required official links |
| --- | --- | --- | --- |
| `tmdb` | TMDB — movie/series discovery, details, people, and artwork | MD, AU, PR | `https://developer.themoviedb.org/docs/faq`, `https://www.themoviedb.org/privacy-policy` |
| `tvdb` | TheTVDB — series, season, episode, and artwork metadata | MD, AU, PR | `https://thetvdb.com`, `https://thetvdb.com/privacy-policy` |
| `mdblist` | MDBList — user-key ratings and lists | MD | `https://mdblist.com` |
| `anilist` | AniList — anime discovery and optional account metadata | MD, PR | `https://anilist.co`, `https://anilist.co/terms` |
| `youtube` | YouTube — external trailer playback handoff | MD, PR | `https://www.youtube.com`, `https://policies.google.com/privacy` |
| `introdb` | IntroDB — read-only intro timestamp lookup | PB, AU | `https://introdb.app/docs/terms` |
| `stremio-addons` | Stremio-compatible add-ons — HTTPS manifest/catalog/meta/stream subset | AO | `https://stremio.github.io/stremio-addon-guide/` |
| `avplayer` | AVPlayer — in-app iPhone and iPad playback | PB, AT | `https://developer.apple.com/documentation/avfoundation/avplayer` |
| `libmpv` | libmpv — in-app Mac playback | PB, OS, LI | `https://mpv.io`, `https://github.com/mpv-player/mpv/blob/master/Copyright` |
| `supabase` | Supabase — authentication, metadata function, and cloud data boundary | CA, PR | `https://supabase.com`, `https://supabase.com/privacy` |
| `sign-in-with-apple` | Sign in with Apple — native Apple authentication | CA, AT, PR | `https://developer.apple.com/sign-in-with-apple/`, `https://www.apple.com/legal/privacy/` |
| `google-auth` | Google OAuth — Google account authentication through Supabase | CA, PR | `https://developers.google.com/identity`, `https://policies.google.com/privacy` |
| `facebook-auth` | Facebook Login — Facebook account authentication through Supabase | CA, PR | `https://developers.facebook.com/docs/facebook-login/`, `https://www.facebook.com/privacy/policy/` |
| `swiftui` | SwiftUI — application and Settings interface | AT | `https://developer.apple.com/documentation/swiftui` |
| `foundation` | Foundation — networking, data, URLs, files, and core value types | AT | `https://developer.apple.com/documentation/foundation` |
| `observation` | Observation — observable application state | AT | `https://developer.apple.com/documentation/observation` |
| `swiftdata` | SwiftData — durable local media storage | AT | `https://developer.apple.com/documentation/swiftdata` |
| `avfoundation` | AVFoundation — audiovisual playback and media selection | AT | `https://developer.apple.com/documentation/avfoundation` |
| `avkit` | AVKit — system audiovisual presentation support | AT | `https://developer.apple.com/documentation/avkit` |
| `authenticationservices` | AuthenticationServices — Sign in with Apple authorization | AT | `https://developer.apple.com/documentation/authenticationservices` |
| `cryptokit` | CryptoKit — OAuth nonce hashing | AT | `https://developer.apple.com/documentation/cryptokit` |
| `security` | Security — Keychain storage for user secrets | AT | `https://developer.apple.com/documentation/security` |
| `uniformtypeidentifiers` | Uniform Type Identifiers — JSON import/export types | AT | `https://developer.apple.com/documentation/uniformtypeidentifiers` |
| `uikit` | UIKit — iPhone/iPad platform integration | AT | `https://developer.apple.com/documentation/uikit` |
| `appkit` | AppKit — Mac window and platform integration | AT | `https://developer.apple.com/documentation/appkit` |
| `supabase-swift` | Supabase Swift — Swift client package | OS, LI | `https://github.com/supabase/supabase-swift`, `https://github.com/supabase/supabase-swift/blob/main/LICENSE` |
| `native-playback-libraries` | Native playback libraries — FFmpeg, libass, libplacebo, MuJS, Little CMS, libarchive, libbluray, LuaJIT, Rubber Band, uchardet, zimg, jpeg-turbo, and Vulkan loader in the observed libmpv closure | OS, LI | `https://github.com/mpv-player/mpv/blob/master/Copyright` |

Use the exact TMDB notice asserted by the test. For TheTVDB, display neutral attribution that Omnia uses TheTVDB metadata and link to the official site without implying endorsement.

Set `sections` so technology pages show their relevant resources and aggregate Attributions, Licenses, and Privacy pages show only resources with that applicable link/notice. Keep the registry static and deterministic.

- [ ] **Step 4: Build native About forms and typed links**

```swift
struct AboutSettingsView: View {
    var body: some View {
        Form {
            Section("Omnia") {
                LabeledContent("Version", value: appVersion)
                LabeledContent("Build", value: buildNumber)
                LabeledContent("Platforms", value: "iPhone, iPad, Mac")
            }
            Section("Resources and Technologies") {
                ForEach(AboutSection.allCases) { section in
                    NavigationLink(value: SettingsRoute.aboutSection(section)) {
                        Label(section.title, systemImage: section.systemImage)
                    }
                }
            }
        }
        .navigationTitle("About Omnia")
    }
}
```

Read `CFBundleShortVersionString` and `CFBundleVersion` with a small pure fallback that returns `"—"`, never a hard-coded release value. `AboutSectionSettingsView` uses `Form`/`Section`, `LabeledContent`, `Text`, and `Link`; it does not fetch content.

- [ ] **Step 5: Run focused tests and the macOS build**

```bash
[Automated validation command removed by repository policy.]
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' build
```

Expected: About tests and build pass.

- [ ] **Step 6: Commit only the About files through the dirty-tree gate**

```bash
git diff --check -- Omnia/Features/Settings/AboutSettingsView.swift Omnia/Features/Settings/SettingsRoute.swift OmniaTests/AboutSettingsTests.swift
git commit --only Omnia/Features/Settings/AboutSettingsView.swift Omnia/Features/Settings/SettingsRoute.swift OmniaTests/AboutSettingsTests.swift -m "Add comprehensive Omnia resources"
```

---

### Task 4: Searchable Root and Central Destination Mapping

**Files:**

- Modify: `Omnia/Features/Settings/SettingsView.swift`
- Modify: `OmniaTests/SettingsPresentationTests.swift`

**Interfaces:**

- Consumes: all `SettingsRoute` metadata from Task 1.
- Produces: a root `Form`, `.searchable`, one `navigationDestination(for: SettingsRoute.self)`, and `SettingsRouteLabel`.

- [ ] **Step 1: Replace obsolete capability tests with filtered-group behavior**

Add this test before changing the view:

```swift
func testFilteringPreservesApprovedSectionAndRouteOrder() {
    let groups = SettingsRoute.filteredRootGroups(query: "video")
    XCTAssertEqual(groups.map(\.section), [.playback])
    XCTAssertEqual(groups.flatMap(\.routes), [.videoPlayer])
}
```

Add `filteredRootGroups(query:)` to the interface expected in Task 1 and keep the filter stable:

```swift
static func filteredRootGroups(query: String) -> [SettingsRouteGroup] {
    rootGroups.compactMap { group in
        let routes = group.routes.filter { $0.matches(query) }
        return routes.isEmpty ? nil : .init(section: group.section, routes: routes)
    }
}
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
[Automated validation command removed by repository policy.]
```

Expected: compile failure because `filteredRootGroups(query:)` is missing.

- [ ] **Step 3: Implement the filter, then replace the root view**

The root body must have this structure:

```swift
@State private var searchText = ""

var body: some View {
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
    .navigationTitle("Settings")
    .searchable(text: $searchText, prompt: "Search Settings")
    .navigationDestination(for: SettingsRoute.self) { route in
        destination(for: route)
    }
}
```

Implement one exhaustive `@ViewBuilder destination(for:)` switch. At the end of all tasks it must map:

- `.account` → `AccountSettingsView()`
- `.addons` → `AddonsSettingsView()`
- `.catalogs` → `CatalogsSettingsView()`
- `.metadata` → `MetadataSettingsView()`
- `.progress` → `ProgressSettingsView()`
- `.upcoming` → `UpcomingSettingsView()`
- `.videoPlayer` → `VideoPlayerSettingsView()`
- `.subtitle` → `SubtitleAppearanceSettingsView()`
- `.playbackResolver` → `PlaybackResolverSettingsView()`
- `.appearance` → `AppearanceSettingsView()`
- `.about` → `AboutSettingsView()`
- `.metadataProvider(id)` → the matching `MetadataProviderDetailView`, with `ContentUnavailableView` only for an impossible unknown ID
- `.aboutSection(section)` → `AboutSectionSettingsView(section: section)`.

Keep `summary(for:)` limited to current state already available in `OmniaStore` and `SettingsPreferencesStore`: account/provider state, enabled add-on count, local-only progress, Upcoming visible/hidden, in-app playback, and appearance title.

- [ ] **Step 4: Delete only root-obsolete inline About content and run tests**

Do not yet delete legacy child views that Tasks 5–8 still migrate. Run:

```bash
[Automated validation command removed by repository policy.]
[Automated validation command removed by repository policy.]
```

Expected: both suites pass.

- [ ] **Step 5: Commit the root only if its pre-existing diff is reviewable as one coherent Settings change**

```bash
git diff --check -- Omnia/Features/Settings/SettingsView.swift Omnia/Features/Settings/SettingsRoute.swift OmniaTests/SettingsPresentationTests.swift
git commit --only Omnia/Features/Settings/SettingsView.swift Omnia/Features/Settings/SettingsRoute.swift OmniaTests/SettingsPresentationTests.swift -m "Build native settings root"
```

If this would absorb unrelated pre-existing changes from `SettingsView.swift`, do not commit; record the test result and continue with the working tree intact.

---

### Task 5: Native Account, Appearance, and Catalogs Screens

**Files:**

- Create: `Omnia/Features/Settings/AccountSettingsView.swift`
- Create: `Omnia/Features/Settings/AppearanceSettingsView.swift`
- Create: `Omnia/Features/Settings/CatalogsSettingsView.swift`
- Modify: `Omnia/Features/Settings/SettingsView.swift`
- Modify: `OmniaTests/SettingsPresentationTests.swift`

**Interfaces:**

- Consumes: `SettingsConfirmation`, `OmniaAccount.Provider`, `AppAppearance`, `OmniaStore`, and typed root routes.
- Produces: internal `AccountSettingsView`, `AppearanceSettingsView`, and `CatalogsSettingsView` types accessible to centralized destination mapping.

- [ ] **Step 1: Add account-provider and appearance-order regression tests**

```swift
func testAccountProvidersRemainAppleGoogleFacebook() {
    XCTAssertEqual(OmniaAccount.Provider.allCases, [.apple, .google, .facebook])
}

func testAppearanceChoicesRemainSystemLightDark() {
    XCTAssertEqual(AppAppearance.allCases, [.system, .light, .dark])
}
```

- [ ] **Step 2: Run the focused tests and record the baseline**

Run:

```bash
[Automated validation command removed by repository policy.]
```

Expected: the provider/appearance assertions pass against current domain behavior. Preserve this green characterization before moving presentation code.

- [ ] **Step 3: Move Account into a native Form and add confirmed Sign Out**

Use `Form` sections for Signed In or Sign In With. Reuse the existing provider marks from `AccountProviderMark`, moved into the new file. Provider rows remain `Button` actions because they authenticate; they are not fake navigation links. Add:

```swift
private enum DestructiveAction: Equatable { case signOut }
@State private var confirmation = SettingsConfirmation<DestructiveAction>()
```

Only call `await account.signOut()` after `confirmation.confirm()` returns `.signOut`. Show a native confirmation with Cancel. Preserve `account.isWorking`, `account.isConfigured`, and inline `account.errorMessage` behavior.

- [ ] **Step 4: Move Appearance into a native Form**

Use one `Picker("Appearance", selection:)` or checkmarked buttons over `AppAppearance.allCases`, with a footer explaining System follows the device. Do not keep the custom `SettingsGroup`, custom surfaces, or the hard-coded “Liquid Glass” value row.

- [ ] **Step 5: Rewrite Catalogs with native sections**

Use a Built-in section with `LabeledContent("TMDB + TVDB", value: "Default")`. For each installed add-on declaring catalogs, create a `Section(addon.manifest.name)` containing native `Toggle` controls. Disable the section's toggles when the owner add-on is disabled and provide the approved footer. If no add-on declares catalogs, use a `ContentUnavailableView` section that explains how catalogs appear.

- [ ] **Step 6: Delete the three migrated private types and their now-unused custom helper calls from `SettingsView.swift`**

Delete only `CatalogsSettingsView`, `AccountSettingsView`, `AppearanceSettingsView`, and `AccountProviderMark` definitions from the monolith. Central destination mapping must now resolve the new internal types.

- [ ] **Step 7: Run tests and both platform builds**

```bash
[Automated validation command removed by repository policy.]
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' build
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'generic/platform=iOS Simulator' build
```

Expected: tests and builds pass; Account, Appearance, and Catalogs use system Forms.

- [ ] **Step 8: Commit only the migrated screen paths through the dirty-tree gate**

```bash
git diff --check -- Omnia/Features/Settings/AccountSettingsView.swift Omnia/Features/Settings/AppearanceSettingsView.swift Omnia/Features/Settings/CatalogsSettingsView.swift Omnia/Features/Settings/SettingsView.swift OmniaTests/SettingsPresentationTests.swift
git commit --only Omnia/Features/Settings/AccountSettingsView.swift Omnia/Features/Settings/AppearanceSettingsView.swift Omnia/Features/Settings/CatalogsSettingsView.swift Omnia/Features/Settings/SettingsView.swift OmniaTests/SettingsPresentationTests.swift -m "Use native account and media settings"
```

---

### Task 6: Native Metadata Routing and Accessible Reordering

**Files:**

- Create: `Omnia/Features/Settings/MetadataSettingsView.swift`
- Create: `OmniaTests/MetadataRoutingTests.swift`
- Modify: `Omnia/Domain/Metadata/MetadataRouting.swift`
- Modify: `Omnia/Features/Settings/SettingsView.swift`

**Interfaces:**

- Produces: `MetadataRoute.moveFallback(_:direction:) -> Bool` and internal `MetadataSettingsView`/`MetadataProviderDetailView`.
- Consumes: `SettingsConfirmation`, `ProviderCredentialStore`, existing provider clients, `OmniaStore.metadataRouting`, and typed provider routes.

- [ ] **Step 1: Write bounded directional-move tests**

```swift
import XCTest
@testable import Omnia

final class MetadataRoutingTests: XCTestCase {
    func testMoveFallbackEarlierMovesOnePosition() {
        var route = MetadataRoute(primary: .anilist, fallbackOrder: [.tvdb, .tmdb])
        XCTAssertTrue(route.moveFallback(.tmdb, direction: .earlier))
        XCTAssertEqual(route.fallbackOrder, [.tmdb, .tvdb])
    }

    func testMoveFallbackLaterMovesOnePosition() {
        var route = MetadataRoute(primary: .anilist, fallbackOrder: [.tvdb, .tmdb])
        XCTAssertTrue(route.moveFallback(.tvdb, direction: .later))
        XCTAssertEqual(route.fallbackOrder, [.tmdb, .tvdb])
    }

    func testMoveFallbackRejectsBoundaryAndUnknownProvider() {
        var route = MetadataRoute(primary: .anilist, fallbackOrder: [.tvdb, .tmdb])
        XCTAssertFalse(route.moveFallback(.tvdb, direction: .earlier))
        XCTAssertFalse(route.moveFallback(.anilist, direction: .later))
        XCTAssertEqual(route.fallbackOrder, [.tvdb, .tmdb])
    }
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
[Automated validation command removed by repository policy.]
```

Expected: compile failure because `MetadataFallbackMoveDirection` and the directional overload do not exist.

- [ ] **Step 3: Implement minimal bounded movement**

```swift
nonisolated enum MetadataFallbackMoveDirection: Equatable, Sendable {
    case earlier, later
}

@discardableResult
mutating func moveFallback(
    _ provider: MetadataProviderIdentifier,
    direction: MetadataFallbackMoveDirection
) -> Bool {
    guard let source = fallbackOrder.firstIndex(of: provider) else { return false }
    let destination = direction == .earlier ? source - 1 : source + 1
    guard fallbackOrder.indices.contains(destination) else { return false }
    fallbackOrder.swapAt(source, destination)
    return true
}
```

- [ ] **Step 4: Rewrite Metadata with native Forms and typed provider links**

For each `MetadataContentClass`, create a native Section containing:

- a Picker for Primary Source;
- an Enable Fallback Toggle;
- a toggle per eligible fallback;
- an ordered native row per enabled fallback with Move Earlier/Move Later menu commands and matching `.accessibilityAction(named:)` actions.

Retain drag/drop only as a supplementary pointer interaction. Both drag and directional actions must update a copied `MetadataRoutingPreferences` value and assign it back to `store.metadataRouting`.

Provider rows use `NavigationLink(value: SettingsRoute.metadataProvider(provider.id))`. `MetadataProviderDetailView` remains a native Form. Replace immediate credential deletion with `SettingsConfirmation<UserManagedProviderCredential>` and a native confirmation; never show the stored credential. Keep connection testing localized to the provider section.

- [ ] **Step 5: Delete migrated Metadata types and provider-mark helpers from `SettingsView.swift`**

Move `ProviderMark` into `MetadataSettingsView.swift`. Delete `MetadataSettingsView`, routing groups, drag delegate, provider detail, `ProviderMarkStack`, and their custom row dependencies from the monolith.

- [ ] **Step 6: Run metadata tests and both platform builds**

```bash
[Automated validation command removed by repository policy.]
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' build
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'generic/platform=iOS Simulator' build
```

Expected: directional tests and builds pass.

- [ ] **Step 7: Commit the metadata paths through the dirty-tree gate**

```bash
git diff --check -- Omnia/Domain/Metadata/MetadataRouting.swift Omnia/Features/Settings/MetadataSettingsView.swift Omnia/Features/Settings/SettingsView.swift OmniaTests/MetadataRoutingTests.swift
git commit --only Omnia/Domain/Metadata/MetadataRouting.swift Omnia/Features/Settings/MetadataSettingsView.swift Omnia/Features/Settings/SettingsView.swift OmniaTests/MetadataRoutingTests.swift -m "Rebuild metadata settings"
```

---

### Task 7: Video Player, Subtitle, and Resolver Navigation

**Files:**

- Create: `Omnia/Features/Settings/PlaybackResolverSettingsView.swift`
- Modify: `Omnia/Features/Settings/VideoPlayerSettingsView.swift`
- Modify: `Omnia/Features/Settings/SettingsView.swift`
- Modify: `OmniaTests/SettingsPresentationTests.swift`

**Interfaces:**

- Consumes: `.subtitle` and `.playbackResolver` typed routes, existing resolver AppStorage keys, `PlaybackResolverCredentialStore`, and `OmniaStore` add-ons.
- Produces: native resolver Form and confirmed token removal.

- [ ] **Step 1: Add route metadata regression tests**

```swift
func testVideoPlayerNestedRoutesRemainDiscoverable() {
    XCTAssertEqual(SettingsRoute.subtitle.title, "Subtitle")
    XCTAssertEqual(SettingsRoute.playbackResolver.title, "Playback Resolver")
    XCTAssertTrue(SettingsRoute.playbackResolver.matches("approved HTTPS hosts"))
}
```

- [ ] **Step 2: Run the focused test and verify the new search term fails**

Run:

```bash
[Automated validation command removed by repository policy.]
```

Expected: FAIL until resolver search terms include endpoint, bearer token, approved add-ons, and approved HTTPS hosts.

- [ ] **Step 3: Use typed nested links in Video Player**

Replace closure links with:

```swift
NavigationLink("Subtitle", value: SettingsRoute.subtitle)
NavigationLink(value: SettingsRoute.playbackResolver) {
    LabeledContent("Playback Resolver", value: resolverSummary)
}
```

Keep both inside the relevant native sections. Do not create a nested navigation stack.

- [ ] **Step 4: Move resolver UI to a native Form**

Preserve endpoint, authorization token, approved add-on IDs, exact HTTPS stream hosts, Keychain state, and explanatory security text. Keep the endpoint and allow-list values in their existing AppStorage keys. Replace immediate token removal with a `SettingsConfirmation<DestructiveAction>` request and native confirmation. Continue to trim token input, never reveal the stored token, and never log endpoint/token/allow-list contents.

- [ ] **Step 5: Delete the legacy resolver and playback settings types from `SettingsView.swift`**

Remove `LegacyPlaybackSettingsView` and inline `PlaybackResolverSettingsView`. Do not remove the existing production `PlaybackResolverSettings` domain configuration or credential store.

- [ ] **Step 6: Run presentation/subtitle tests and both builds**

```bash
[Automated validation command removed by repository policy.]
[Automated validation command removed by repository policy.]
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' build
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'generic/platform=iOS Simulator' build
```

Expected: tests and builds pass; both nested pages get native Back from the root stack.

- [ ] **Step 7: Commit the playback Settings paths through the dirty-tree gate**

```bash
git diff --check -- Omnia/Features/Settings/PlaybackResolverSettingsView.swift Omnia/Features/Settings/VideoPlayerSettingsView.swift Omnia/Features/Settings/SettingsView.swift OmniaTests/SettingsPresentationTests.swift
git commit --only Omnia/Features/Settings/PlaybackResolverSettingsView.swift Omnia/Features/Settings/VideoPlayerSettingsView.swift Omnia/Features/Settings/SettingsView.swift OmniaTests/SettingsPresentationTests.swift -m "Rebuild playback settings flow"
```

---

### Task 8: Remaining State Coverage and Legacy Settings Removal

**Files:**

- Modify: `Omnia/Features/Settings/AddonsSettingsView.swift`
- Modify: `Omnia/Features/Settings/ProgressSettingsView.swift`
- Modify: `Omnia/Features/Settings/UpcomingSettingsView.swift`
- Modify: `Omnia/Features/Settings/SubtitleAppearanceSettingsView.swift`
- Modify: `Omnia/Features/Settings/SettingsView.swift`
- Modify: `OmniaTests/SettingsPresentationTests.swift`

**Interfaces:**

- Consumes: shared confirmation state and typed route hierarchy.
- Produces: visible/keyboard/accessibility reorder actions, confirmed Progress replacement, and no remaining legacy custom Settings components.

- [ ] **Step 1: Add approved-screen and custom-component absence assertions**

Add a source audit test that reads the Settings feature directory from `#filePath` and asserts the production files contain no forbidden navigation/custom-surface calls:

```swift
func testSettingsSourcesDoNotHideNativeBackOrUseLegacySurfaceTypes() throws {
    let testsURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let settingsURL = testsURL.deletingLastPathComponent()
        .appending(path: "Omnia/Features/Settings")
    let sources = try FileManager.default.contentsOfDirectory(at: settingsURL, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "swift" }
        .map { try String(contentsOf: $0, encoding: .utf8) }
        .joined(separator: "\n")

    XCTAssertFalse(sources.contains("navigationBarBackButtonHidden(true)"))
    XCTAssertFalse(sources.contains("struct SettingsSurface"))
    XCTAssertFalse(sources.contains("struct SettingsNavigationRow"))
    XCTAssertFalse(sources.contains("struct SettingsToggleRow"))
}
```

- [ ] **Step 2: Run the audit and verify RED**

Run:

```bash
[Automated validation command removed by repository policy.]
```

Expected: FAIL because legacy custom Settings types remain in `SettingsView.swift`.

- [ ] **Step 3: Complete native Add-ons reordering**

Keep `.onMove` and iOS `EditButton`. Add Move Earlier and Move Later buttons to each row's context menu, disable boundary actions, and retain the existing named accessibility actions. Ensure movement calls the existing bounded `move(_:offset:)` path.

- [ ] **Step 4: Confirm replacement imports before applying them**

In `ProgressSettingsView`, change “Replace with Reviewed Import” to request a `.replaceImport` confirmation. Only call `applyImport(replacingExisting: true)` from the confirmation's destructive action. Preserve Merge as immediate and non-destructive. Keep existing Clear Progress and Clear Watchlist confirmations.

- [ ] **Step 5: Verify Upcoming and Subtitle native states without adding UI**

Keep Upcoming dependent controls disabled with the existing written hidden state. Keep Subtitle reset confirmation and accessible preview. Rename visible root/page copy from “Subtitle Appearance” to the approved “Subtitle” only where it is a navigation title/category; preserve detailed appearance terminology inside the page.

- [ ] **Step 6: Delete all remaining legacy/custom Settings declarations**

Remove `LegacyAddonsSettingsView`, its only child `AddonCatalogBrowserView`, the unreachable `LibraryPreferencesSettingsView`, the superseded `AddAddonSheet`, `SettingsGroup`, `SettingsNavigationRow`, `SettingsToggleRow`, `SettingsStaticRow`, `SettingsValueRow`, `SettingsIcon`, `SettingsDivider`, `SettingsSurface`, `SettingsEmptyState`, and `.omniaSettingsPageLayout()`. Repository inspection before planning established that the current root uses `AddonsSettingsView` and its `AddManifestView`, and no current route reaches those legacy declarations.

Before deletion, use `rg` to prove each type has no remaining consumer:

```bash
rg -n 'LegacyAddonsSettingsView|AddonCatalogBrowserView|LibraryPreferencesSettingsView|AddAddonSheet|Settings(Group|NavigationRow|ToggleRow|StaticRow|ValueRow|Icon|Divider|Surface|EmptyState)|omniaSettingsPageLayout' Omnia OmniaTests
```

Do not delete a reachable behavior; migrate it to the owning native screen first.

- [ ] **Step 7: Run the source audit, full Settings tests, and diff checks**

```bash
[Automated validation command removed by repository policy.]
[Automated validation command removed by repository policy.]
[Automated validation command removed by repository policy.]
git diff --check -- Omnia/Features/Settings OmniaTests
```

Expected: all tests pass and no legacy type remains.

- [ ] **Step 8: Commit the cleanup through the dirty-tree gate**

```bash
git diff --check -- Omnia/Features/Settings OmniaTests/SettingsPresentationTests.swift
git commit --only Omnia/Features/Settings/AddonsSettingsView.swift Omnia/Features/Settings/ProgressSettingsView.swift Omnia/Features/Settings/UpcomingSettingsView.swift Omnia/Features/Settings/SubtitleAppearanceSettingsView.swift Omnia/Features/Settings/SettingsView.swift OmniaTests/SettingsPresentationTests.swift -m "Finish native settings states"
```

---

### Task 9: Documentation, Build Matrix, and Manual Apple-Platform Verification

**Files:**

- Modify: `DESIGN.md`
- Verify: all intended Settings and test paths

**Interfaces:**

- Consumes: the complete Settings implementation.
- Produces: evidence-backed Current statements and final verification record.

- [ ] **Step 1: Update only the Settings screen contract in `DESIGN.md`**

Record as Current only what the code/tests prove:

- searchable grouped native root;
- approved root order;
- typed pushed routes and system Back behavior;
- native modal Cancel/Done actions;
- confirmed Sign Out, credential/token removal, Progress replacement, add-on removal, clearing, and subtitle reset;
- visible/keyboard/accessibility reorder paths;
- comprehensive static About/resource hierarchy.

Retain any accessibility/device check as a Requirement or Current gap until manually verified.

- [ ] **Step 2: Run the full signed macOS test suite**

```bash
[Automated validation command removed by repository policy.]
```

Expected: the entire XCTest bundle passes with the signed Omnia host and bundled libmpv.

- [ ] **Step 3: Build every affected supported destination**

```bash
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' build
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'generic/platform=iOS Simulator' build
```

Expected: both builds succeed without new warnings caused by Settings.

- [ ] **Step 4: Run static navigation and custom-UI audits**

```bash
rg -n 'navigationBarBackButtonHidden|toolbar\(\.hidden.*navigationBar|SettingsSurface|SettingsNavigationRow|SettingsToggleRow' Omnia/Features/Settings
rg -n 'NavigationStack' Omnia/Features/Settings
git diff --check
```

Expected: no hidden/custom Back calls or legacy surface types. The only child `NavigationStack` is inside a modal sheet such as Add Add-on.

- [ ] **Step 5: Smoke-test the complete flow on Apple form factors**

Record results for:

- iPhone portrait and landscape: every root route, native Back button, backward swipe, search result push, safe areas, and large accessibility text;
- iPad compact and regular multitasking widths: sidebar selection, typed pushes, Back toolbar, pointer, hardware keyboard, focus order, and reorder commands;
- Mac minimum and expanded window sizes: main sidebar Settings, toolbar Back, Command-[ backward navigation if provided by the system, Full Keyboard Access, hover, menus, and reorder commands;
- VoiceOver: root order, row title/summary, provider actions, status announcements, subtitle preview, and move actions;
- Reduce Motion, Reduce Transparency, Increase Contrast, light/dark appearance, and color-independent disabled/error/destructive states;
- Add-ons empty/add/import failure/partial import/removal/reorder;
- Metadata connection loading/success/failure/credential removal/fallback reorder;
- Progress invalid import/merge/confirmed replacement/storage error/clear confirmations;
- Account unconfigured/loading/error/signed-in/confirmed sign-out;
- resolver unconfigured/configured/token removal and exact-host explanatory state.

- [ ] **Step 6: Review only intended diffs and verify user work remains preserved**

```bash
git status --short
git diff --stat
git diff -- Omnia/Features/Settings Omnia/Domain/Metadata/MetadataRouting.swift OmniaTests/SettingsRouteTests.swift OmniaTests/AboutSettingsTests.swift OmniaTests/SettingsConfirmationTests.swift OmniaTests/MetadataRoutingTests.swift OmniaTests/SettingsPresentationTests.swift DESIGN.md
git diff --cached --name-only
```

Expected: provider asset changes remain exactly as the user staged them; no Supabase hosted configuration, secrets, entitlements, playback implementation, or unrelated feature files changed for this Settings rebuild.

- [ ] **Step 7: Commit documentation only if it is the sole intended staged path**

```bash
git diff --check -- DESIGN.md
git commit --only DESIGN.md -m "Document native settings flow"
```

If implementation paths remain uncommitted because of pre-existing user changes, leave `DESIGN.md` uncommitted with them and report the complete verification evidence instead of creating a misleading partial history.
