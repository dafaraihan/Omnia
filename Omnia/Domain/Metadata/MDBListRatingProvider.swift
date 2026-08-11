import Foundation

nonisolated struct MDBListRatingProviderID: RawRepresentable, Codable, Hashable, Comparable, Sendable {
    let rawValue: String

    init?(_ source: String) {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.unicodeScalars.allSatisfy({ $0.isASCII }) else {
            return nil
        }

        let normalized = trimmed.lowercased()
        let aliasKey = normalized.filter { character in
            character.isASCII && (character.isLetter || character.isNumber)
        }
        if let canonical = Self.aliases[aliasKey] {
            self.init(canonical: canonical)
            return
        }

        guard normalized.count <= 64,
              normalized.unicodeScalars.allSatisfy(Self.isAllowed) else {
            return nil
        }
        self.init(canonical: normalized)
    }

    init?(rawValue: String) {
        self.init(rawValue)
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let source = try container.decode(String.self)
        guard let value = Self(source) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid MDBList rating provider identifier"
            )
        }
        self = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static let imdb = Self(canonical: "imdb")
    static let tmdb = Self(canonical: "tmdb")
    static let rottenTomatoes = Self(canonical: "tomatoes")
    static let metacritic = Self(canonical: "metacritic")
    static let trakt = Self(canonical: "trakt")
    static let letterboxd = Self(canonical: "letterboxd")
    static let rottenTomatoesAudience = Self(canonical: "popcorn")
    static let myAnimeList = Self(canonical: "myanimelist")
    static let rogerEbert = Self(canonical: "rogerebert")

    private init(canonical: String) {
        rawValue = canonical
    }

    private static let aliases: [String: String] = [
        "imdb": imdb.rawValue,
        "tmdb": tmdb.rawValue,
        "themoviedatabase": tmdb.rawValue,
        "tomatoes": rottenTomatoes.rawValue,
        "rottentomatoes": rottenTomatoes.rawValue,
        "rottentomatoescritics": rottenTomatoes.rawValue,
        "rtcritics": rottenTomatoes.rawValue,
        "metacritic": metacritic.rawValue,
        "trakt": trakt.rawValue,
        "letterboxd": letterboxd.rawValue,
        "popcorn": rottenTomatoesAudience.rawValue,
        "tomatoesaudience": rottenTomatoesAudience.rawValue,
        "rottentomatoesaudience": rottenTomatoesAudience.rawValue,
        "popcornmeter": rottenTomatoesAudience.rawValue,
        "mal": myAnimeList.rawValue,
        "myanimelist": myAnimeList.rawValue,
        "rogerebert": rogerEbert.rawValue
    ]

    private static func isAllowed(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 48...57, 97...122:
            true
        case 45, 46, 95:
            true
        default:
            false
        }
    }
}

nonisolated enum MDBListRatingValueFormat: Hashable, Sendable {
    case number
    case percentage
}

nonisolated struct MDBListRatingProviderDescriptor: Identifiable, Hashable, Sendable {
    let id: MDBListRatingProviderID
    let displayName: String
    let order: Int?
    let valueFormat: MDBListRatingValueFormat
    let defaultAssetName: String?
    let negativeAssetName: String?
    let negativeBelow: Double?

    var approvedAssetName: String? { defaultAssetName }
}

