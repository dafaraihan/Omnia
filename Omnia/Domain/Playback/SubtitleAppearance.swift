import Foundation

struct SubtitleAppearance: Codable, Equatable, Sendable {
    enum SemanticColor: String, Codable, CaseIterable, Sendable {
        case white
        case yellow
        case black
    }

    enum EdgeStyle: String, Codable, CaseIterable, Sendable {
        case none
        case outline
        case shadow
        case outlineAndShadow
    }

    enum Position: String, Codable, CaseIterable, Sendable {
        case top
        case middle
        case bottom
    }

    enum Alignment: String, Codable, CaseIterable, Sendable {
        case leading
        case center
        case trailing
    }

    var textScalePercent: Int
    var textColor: SemanticColor
    var outlineColor: SemanticColor
    var backgroundColor: SemanticColor
    var backgroundOpacityPercent: Int
    var edgeStyle: EdgeStyle
    var position: Position
    var alignment: Alignment
    var horizontalMarginPercent: Int
    var isBold: Bool
    var isItalic: Bool

    static let `default` = SubtitleAppearance(
        textScalePercent: 100,
        textColor: .white,
        outlineColor: .black,
        backgroundColor: .black,
        backgroundOpacityPercent: 0,
        edgeStyle: .outline,
        position: .bottom,
        alignment: .center,
        horizontalMarginPercent: 5,
        isBold: false,
        isItalic: false
    )

    static let standard = Self.default
    static let boxed = SubtitleAppearance(
        textScalePercent: 100, textColor: .white, outlineColor: .black,
        backgroundColor: .black, backgroundOpacityPercent: 70, edgeStyle: .none,
        position: .bottom, alignment: .center, horizontalMarginPercent: 5,
        isBold: false, isItalic: false
    )
    static let classic = SubtitleAppearance(
        textScalePercent: 100, textColor: .yellow, outlineColor: .black,
        backgroundColor: .black, backgroundOpacityPercent: 0, edgeStyle: .outline,
        position: .bottom, alignment: .center, horizontalMarginPercent: 5,
        isBold: false, isItalic: false
    )
    static let minimal = SubtitleAppearance(
        textScalePercent: 95, textColor: .white, outlineColor: .black,
        backgroundColor: .black, backgroundOpacityPercent: 0, edgeStyle: .shadow,
        position: .bottom, alignment: .center, horizontalMarginPercent: 5,
        isBold: false, isItalic: false
    )
    static let bold = SubtitleAppearance(
        textScalePercent: 125, textColor: .white, outlineColor: .black,
        backgroundColor: .black, backgroundOpacityPercent: 0, edgeStyle: .outlineAndShadow,
        position: .bottom, alignment: .center, horizontalMarginPercent: 5,
        isBold: true, isItalic: false
    )

    var usesBackground: Bool { backgroundOpacityPercent > 0 }

    var normalized: SubtitleAppearance {
        var value = self
        value.textScalePercent = Self.stepped(value.textScalePercent, range: 75 ... 200)
        value.backgroundOpacityPercent = Self.stepped(value.backgroundOpacityPercent, range: 0 ... 100)
        value.horizontalMarginPercent = min(max(value.horizontalMarginPercent, 0), 15)
        return value
    }

    func reset() -> SubtitleAppearance { .default }

    private static func stepped(_ value: Int, range: ClosedRange<Int>) -> Int {
        let bounded = min(max(value, range.lowerBound), range.upperBound)
        return Int((Double(bounded) / 5).rounded()) * 5
    }
}
