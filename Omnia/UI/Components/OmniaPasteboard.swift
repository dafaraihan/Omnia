import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum OmniaPasteboard {
    @MainActor
    static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    /// For text that works as a credential, such as an add-on link with a
    /// token in it: not sent to other devices or kept by clipboard managers,
    /// and on iOS gone after two minutes.
    @MainActor
    static func copySensitive(_ text: String) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")], owner: nil)
        pasteboard.setString(text, forType: .string)
        #else
        UIPasteboard.general.setItems(
            [[UIPasteboard.typeAutomatic: text]],
            options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(120)]
        )
        #endif
    }
}
