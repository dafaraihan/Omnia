//
//  PlaybackTrack.swift
//  Omnia
//

import Foundation

struct PlaybackTrack: Identifiable, Equatable, Sendable {
    let id: Int
    let title: String?
    let language: String?
    let codec: String?
    let isSelected: Bool

    var displayName: String {
        let cleanTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        let languageName = languageDisplayName
        if let cleanTitle, let languageName { return "\(cleanTitle) · \(languageName)" }
        if let cleanTitle { return cleanTitle }
        if let languageName { return languageName }
        return "Track \(id)"
    }

    private var languageDisplayName: String? {
        guard let code = language?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().nonEmpty else {
            return nil
        }
        return Locale(identifier: "en").localizedString(forLanguageCode: code) ?? code.uppercased()
    }

    #if os(macOS)
    init(_ track: OMMpvTrack) {
        id = track.trackID
        title = track.title
        language = track.language
        codec = track.codec
        isSelected = track.isSelected
    }
    #endif

    init(id: Int, title: String?, language: String?, codec: String?, isSelected: Bool) {
        self.id = id
        self.title = title
        self.language = language
        self.codec = codec
        self.isSelected = isSelected
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
