import SwiftUI
import Observation

/// Nuvio's first launch in Omnia's look: a welcome with the wordmark over
/// a moving wall of posters, a preview of Omnia and what it does, sign in
/// or continue without an account, then the first profile. Follows the
/// system's light or dark appearance.
struct OnboardingView: View {
    @Environment(ProfileStore.self) private var profiles
    @Environment(OmniaAccount.self) private var account
    @Environment(LiveMetadataStore.self) private var metadata
    @Environment(OmniaStore.self) private var store
    @Environment(AddonCatalogStore.self) private var addonCatalogs
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var step: Step = .welcome
    @State private var name = ""
    @State private var avatarID: String? = AvatarCatalog.random().id
    @State private var colorHex = ViewerProfile.colors.randomElement() ?? "705CFF"
    @State private var appeared = false
    @State private var previewSource = OnboardingPreviewSource()
    @State private var previewRetry = 0
    var onFinished: () -> Void

    static let completedKey = "onboarding-completed"

    private enum Step: Int, CaseIterable {
        case welcome, features, account, profile
    }

    private var availableShowcase: [MediaItem] {
        let catalogs = AddonCatalogStore.catalogs(in: store).filter {
            store.isCatalogEnabled(for: $0.addon, catalog: $0.catalog)
        }
        return catalogs.flatMap { addonCatalogs.rows[$0.key]?.items ?? [] }
            + metadata.topMovies + metadata.topSeries + metadata.movieCatalog + metadata.seriesCatalog
            + metadata.animeCatalogs.flatMap(\.items)
    }

    private var showcase: [MediaItem] {
        OnboardingPreviewSource.uniqueItems(availableShowcase + previewSource.items)
    }

    private var previewLoadKey: String {
        store.installedAddons.map { "\($0.id):\($0.isEnabled):\($0.manifestURL.absoluteString)" }.joined(separator: "|")
            + ":\(previewRetry)"
    }

