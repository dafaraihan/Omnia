//
//  JustifiedSynopsisText.swift
//  Omnia
//

import SwiftUI

/// A native text control is used because SwiftUI's `Text` does not reliably
/// honour paragraph justification from an attributed string on every target.
struct JustifiedSynopsisText: View {
    let text: String
    var lineLimit: Int?
    var fontSize: CGFloat = 13

    var body: some View {
        #if os(macOS)
        JustifiedMacText(text: text, lineLimit: lineLimit, fontSize: fontSize)
        #else
        JustifiedUIKitText(text: text, lineLimit: lineLimit, fontSize: fontSize)
        #endif
    }
}

#if os(macOS)
import AppKit

private struct JustifiedMacText: NSViewRepresentable {
    let text: String
    let lineLimit: Int?
    let fontSize: CGFloat

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.isEditable = false
        field.isSelectable = false
        field.drawsBackground = false
        field.usesSingleLineMode = false
        // NSTextField only grows to the requested number of lines when its
        // paragraph mode permits wrapping. The synopsis itself opens in a
        // sheet, so showing complete words is preferable to a one-line tail.
        field.lineBreakMode = .byWordWrapping
        field.alignment = .justified
        field.font = .systemFont(ofSize: fontSize)
        field.textColor = .white.withAlphaComponent(0.88)
        field.maximumNumberOfLines = lineLimit ?? 0
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        field.stringValue = text
        field.font = .systemFont(ofSize: fontSize)
        field.maximumNumberOfLines = lineLimit ?? 0
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView field: NSTextField, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        field.preferredMaxLayoutWidth = width
        field.frame.size.width = width
        return CGSize(width: width, height: field.fittingSize.height)
    }
}
#else
import UIKit

private struct JustifiedUIKitText: UIViewRepresentable {
    let text: String
    let lineLimit: Int?
    let fontSize: CGFloat

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = lineLimit ?? 0
        label.lineBreakMode = .byWordWrapping
        label.textAlignment = .justified
        label.font = .systemFont(ofSize: fontSize)
        label.textColor = .white.withAlphaComponent(0.88)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.text = text
        label.font = .systemFont(ofSize: fontSize)
        label.numberOfLines = lineLimit ?? 0
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView label: UILabel, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }
}
#endif
