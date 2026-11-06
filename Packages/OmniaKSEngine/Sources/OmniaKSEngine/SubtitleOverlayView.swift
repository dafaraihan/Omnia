//
//  SubtitleOverlayView.swift
//  OmniaKSEngine
//
//  Draws KSPlayer's subtitle cues with the style Omnia gives mpv, so a
//  subtitle looks the same whichever engine plays it.
//

import Foundation
#if canImport(UIKit)
import UIKit
typealias OverlayFont = UIFont
typealias OverlayColor = UIColor
typealias OverlayImage = UIImage
#else
import AppKit
typealias OverlayFont = NSFont
typealias OverlayColor = NSColor
typealias OverlayImage = NSImage
#endif

/// mpv's subtitle options, read from the same keys.
struct SubtitleStyle {
    var font = "sans-serif"
    /// mpv's sub-font-size, measured against a 720-pixel-high video.
    var fontSize = 42.0
    var scale = 1.0
    /// mpv's sub-pos: 100 at the bottom.
    var position = 95.0
    var textColor = OverlayColor.white
    var outlineColor = OverlayColor.black
    var outlineSize = 1.65
    var shadowOpacity = 0.65
    var shadowBlur = 2.0
    var background = "none"
    var backgroundRGB = "000000"
    var bold = false
    var italic = false
    var alignment = "center"
    /// Horizontal margin as a percentage of the width.
    var margin = 0.0

    mutating func merge(_ values: [String: Any]) {
        if let value = values["font"] as? String, !value.isEmpty, value.count <= 128 { font = value }
        if let value = Self.number(values["fontSize"]) { fontSize = min(max(value, 8), 200) }
        if let value = Self.number(values["scale"]) { scale = min(max(value, 0.2), 5) }
        if let value = Self.number(values["position"]) { position = min(max(value, 0), 150) }
        if let value = values["textColor"] as? String, let color = Self.color(value) { textColor = color }
        if let value = values["outlineColor"] as? String, let color = Self.color(value) { outlineColor = color }
        if let value = Self.number(values["outlineSize"]) { outlineSize = min(max(value, 0), 20) }
        if let value = Self.number(values["shadowOpacity"]) { shadowOpacity = min(max(value, 0), 1) }
        if let value = Self.number(values["shadowBlur"]) { shadowBlur = min(max(value, 0), 20) }
        if let value = values["background"] as? String { background = value }
        if let value = values["backgroundRGB"] as? String, value.count == 6 { backgroundRGB = value }
        if let value = values["bold"] as? Bool { bold = value }
        if let value = values["italic"] as? Bool { italic = value }
        if let value = values["alignment"] as? String { alignment = value }
        if let value = Self.number(values["margin"]) { margin = min(max(value, 0), 40) }
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double, value.isFinite { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber, value.doubleValue.isFinite { return value.doubleValue }
        return nil
    }

    /// "#RRGGBB", or mpv's "#AARRGGBB".
    static func color(_ string: String) -> OverlayColor? {
        var hex = string.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else { return nil }
        let alpha: Double
        let rgb: UInt64
        if hex.count == 8 {
            alpha = Double((value >> 24) & 0xFF) / 255
            rgb = value & 0xFFFFFF
        } else {
            alpha = 1
            rgb = value
        }
        return OverlayColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: CGFloat(alpha)
        )
    }
}

final class SubtitleOverlayView: OmniaKSView {
    struct Cue: Equatable {
        let text: String?
        let image: OverlayImage?

        static func == (lhs: Cue, rhs: Cue) -> Bool {
            lhs.text == rhs.text && lhs.image === rhs.image
        }
    }

    var style = SubtitleStyle()
    var stripsSDH = false
    private var cues: [Cue] = []
    #if canImport(UIKit)
    private let label = UILabel()
    private let imageView = UIImageView()
    #else
    private let label = NSTextField(labelWithString: "")
    private let imageView = NSImageView()
    #endif

    override init(frame: CGRect) {
        super.init(frame: frame)
        #if canImport(UIKit)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        label.numberOfLines = 0
        label.layer.cornerRadius = 4
        label.layer.masksToBounds = true
        imageView.contentMode = .scaleAspectFit
        #else
        wantsLayer = true
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.wantsLayer = true
        label.layer?.cornerRadius = 4
        imageView.imageScaling = .scaleProportionallyUpOrDown
        #endif
        label.isHidden = true
        imageView.isHidden = true
        addSubview(imageView)
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        nil
    }

    #if os(macOS)
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    #endif

    func show(_ cues: [Cue]) {
        guard cues != self.cues else { return }
        self.cues = cues
        restyle()
    }