    /// An iPhone held upright: steps stack in one column.
    private var isCompact: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    var body: some View {
        ZStack {
            OmniaBrandBackground()
            if step == .welcome {
                PosterWall(items: showcase)
                    .transition(.opacity)
            }
            Group {
                switch step {
                case .welcome: welcome
                case .features: ScrollView { features.padding(.vertical, 12) }
                case .account: accountStep
                case .profile:
                    if isCompact {
                        ScrollView { profileStep.padding(.bottom, 56) }
                            .scrollIndicators(.never)
                    } else {
                        profileStep
                    }
                }
            }
            .padding(isCompact ? 20 : 32)
            .frame(maxWidth: step == .profile || step == .features ? 960 : 720)
            .transition(.asymmetric(
                insertion: reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity),
                removal: reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity)
            ))
            .id(step)
        }
        .overlay(alignment: .bottom) { pageDots.padding(.bottom, 28) }
        .animation(reduceMotion ? nil : .smooth(duration: 0.5), value: step)
        .task(id: previewLoadKey) {
            await previewSource.load(store: store, existing: availableShowcase)
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 1.1, dampingFraction: 0.8).delay(0.15)) { appeared = true }
        }
        // Profiles from the account arrive after signing in; with some
        // already there, there's nothing left to set up.
        .onChange(of: profiles.profiles.isEmpty) { _, isEmpty in
            if !isEmpty, step == .profile { finish() }
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 26) {
            OmniaWordmark(height: 96)
                .scaleEffect(appeared ? 1 : 0.86)
                .blur(radius: appeared ? 0 : 12)
                .opacity(appeared ? 1 : 0)
            VStack(spacing: 10) {
                Text("Everything you watch, in one place.")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text("Movies, shows and live TV from the add-ons you choose.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .opacity(appeared ? 1 : 0)
            .offset(y: reduceMotion || appeared ? 0 : 14)
            .animation(reduceMotion ? nil : .smooth(duration: 0.8).delay(0.45), value: appeared)
            nextButton("Get Started") { step = .features }
                .padding(.top, 10)
                .opacity(appeared ? 1 : 0)
                .animation(reduceMotion ? nil : .smooth(duration: 0.8).delay(0.75), value: appeared)
        }
        .padding(.vertical, 36)
        .padding(.horizontal, 44)
        .background {
            // Keeps the words readable over the posters.
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(appeared ? 1 : 0)
        }
    }

    private var features: some View {
        VStack(spacing: 30) {
            Text("Made for How You Watch")
                .font(.system(size: 32, weight: .bold, design: .rounded))
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 32) {
                    AppPreview(items: showcase, isLoading: previewSource.isLoading, retry: { previewRetry += 1 }).frame(width: 480)
                    featureList.frame(width: 300)
                }
                VStack(spacing: 24) {
                    AppPreview(items: showcase, isLoading: previewSource.isLoading, retry: { previewRetry += 1 }).frame(maxWidth: 600)
                    featureList.frame(maxWidth: 600, alignment: .leading)
                }
            }
            HStack(spacing: 12) {
                Button("Back") { step = .welcome }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                nextButton("Continue") { step = .account }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 22) {
            StaggeredFeature(index: 0, symbol: "puzzlepiece.extension.fill", title: "Your Add-ons",
                             detail: "Bring the Stremio add-ons you already use. Omnia hosts nothing itself.")
            StaggeredFeature(index: 1, symbol: "person.2.fill", title: "Profiles for Everyone",
                             detail: "Up to five profiles, each with its own library, progress and settings.")
            StaggeredFeature(index: 2, symbol: "captions.bubble.fill", title: "Subtitles That Fit",
                             detail: "Styles, delay and automatic sync, right in the player.")
            StaggeredFeature(index: 3, symbol: "arrow.triangle.2.circlepath", title: "Picks Up Where You Left Off",
                             detail: "Sign in to restore your synced profiles, library, settings and sources.")
        }
    }

    private var accountStep: some View {
        VStack(spacing: 20) {
            OmniaWordmark(height: 36)
            AuthPanel(
                mode: .signUp,
                skipTitle: "Continue Without an Account",
                onSkip: { step = .profile },
                onSignedIn: afterSignIn
            )
        }
        .onAppear {
            if account.user != nil { afterSignIn() }
        }
    }

    private var profileStep: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Create Your Profile")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                Text("This is the main profile. You can add up to four more for family and friends later.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            // Side by side where there's room; the avatar grid goes under the
            // name on an iPhone.
            (isCompact ? AnyLayout(VStackLayout(spacing: 24)) : AnyLayout(HStackLayout(alignment: .top, spacing: 36))) {
                VStack(spacing: 18) {
                    ZStack {
                        Circle()
                            .fill(Color(profileHex: colorHex).opacity(0.45))
                            .frame(width: 170, height: 170)
                            .blur(radius: 46)
                        ProfileAvatarView(name: name.isEmpty ? "?" : name, avatarID: avatarID, colorHex: colorHex, size: 136, isSelected: true)
                            .id(avatarID)
                            .transition(.scale(scale: 0.85).combined(with: .opacity))
                    }
                    .frame(height: 150)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: avatarID)
                    TextField("Your name", text: $name)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .frame(width: 240, height: 44)
                        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .onChange(of: name) { _, value in
                            if value.count > ViewerProfile.maximumNameLength {
                                name = String(value.prefix(ViewerProfile.maximumNameLength))
                            }
                        }
                    HStack(spacing: 7) {
                        ForEach(ViewerProfile.colors.prefix(8), id: \.self) { hex in
                            Button { colorHex = hex } label: {
                                Circle()
                                    .fill(Color(profileHex: hex))
                                    .frame(width: 20, height: 20)
                                    .overlay {
                                        if hex == colorHex {
                                            Circle().strokeBorder(.primary, lineWidth: 2).padding(-3)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Colour \(hex)")
                        }
                    }
                    nextButton("Start Watching", isEnabled: !ViewerProfile.cleanName(name).isEmpty, action: createProfile)
                        .padding(.top, 6)
                }
                .frame(width: 280)
                ScrollView {
                    AvatarPicker(selection: $avatarID, columns: isCompact ? 5 : 7, size: 54)
                        .padding(18)
                }
                .scrollIndicators(.never)
                .frame(width: isCompact ? 5 * 54 + 4 * 12 + 36 : 7 * 54 + 6 * 12 + 36, height: isCompact ? 320 : 400)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .mask {
                    // Fades the grid out at the top and bottom edges.
                    LinearGradient(
                        stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.05),
                                .init(color: .black, location: 0.95), .init(color: .clear, location: 1)],
                        startPoint: .top, endPoint: .bottom
                    )
                }
            }
        }
    }

    // MARK: Pieces

    private func nextButton(_ title: String, isEnabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(minWidth: 180, minHeight: 30)
        }
        .buttonStyle(.glassProminent)
        .tint(OmniaBrandColors.violet)
        .controlSize(.large)
        .disabled(!isEnabled)
        .keyboardShortcut(.defaultAction)
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(Step.allCases, id: \.self) { item in
                Capsule()
                    .fill(item == step ? AnyShapeStyle(OmniaBrandColors.gradient) : AnyShapeStyle(.secondary.opacity(0.35)))
                    .frame(width: item == step ? 22 : 8, height: 8)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Actions

    private func afterSignIn() {
        Task {
            await profiles.sync(with: account)
            if profiles.profiles.isEmpty {
                step = .profile
            } else {
                finish()
            }
        }
    }

    private func createProfile() {
        guard !ViewerProfile.cleanName(name).isEmpty else { return }
        if let profile = profiles.create(name: name, avatarID: avatarID, colorHex: colorHex) {
            profiles.select(profile.id)
        }
        finish()
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        onFinished()
    }
}

