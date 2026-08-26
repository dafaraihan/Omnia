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

/// The shared primary and library actions used by Omnia's cinematic heroes.
/// Keeping this component shared prevents Home and title detail from drifting
/// into subtly different button sizes or spacing.
struct HeroActionRow<Primary: View>: View {
    let width: CGFloat
    let isSaved: Bool
    let libraryAction: () -> Void
    private let primary: Primary

    init(
        width: CGFloat,
        isSaved: Bool,
        libraryAction: @escaping () -> Void,
        @ViewBuilder primary: () -> Primary
    ) {
        self.width = width
        self.isSaved = isSaved
        self.libraryAction = libraryAction
        self.primary = primary()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                primary
                libraryButton
            }

            VStack(alignment: .leading, spacing: 10) {
                primary
                libraryButton
            }
        }
        // The action group belongs to the same leading identity column as the
        // transparent logo, metadata, and synopsis.
        .frame(width: width, alignment: .leading)
    }

    private var libraryButton: some View {
        Button(action: libraryAction) {
            Image(systemName: isSaved ? "checkmark" : "plus")
                .font(.body.weight(.semibold))
                .foregroundStyle(actionForeground)
                .frame(width: 46, height: 46)
                .background(actionBackground, in: Circle())
        }
        .buttonStyle(.plain)
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
    let title: String

    var body: some View {
        Label(title, systemImage: "play.fill")
            .font(.body.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 18)
            // A stable, longer primary hit target makes Play, Resume, and
            // Rewatch feel like the same deliberate playback action.
            .frame(minWidth: 176, minHeight: 46)
            .background(.white, in: Capsule())
    }
}