    func restyle() {
        let lines = cues.compactMap(\.text).map(cleaned).filter { !$0.isEmpty }
        let text = lines.joined(separator: "\n")
        if text.isEmpty {
            label.isHidden = true
        } else {
            label.isHidden = false
            #if canImport(UIKit)
            label.attributedText = attributed(text)
            label.textAlignment = alignment
            #else
            label.attributedStringValue = attributed(text)
            label.alignment = alignment
            #endif
            let box = style.background != "none"
            let alpha = style.background == "solid" ? 0.9 : 0.55
            let color = SubtitleStyle.color(style.backgroundRGB)?.withAlphaComponent(CGFloat(alpha))
            #if canImport(UIKit)
            label.backgroundColor = box ? color : .clear
            #else
            label.drawsBackground = box
            label.backgroundColor = box ? color : .clear
            #endif
        }
        let image = cues.compactMap(\.image).first
        imageView.image = image
        imageView.isHidden = image == nil
        #if canImport(UIKit)
        setNeedsLayout()
        #else
        needsLayout = true
        #endif
    }

    #if canImport(UIKit)
    override func layoutSubviews() {
        super.layoutSubviews()
        place()
    }
    #else
    override func layout() {
        super.layout()
        place()
    }
    #endif

    /// mpv sizes subtitles against a 720-pixel-high picture.
    private var pointScale: CGFloat { max(bounds.height, 1) / 720 }

    private func place() {
        let width = bounds.width
        let height = bounds.height
        guard width > 0, height > 0 else { return }
        let side = width * CGFloat(style.margin) / 100 + 16
        let maxWidth = max(width - side * 2, 40)
        let bottom = height * CGFloat(min(style.position, 100)) / 100 - height * 0.03
        if !label.isHidden {
            let padding: CGFloat = style.background == "none" ? 0 : 8
            var size = label.sizeThatFits(CGSize(width: maxWidth - padding * 2, height: height))
            size.width = min(size.width, maxWidth - padding * 2) + padding * 2
            size.height += padding
            let x: CGFloat = switch style.alignment {
            case "left": side
            case "right": width - side - size.width
            default: (width - size.width) / 2
            }
            label.frame = CGRect(x: x, y: max(bottom - size.height, 0), width: size.width, height: size.height)
        }
        if let image = imageView.image, !imageView.isHidden {
            let factor = height / 1080
            var size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
            if size.width > maxWidth {
                size = CGSize(width: maxWidth, height: size.height * maxWidth / size.width)
            }
            imageView.frame = CGRect(x: (width - size.width) / 2, y: max(bottom - size.height, 0), width: size.width, height: size.height)
        }
    }

    private var alignment: NSTextAlignment {
        switch style.alignment {
        case "left": .left
        case "right": .right
        default: .center
        }
    }

    private func attributed(_ text: String) -> NSAttributedString {
        let size = CGFloat(style.fontSize * style.scale) * pointScale
        let font = Self.font(named: style.font, size: max(size, 8), bold: style.bold, italic: style.italic)
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: style.textColor,
        ]
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        attributes[.paragraphStyle] = paragraph
        if style.outlineSize > 0, style.background == "none" {
            // A negative stroke width fills and outlines; it's a percentage
            // of the font size.
            let outline = CGFloat(style.outlineSize) * pointScale
            attributes[.strokeColor] = style.outlineColor
            attributes[.strokeWidth] = -(outline / font.pointSize) * 100 * 1.6
        }
        if style.shadowOpacity > 0, style.background == "none" {
            let shadow = NSShadow()
            shadow.shadowColor = OverlayColor.black.withAlphaComponent(CGFloat(style.shadowOpacity))
            shadow.shadowOffset = CGSize(width: 0, height: 2 * pointScale)
            shadow.shadowBlurRadius = CGFloat(style.shadowBlur) * pointScale
            attributes[.shadow] = shadow
        }
        return NSAttributedString(string: text, attributes: attributes)
    }

    private static func font(named name: String, size: CGFloat, bold: Bool, italic: Bool) -> OverlayFont {
        let generic = ["sans-serif", "sans", "system", ""].contains(name.lowercased())
        #if canImport(UIKit)
        var font = generic ? UIFont.systemFont(ofSize: size, weight: bold ? .bold : .semibold)
            : (UIFont(name: name, size: size) ?? UIFont.systemFont(ofSize: size, weight: .semibold))
        var traits = font.fontDescriptor.symbolicTraits
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
            font = UIFont(descriptor: descriptor, size: size)
        }
        return font
        #else
        var font = generic ? NSFont.systemFont(ofSize: size, weight: bold ? .bold : .semibold)
            : (NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size, weight: .semibold))
        var traits = font.fontDescriptor.symbolicTraits
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        font = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits), size: size) ?? font
        return font
        #endif
    }

    // MARK: SDH

    private static let bracketed = try? NSRegularExpression(pattern: "\\[[^\\]]*\\]|\\([^)]*\\)|♪[^♪]*♪?")
    private static let speaker = try? NSRegularExpression(pattern: "^\\s*-?\\s*[A-Z][A-Z0-9 .'-]{1,30}:\\s*", options: [.anchorsMatchLines])

    /// Strip SDH removes sound descriptions and speaker names, as mpv's
    /// sub-filter-sdh does.
    private func cleaned(_ text: String) -> String {
        guard stripsSDH else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        var value = text
        for expression in [Self.bracketed, Self.speaker].compactMap({ $0 }) {
            value = expression.stringByReplacingMatches(
                in: value,
                range: NSRange(value.startIndex..., in: value),
                withTemplate: ""
            )
        }
        return value
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "-" }
            .joined(separator: "\n")
    }
}
