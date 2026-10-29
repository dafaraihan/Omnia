//
//  HeroActionRow.swift
//  Omnia
//

import SwiftUI

/// Resolves visual feedback from states already owned by SwiftUI's Button.
/// Interactive controls must not add a zero-distance drag recognizer merely
/// to observe presses because that recognizer competes with clicks in shelves.
enum ButtonInteractionPresentation {
    static func isActive(isHovered: Bool, isPressed: Bool) -> Bool {
        isHovered || isPressed
    }
}

struct HeroWatchAction {
    let systemImage: String
    let accessibilityLabel: String
    let perform: () -> Void
    var isEnabled = true
}

/// The shared primary and library actions used by Omnia's cinematic heroes.
/// Keeping this component shared prevents Home and title detail from drifting
/// into subtly different button sizes or spacing.
struct HeroActionRow<Primary: View>: View {
    @Environment(\.controlSize) private var controlSize
    let width: CGFloat
    let isSaved: Bool
    let libraryAction: () -> Void
    let watchAction: HeroWatchAction?
    /// Settings › Layout › Detail Page › Shuffle, on a show's page.
    let shuffleAction: HeroWatchAction?
    private let primary: Primary

    init(
        width: CGFloat,
        isSaved: Bool,
        libraryAction: @escaping () -> Void,
        watchAction: HeroWatchAction? = nil,
        shuffleAction: HeroWatchAction? = nil,
        @ViewBuilder primary: () -> Primary
    ) {
        self.width = width
        self.isSaved = isSaved
        self.libraryAction = libraryAction
        self.watchAction = watchAction
        self.shuffleAction = shuffleAction
        self.primary = primary()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                primary
                if let shuffleAction {
                    watchButton(action: shuffleAction)
                }
                if let watchAction {
                    watchButton(action: watchAction)
                }
                libraryButton
            }

            VStack(alignment: .center, spacing: 10) {
                primary
                HStack(spacing: 10) {
                    if let shuffleAction {
                        watchButton(action: shuffleAction)
                    }
                    if let watchAction {
                        watchButton(action: watchAction)
                    }
                    libraryButton
                }
            }
        }
        // The action group belongs to the same leading identity column as the
        // transparent logo, metadata, and synopsis.
        .frame(width: width, alignment: watchAction == nil ? .leading : .center)
    }

    private func watchButton(action: HeroWatchAction) -> some View {
        Button(action: action.perform) {
            Image(systemName: action.systemImage)
                .font(.body.weight(.semibold))
                #if os(macOS)
                .foregroundStyle(.white)
                #else
                .foregroundStyle(actionForeground)
                #endif
                .frame(width: controlSize == .small ? 44 : 46, height: controlSize == .small ? 44 : 46)
                .contentShape(Circle())
                #if !os(macOS)
                .background(actionBackground, in: Circle())
                #endif
        }
        #if os(macOS)
        .omniaCircularGlassButton()
        #else
        .buttonStyle(.plain)
        #endif
        .disabled(!action.isEnabled)
        .accessibilityLabel(action.accessibilityLabel)
    }

    private var libraryButton: some View {
        Button(action: libraryAction) {
            Image(systemName: isSaved ? "checkmark" : "plus")
                .font(.body.weight(.semibold))
                #if os(macOS)
                .foregroundStyle(.white)
                #else
                .foregroundStyle(actionForeground)
                #endif
                .frame(width: controlSize == .small ? 44 : 46, height: controlSize == .small ? 44 : 46)
                .contentShape(Circle())
                #if !os(macOS)
                .background(actionBackground, in: Circle())
                #endif
        }
        #if os(macOS)
        .omniaCircularGlassButton()
        #else
        .buttonStyle(.plain)
        #endif
        .accessibilityLabel(isSaved ? "In My List" : "Add to My List")
    }

    // Playback and library actions retain their high-contrast white treatment
    // over artwork in both appearances; page appearance must not alter their
    // cinematic affordance.
    private var actionBackground: Color { .white }
    private var actionForeground: Color { .black }
}

/// The identically styled primary pill used in every cinematic hero.
struct HeroPrimaryActionLabel: View {
    @Environment(\.controlSize) private var controlSize
    let title: String
    var resumeProgress: ResumeProgressPresentation?

    var body: some View {
        HStack(spacing: 8) {
            Label(title, systemImage: "play.fill")
                .font(.body.weight(.semibold))
                .fixedSize()

            if let resumeProgress {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(resumeProgress.heroMetadataText)
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    ResumeProgressBar(progress: resumeProgress.progress)
                }
                .frame(width: 56)
            }
        }
            #if os(macOS)
            .foregroundStyle(.white)
            #else
            .foregroundStyle(.black)
            #endif
            .padding(.horizontal, 14)
            // A stable, longer primary hit target makes Play, Resume, and
            // Rewatch feel like the same deliberate playback action.
            .frame(width: controlSize == .small ? 160 : 176, height: controlSize == .small ? 44 : 46)
            .contentShape(Capsule())
            #if !os(macOS)
            .background(.white, in: Capsule())
            #endif
    }
}