nonisolated enum MDBListRatingProviderRegistry {
    static let knownDescriptors: [MDBListRatingProviderDescriptor] = [
        descriptor(.imdb, "IMDb", order: 0, assetName: "RatingIMDbMark"),
        descriptor(.tmdb, "TMDB", order: 1, assetName: "RatingTMDBMark"),
        descriptor(
            .rottenTomatoes,
            "Rotten Tomatoes",
            order: 2,
            format: .percentage,
            assetName: "RatingRottenTomatoesFreshMark",
            negativeAssetName: "RatingRottenTomatoesRottenMark",
            negativeBelow: 60
        ),
        descriptor(
            .metacritic,
            "Metacritic",
            order: 3,
            assetName: "RatingMetacriticMark"
        ),
        descriptor(.trakt, "Trakt", order: 4, assetName: "RatingTraktMark"),
        descriptor(
            .letterboxd,
            "Letterboxd",
            order: 5,
            assetName: "RatingLetterboxdMark"
        ),
        descriptor(
            .rottenTomatoesAudience,
            "Rotten Tomatoes Audience",
            order: 6,
            format: .percentage,
            assetName: "RatingRottenTomatoesAudienceHotMark",
            negativeAssetName: "RatingRottenTomatoesAudienceStaleMark",
            negativeBelow: 60
        ),
        descriptor(
            .myAnimeList,
            "MyAnimeList",
            order: 7,
            assetName: "RatingMyAnimeListMark"
        ),
        descriptor(
            .rogerEbert,
            "Roger Ebert",
            order: 8,
            assetName: "RatingRogerEbertMark"
        ),
    ]

    static let aggregateAssetName = "RatingMDBListMark"

    static func descriptor(for id: MDBListRatingProviderID) -> MDBListRatingProviderDescriptor {
        knownByID[id] ?? MDBListRatingProviderDescriptor(
            id: id,
            displayName: fallbackDisplayName(for: id),
            order: nil,
            valueFormat: .number,
            defaultAssetName: nil,
            negativeAssetName: nil,
            negativeBelow: nil
        )
    }

    static func settingsDescriptors(discovered: Set<String>) -> [MDBListRatingProviderDescriptor] {
        let knownIDs = Set(knownDescriptors.map(\.id))
        var unknownIDs: Set<MDBListRatingProviderID> = []
        for source in discovered {
            guard let id = MDBListRatingProviderID(source), !knownIDs.contains(id) else { continue }
            unknownIDs.insert(id)
        }
        let unknownDescriptors = unknownIDs.sorted().map { id in
            descriptor(for: id)
        }
        return knownDescriptors + unknownDescriptors
    }

    static func sortedDescriptors(
        for ids: Set<MDBListRatingProviderID>
    ) -> [MDBListRatingProviderDescriptor] {
        ids.map { descriptor(for: $0) }.sorted { lhs, rhs in
            switch (lhs.order, rhs.order) {
            case let (left?, right?):
                left < right
            case (_?, nil):
                true
            case (nil, _?):
                false
            case (nil, nil):
                lhs.id < rhs.id
            }
        }
    }

    static func formattedValue(
        _ value: Double,
        for id: MDBListRatingProviderID
    ) -> String? {
        guard let number = formattedNumber(value) else { return nil }
        switch descriptor(for: id).valueFormat {
        case .number:
            return number
        case .percentage:
            return "\(number)%"
        }
    }

    static func formattedAggregate(_ value: Double) -> String? {
        formattedNumber(value)
    }

    static func assetName(
        for id: MDBListRatingProviderID,
        value: Double
    ) -> String? {
        guard validatedValue(value) != nil else { return nil }
        let descriptor = descriptor(for: id)
        if let threshold = descriptor.negativeBelow,
           value < threshold,
           let negativeAssetName = descriptor.negativeAssetName {
            return negativeAssetName
        }
        return descriptor.defaultAssetName
    }

    static func validatedValue(_ value: Double) -> Double? {
        guard value.isFinite, (0...100).contains(value) else { return nil }
        return value
    }

    private static let knownByID = Dictionary(
        uniqueKeysWithValues: knownDescriptors.map { ($0.id, $0) }
    )

    private static func descriptor(
        _ id: MDBListRatingProviderID,
        _ displayName: String,
        order: Int,
        format: MDBListRatingValueFormat = .number,
        assetName: String? = nil,
        negativeAssetName: String? = nil,
        negativeBelow: Double? = nil
    ) -> MDBListRatingProviderDescriptor {
        MDBListRatingProviderDescriptor(
            id: id,
            displayName: displayName,
            order: order,
            valueFormat: format,
            defaultAssetName: assetName,
            negativeAssetName: negativeAssetName,
            negativeBelow: negativeBelow
        )
    }

    private static func fallbackDisplayName(for id: MDBListRatingProviderID) -> String {
        id.rawValue
            .split(whereSeparator: { $0 == "_" || $0 == "-" || $0 == "." })
            .map { component in
                guard let first = component.first else { return "" }
                return first.uppercased() + component.dropFirst()
            }
            .joined(separator: " ")
    }

    private static func formattedNumber(_ value: Double) -> String? {
        guard validatedValue(value) != nil else { return nil }
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), rounded)
    }
}

nonisolated struct MDBListRatingProviderProvenanceRecord: Hashable, Sendable {
    let canonicalSourceID: String
    let displayName: String
    let officialURL: URL
    let aboutResourceID: String
    let approvedAssetName: String?
}

nonisolated enum MDBListRatingProviderProvenance {
    static let records: [MDBListRatingProviderProvenanceRecord] = [
        record("imdb", "IMDb", "https://developer.imdb.com", "rating-imdb"),
        record(
            "tmdb",
            "TMDB",
            "https://developer.themoviedb.org/docs/faq",
            "tmdb",
            assetName: "RatingTMDBMark"
        ),
        record(
            "tomatoes",
            "Rotten Tomatoes",
            "https://www.rottentomatoes.com/help_desk/licensing",
            "rating-rotten-tomatoes"
        ),
        record(
            "metacritic",
            "Metacritic",
            "https://business.tivo.com/misc/metacriticusageguidelines.pdf",
            "rating-metacritic"
        ),
        record("trakt", "Trakt", "https://media-og.trakt.tv/branding", "rating-trakt"),
        record(
            "letterboxd",
            "Letterboxd",
            "https://letterboxd.com/about/brand/",
            "rating-letterboxd"
        ),
        record(
            "popcorn",
            "Rotten Tomatoes Audience",
            "https://www.rottentomatoes.com/help_desk/licensing",
            "rating-rotten-tomatoes"
        ),
        record("myanimelist", "MyAnimeList", "https://myanimelist.net", "rating-myanimelist"),
        record(
            "rogerebert",
            "Roger Ebert",
            "https://www.rogerebert.com/terms-of-use",
            "rating-roger-ebert"
        ),
        record("mdblist", "MDBList", "https://docs.mdblist.com/docs/api", "mdblist")
    ]

    private static func record(
        _ canonicalSourceID: String,
        _ displayName: String,
        _ officialURL: String,
        _ aboutResourceID: String,
        assetName: String? = nil
    ) -> MDBListRatingProviderProvenanceRecord {
        guard let url = URL(string: officialURL), url.scheme == "https" else {
            preconditionFailure("Invalid provider provenance URL")
        }
        return MDBListRatingProviderProvenanceRecord(
            canonicalSourceID: canonicalSourceID,
            displayName: displayName,
            officialURL: url,
            aboutResourceID: aboutResourceID,
            approvedAssetName: assetName
        )
    }
}