// MARK: - Poster wall

/// Rows of posters drifting slowly in alternate directions, tilted, behind
/// the welcome. Placeholder cards stand in until artwork loads.
private struct PosterWall: View {
    let items: [MediaItem]
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let posterSize = CGSize(width: 120, height: 180)
    private let spacing: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(paused: reduceMotion)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                VStack(spacing: spacing) {
                    ForEach(0..<5, id: \.self) { row in
                        posterRow(row, time: time, width: proxy.size.width * 1.6)
                    }
                }
                .rotationEffect(.degrees(-12))
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .opacity(colorScheme == .dark ? 0.55 : 0.4)
        .overlay {
            RadialGradient(
                colors: [.clear, Color.omniaWindowBackground.opacity(0.9)],
                center: .center, startRadius: 120, endRadius: 720
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func posterRow(_ row: Int, time: TimeInterval, width: CGFloat) -> some View {
        let step = posterSize.width + spacing
        let count = Int(width / step) + 3
        let speed = 9.0 + Double(row % 3) * 3
        let direction: Double = row.isMultiple(of: 2) ? -1 : 1
        let shift = (time * speed * direction).truncatingRemainder(dividingBy: step)
        return HStack(spacing: spacing) {
            ForEach(0..<count, id: \.self) { column in
                poster(at: row * 7 + column)
            }
        }
        .offset(x: shift - step)
        .frame(width: width)
    }

    @ViewBuilder
    private func poster(at index: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        if items.isEmpty {
            shape
                .fill(LinearGradient(
                    colors: [OmniaBrandColors.violet.opacity(0.35), OmniaBrandColors.teal.opacity(0.25)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: posterSize.width, height: posterSize.height)
        } else {
            CachedArtworkImage(url: items[index % items.count].artworkURL, size: posterSize) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(width: posterSize.width, height: posterSize.height)
            .clipShape(shape)
        }
    }
}

// MARK: - App preview

/// Uses the shipping screens, with side effects suppressed by preview mode.
private struct AppPreview: View {
    let items: [MediaItem]
    let isLoading: Bool
    let retry: () -> Void
    @State private var previewMetadata = LiveMetadataStore(loadsBundleConfiguration: false)
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var page: Page = .home
    @State private var previewStore = OmniaStore(
        library: [], installedAddons: [], disabledAddonCatalogIDs: [],
        appearance: .system, metadataRouting: .init()
    )
    @State private var previewDefaults = UserDefaults(suiteName: "Omnia.OnboardingPreview")!

    private enum Page: String, CaseIterable, Identifiable {
        case home = "Home"
        case details = "Title Details"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 12) {
            Picker("Preview screen", selection: $page) {
                ForEach(Page.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(items.isEmpty)

            GeometryReader { geometry in
                ZStack {
                    if !items.isEmpty {
                        NavigationStack {
                            Group {
                                switch page {
                                case .home: HomeView()
                                case .details:
                                    if let item = items.first { MediaDetailView(item: item) }
                                }
                            }
                            .environment(previewStore)
                            .environment(previewMetadata)
                            .environment(\.isOnboardingPreview, true)
                            .environment(\.isActiveDestination, false)
                            .environment(\.displayPreferences, DisplayPreferences())
                            .defaultAppStorage(previewDefaults)
                        }
                        .frame(width: 1100, height: 720)
                        .disabled(true)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .scaleEffect(geometry.size.width / 1100, anchor: .topLeading)
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                    } else if isLoading {
                        OmniaLoadingRow("Loading Omnia preview…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ContentUnavailableView {
                            Label("Preview Unavailable", systemImage: "wifi.exclamationmark")
                        } description: {
                            Text("You can continue setup and browse when discovery is available.")
                        } actions: {
                            Button("Retry", action: retry)
                        }
                    }
                }
            }
            .aspectRatio(1100.0 / 720.0, contentMode: .fit)
            .background(reduceTransparency ? AnyShapeStyle(.background) : AnyShapeStyle(.regularMaterial))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.separator)
            }

            Text("Live preview · \(page.rawValue) · Read-only")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task(id: items.map(\.id)) {
            let movies = items.filter { $0.kind == .movie }
            let series = items.filter { $0.kind != .movie }
            previewMetadata.topMovies = movies
            previewMetadata.topSeries = series
            previewMetadata.movieCatalog = movies
            previewMetadata.seriesCatalog = series
            previewMetadata.homeCatalogs = [
                BuiltInHomeCatalog(shelf: .popularMovies, items: movies),
                BuiltInHomeCatalog(shelf: .popularSeries, items: series),
            ].filter { !$0.items.isEmpty }
        }
    }
}

/// A feature line that slides in after the ones above it.
private struct StaggeredFeature: View {
    let index: Int
    let symbol: String
    let title: String
    let detail: String
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(OmniaBrandColors.gradient)
                .frame(width: 34)
                .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : shown)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .opacity(shown ? 1 : 0)
        .offset(x: reduceMotion || shown ? 0 : 24)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.85).delay(0.25 + Double(index) * 0.14)) {
                shown = true
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Read-only onboarding catalog source

/// Reads public catalog metadata without installing sources or touching the library.
@MainActor
@Observable
private final class OnboardingPreviewSource {
    var items: [MediaItem] = []
    var isLoading = true

    static func uniqueItems(_ candidates: [MediaItem]) -> [MediaItem] {
        var seen = Set<String>()
        return Array(candidates.filter { $0.artworkURL != nil && seen.insert($0.id).inserted }.prefix(24))
    }

    func load(store: OmniaStore, existing: [MediaItem]) async {
        isLoading = true
        defer { isLoading = false }
        let loaded = Self.uniqueItems(existing)
        if !loaded.isEmpty {
            items = loaded
            return
        }
        var catalogs = AddonCatalogStore.catalogs(in: store).filter {
            store.isCatalogEnabled(for: $0.addon, catalog: $0.catalog)
        }
        do {
            try Task.checkCancellation()
            // The app already uses Cinemeta as its default public catalog.
            // This local value is never installed or persisted.
            if catalogs.isEmpty, let address = OmniaStore.defaultAddonManifestURLs.first,
               let url = URL(string: address) {
                let manifest = try await StremioAddonClient.fetchManifest(from: url)
                try Task.checkCancellation()
                let addon = InstalledAddon(manifest: manifest, manifestURL: url, isEnabled: true, addedAt: .now)
                catalogs = manifest.catalogs.filter {
                    $0.canLoadWithoutExtra && $0.showInHome != false && AddonHomeCatalog.isSupportedType($0.type)
                }.map { AddonHomeCatalog(key: $0.id, addon: addon, catalog: $0) }
            }
            for catalog in catalogs.prefix(3) {
                try Task.checkCancellation()
                do {
                    let previews = try await StremioAddonClient.fetchCatalog(from: catalog.addon, catalog: catalog.catalog)
                    try Task.checkCancellation()
                    items = Self.uniqueItems(items + previews.prefix(24).compactMap { $0.mediaItem(addon: catalog.addon) })
                    if items.count >= 24 { break }
                } catch is CancellationError {
                    throw CancellationError()
                } catch HTTPTransportError.cancelled {
                    throw CancellationError()
                } catch {
                    try Task.checkCancellation()
                    // Preserve successful rows if a later source is unavailable.
                }
            }
        } catch is CancellationError {
            return
        } catch HTTPTransportError.cancelled {
            return
        } catch {
            // Empty content keeps the accessible retry and setup actions available.
        }
    }
}
