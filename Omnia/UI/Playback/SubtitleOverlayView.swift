import SwiftUI

struct SubtitleOverlayView: View {
    let cues: [SubtitleCue]
    let appearance: SubtitleAppearance

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack {
            if appearance.position == .bottom { Spacer() }
            Text(cues.map(\.text).joined(separator: "\n"))
                .font(.system(size: 20 * CGFloat(appearance.normalized.textScalePercent) / 100,
                              weight: appearance.isBold ? .bold : .regular))
                .italic(appearance.isItalic)
                .multilineTextAlignment(textAlignment)
                .foregroundStyle(textColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(backgroundColor, in: RoundedRectangle(cornerRadius: 6))
                .shadow(color: shadowColor, radius: 2, y: 1)
                .frame(maxWidth: .infinity, alignment: frameAlignment)
                .padding(.horizontal, CGFloat(appearance.normalized.horizontalMarginPercent) / 100 * 500)
                .accessibilityHidden(true)
            if appearance.position == .top { Spacer() }
        }
        .padding(.vertical)
        .allowsHitTesting(false)
    }

    private var textAlignment: TextAlignment {
        switch appearance.alignment { case .leading: .leading; case .center: .center; case .trailing: .trailing }
    }

    private var frameAlignment: Alignment {
        switch appearance.alignment { case .leading: .leading; case .center: .center; case .trailing: .trailing }
    }

    private var textColor: Color { appearance.textColor == .yellow ? .yellow : appearance.textColor == .black ? .black : .white }
    private var backgroundColor: Color {
        let opacity = reduceTransparency ? max(Double(appearance.backgroundOpacityPercent) / 100, 0.85) : Double(appearance.backgroundOpacityPercent) / 100
        return .black.opacity(contrast == .increased ? max(opacity, 0.75) : opacity)
    }
    private var shadowColor: Color {
        switch appearance.edgeStyle { case .shadow, .outlineAndShadow: .black; default: .clear }
    }
}
