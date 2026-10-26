//
//  ContentWarningClient.swift
//  Omnia
//
//  Nuvio's Parental Guide (ParentalGuideRepository.kt, NuvioMedia/NuvioMobile,
//  GPL-3.0): IMDb's parents guide through the same api.tiffara.com mirror.
//

import Foundation

/// One content warning, such as "Violence · Severe".
nonisolated struct ContentWarning: Equatable, Hashable, Sendable {
    enum Severity: Int, Comparable, Sendable {
        case severe, moderate, mild

        var title: String {
            switch self {
            case .severe: "Severe"
            case .moderate: "Moderate"
            case .mild: "Mild"
            }
        }

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    let category: String
    let severity: Severity
}

actor ContentWarningClient {
    static let shared = ContentWarningClient()

    private var cache: [String: [ContentWarning]] = [:]
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        return URLSession(configuration: configuration)
    }()

    /// Categories IMDb voters rated above "none", most severe first.
    func warnings(forIMDbID value: String) async -> [ContentWarning] {
        guard let imdbID = Self.imdbID(in: value) else { return [] }
        if let cached = cache[imdbID] { return cached }
        guard let url = URL(string: "https://api.tiffara.com/titles/\(imdbID)/parentsGuide") else { return [] }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              (200..<300).contains((response as? HTTPURLResponse)?.statusCode ?? 0),
              let body = try? JSONDecoder().decode(Response.self, from: data)
        else { return [] }
        let warnings = Self.warnings(from: body.parentsGuide)
        cache[imdbID] = warnings
        return warnings
    }

    static func warnings(from categories: [Response.Category]) -> [ContentWarning] {
        let names: [(key: String, title: String)] = [
            ("SEXUAL_CONTENT", "Sex & Nudity"),
            ("VIOLENCE", "Violence"),
            ("PROFANITY", "Language"),
            ("ALCOHOL_DRUGS", "Alcohol & Drugs"),
            ("FRIGHTENING_INTENSE_SCENES", "Frightening Scenes")
        ]
        let byKey = Dictionary(categories.map { ($0.category.uppercased(), $0) }, uniquingKeysWith: { first, _ in first })
        return names.compactMap { name in
            guard let category = byKey[name.key], let severity = severity(of: category) else { return nil }
            return ContentWarning(category: name.title, severity: severity)
        }
        .sorted { $0.severity < $1.severity }
    }

    /// The level most voters chose, when it outvotes "none".
    private static func severity(of category: Response.Category) -> ContentWarning.Severity? {
        let breakdowns = category.severityBreakdowns ?? []
        let none = breakdowns.first { $0.severityLevel.lowercased() == "none" }?.voteCount ?? 0
        guard let dominant = breakdowns.filter({ $0.severityLevel.lowercased() != "none" }).max(by: { $0.voteCount < $1.voteCount }),
              dominant.voteCount > none
        else { return nil }
        switch dominant.severityLevel.lowercased() {
        case "severe": return .severe
        case "moderate": return .moderate
        case "mild": return .mild
        default: return nil
        }
    }

    private static func imdbID(in value: String) -> String? {
        guard let range = value.range(of: #"tt\d{5,10}"#, options: .regularExpression) else { return nil }
        return String(value[range])
    }

    struct Response: Decodable, Sendable {
        struct Category: Decodable, Sendable {
            let category: String
            let severityBreakdowns: [Breakdown]?
        }

        struct Breakdown: Decodable, Sendable {
            let severityLevel: String
            let voteCount: Int
        }

        let parentsGuide: [Category]
    }
}
