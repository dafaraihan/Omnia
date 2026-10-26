//
//  StreamRanking.swift
//  Omnia
//
//  Nuvio's stream sorting and filters (DebridStreamPresentation.kt and
//  DebridSettings.kt, NuvioMedia/NuvioMobile, GPL-3.0): what each source
//  is, read from its name, description and file name, then filtered and
//  ordered by the user's preferences (Dafa, 2026-10-27).
//

import Foundation
import os

/// Nuvio's sort profiles.
nonisolated enum StreamSortProfile: String, Codable, CaseIterable, Identifiable, Sendable {
    /// The order add-ons sent them in.
    case original
    /// Resolution, then release quality, HDR, audio, channels, codec, size.
    case bestQuality
    case largest
    case smallest
    /// Audio format and channels first, then picture.
    case audio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: "Add-on Order"
        case .bestQuality: "Best Quality"
        case .largest: "Largest First"
        case .smallest: "Smallest First"
        case .audio: "Best Audio"
        }
    }

    var summary: String {
        switch self {
        case .original: "Sources stay in the order each add-on lists them."
        case .bestQuality: "Highest resolution first, then the best release, HDR, audio and codec."
        case .largest: "Biggest files first, usually the highest bitrate."
        case .smallest: "Smallest files first, for slow connections."
        case .audio: "Atmos, DTS:X and more channels first, then picture."
        }
    }
}

nonisolated enum StreamFeatureFilter: String, Codable, CaseIterable, Identifiable, Sendable {
    case any, exclude, only
    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: "Any"
        case .exclude: "Hide"
        case .only: "Only"
        }
    }
}

nonisolated enum StreamCodecFilter: String, Codable, CaseIterable, Identifiable, Sendable {
    case any, h264, hevc, av1
    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: "Any"
        case .h264: "H.264 Only"
        case .hevc: "HEVC Only"
        case .av1: "AV1 Only"
        }
    }
}

/// Settings › Integrations › Stream Sorting, after Nuvio's Debrid › Stream
/// sorting and filters. Every field falls back to its default on decode.
nonisolated struct StreamSortPreferences: Codable, Equatable, Sendable {
    var profile: StreamSortProfile = .bestQuality
    /// Sources a debrid service already has ready (⚡, [RD+]) before ones it
    /// would still have to download.
    var cachedFirst = true
    /// 0 shows every resolution.
    var minimumResolution = 0
    var hdr: StreamFeatureFilter = .any
    var dolbyVision: StreamFeatureFilter = .any
    var codec: StreamCodecFilter = .any

    static let minimumResolutionOptions = [0, 720, 1080, 2160]

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        profile = (try? container.decodeIfPresent(StreamSortProfile.self, forKey: .profile)) ?? defaults.profile
        cachedFirst = (try? container.decodeIfPresent(Bool.self, forKey: .cachedFirst)) ?? defaults.cachedFirst
        minimumResolution = (try? container.decodeIfPresent(Int.self, forKey: .minimumResolution)) ?? defaults.minimumResolution
        hdr = (try? container.decodeIfPresent(StreamFeatureFilter.self, forKey: .hdr)) ?? defaults.hdr
        dolbyVision = (try? container.decodeIfPresent(StreamFeatureFilter.self, forKey: .dolbyVision)) ?? defaults.dolbyVision
        codec = (try? container.decodeIfPresent(StreamCodecFilter.self, forKey: .codec)) ?? defaults.codec
    }

    var filtersAnything: Bool {
        minimumResolution > 0 || hdr != .any || dolbyVision != .any || codec != .any
    }
}

/// What a source is, as far as its add-on says.
nonisolated struct StreamFacts: Equatable, Sendable {
    enum Quality: Int, Comparable, Sendable {
        // Best first, as Nuvio orders them.
        case remux, bluray, webDL, webRip, hdRip, dvdRip, hdtv, unknown, screener, telesync, cam

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    enum Codec: Int, Sendable {
        case av1, hevc, avc, other, unknown
    }

    enum CacheState: Int, Sendable {
        case cached, unknown, uncached

        /// A plain direct link plays as soon as a ready debrid one, so only
        /// links still to be downloaded sort after the rest.
        var readiness: Int { self == .uncached ? 1 : 0 }
    }

    /// 2160, 1080…; 0 when the source doesn't say.
    let resolution: Int
    let quality: Quality
    let hasDolbyVision: Bool
    let hasHDR: Bool
    /// Lower is better: Atmos, DTS:X, TrueHD, DTS-HD MA, DD+, DTS, DD, AAC.
    let audioRank: Int
    /// 8 for 7.1, 6 for 5.1, 2 for stereo, 0 when unknown.
    let channels: Int
    let codec: Codec
    let size: Int64?
    let cacheState: CacheState

    /// HDR and Dolby Vision together rank above either alone.
    var visualRank: Int {
        switch (hasDolbyVision, hasHDR) {
        case (true, true): 0
        case (true, false): 1
        case (false, true): 2
        case (false, false): 3
        }
    }

    init(candidate: AddonStreamCandidate) {
        let text = [candidate.displayName, candidate.displayDescription, candidate.filename]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        let range = NSRange(text.startIndex..., in: text)
        func has(_ pattern: String) -> Bool {
            Self.tokenExpression(pattern).firstMatch(in: text, range: range) != nil
        }

        if has("2160p?|4k|uhd") { resolution = 2160 }
        else if has("1440p?|2k") { resolution = 1440 }
        else if has("1080p?|fhd") { resolution = 1080 }
        else if has("720p?") { resolution = 720 }
        else if has("576p?") { resolution = 576 }
        else if has("480p?|sd") { resolution = 480 }
        else if has("360p?") { resolution = 360 }
        else { resolution = 0 }

        if text.contains("remux") { quality = .remux }
        else if has("blu-?ray|bdrip|brrip|bdremux") { quality = .bluray }
        else if has("web-?dl") { quality = .webDL }
        else if has("web-?rip|web") { quality = .webRip }
        else if has("hd-?rip|hc") { quality = .hdRip }
        else if has("dvd-?rip|dvd") { quality = .dvdRip }
        else if has("hdtv") { quality = .hdtv }
        else if has("hd-?cam|cam|camrip") { quality = .cam }
        else if has("ts|telesync|hdts|tc|telecine") { quality = .telesync }
        else if has("scr|screener|dvdscr") { quality = .screener }
        else { quality = .unknown }

        hasDolbyVision = has("dv|dovi|dolby[ ._-]?vision")
        hasHDR = has("hdr|hdr10|hdr10\\+|hdr10plus|hlg")

        if has("atmos") { audioRank = 0 }
        else if has("dts[: -]?x") { audioRank = 1 }
        else if has("truehd|true[ ._-]hd") { audioRank = 2 }
        else if has("dts[ ._-]?hd[ ._-]?ma|dts[ ._-]?hd") { audioRank = 3 }
        // Release names glue channels on: DDP5.1, DD2.0, AAC2.0.
        else if has("dd\\+[0-9.]*|ddp[0-9.]*|eac3|e-ac-3|dolby digital plus") { audioRank = 4 }
        else if has("dts[0-9.]*") { audioRank = 5 }
        else if has("dd[0-9.]*|ac3|dolby digital") { audioRank = 6 }
        else if has("flac|opus") { audioRank = 7 }
        else if has("aac[0-9.]*") { audioRank = 8 }
        else { audioRank = 9 }

        // Channels often follow the codec with no space (DDP5.1), so these
        // only need no digit right before or after.
        func hasChannels(_ value: String) -> Bool {
            text.range(of: #"(?<![0-9.])"# + value + #"(?![0-9])"#, options: .regularExpression) != nil
        }
        if hasChannels("7\\.1") || has("8ch") { channels = 8 }
        else if hasChannels("6\\.1") || has("7ch") { channels = 7 }
        else if hasChannels("5\\.1") || has("6ch") { channels = 6 }
        else if hasChannels("2\\.0") || has("stereo") { channels = 2 }
        else { channels = 0 }

        if has("av1") { codec = .av1 }
        else if has("hevc|h\\.?265|x265") { codec = .hevc }
        else if has("avc|h\\.?264|x264") { codec = .avc }
        else if has("xvid|divx|mpeg2|vc-?1") { codec = .other }
        else { codec = .unknown }

        size = candidate.videoSize ?? Self.sizeInText(text)

        // AIOStreams, Comet, MediaFusion and StremThru mark ready debrid
        // links with ⚡ and pending ones with ⏳; Torrentio writes [RD+]
        // for ready and [RD download] for pending.
        if text.contains("⏳") || text.range(of: #"\[(rd|ad|pm|tb|dl|ed|oc|pp)\s*download\]"#, options: .regularExpression) != nil {
            cacheState = .uncached
        } else if text.contains("⚡") || text.range(of: #"\[(rd|ad|pm|tb|dl|ed|oc|pp)\+\]"#, options: .regularExpression) != nil
                    || has("cached|instant") {
            cacheState = .cached
        } else {
            cacheState = .unknown
        }
    }

    /// Compiled once per pattern: ranking runs on every partial source
    /// update, for every source.
    private static let expressions = OSAllocatedUnfairLock(initialState: [String: NSRegularExpression]())

    /// `pattern` as a whole word or token.
    private static func tokenExpression(_ pattern: String) -> NSRegularExpression {
        expressions.withLock { cache in
            if let cached = cache[pattern] { return cached }
            // The patterns are constants in this file, so they always compile.
            let expression = try! NSRegularExpression(pattern: #"(^|[^a-z0-9])(?:"# + pattern + #")([^a-z0-9]|$)"#)
            cache[pattern] = expression
            return expression
        }
    }

    /// "12.3 GB" or "850 MB" in the source's description.
    private static func sizeInText(_ text: String) -> Int64? {
        guard let match = text.range(of: #"(\d+(?:[.,]\d+)?)\s?(tb|gb|gib|mb|mib)\b"#, options: .regularExpression) else {
            return nil
        }
        let found = String(text[match])
        let number = Double(found.prefix { $0.isNumber || $0 == "." || $0 == "," }.replacingOccurrences(of: ",", with: ".")) ?? 0
        let unit: Double = found.contains("t") ? 1e12 : found.contains("g") ? 1e9 : 1e6
        return number > 0 ? Int64(number * unit) : nil
    }
}

nonisolated enum StreamRanking {
    /// Drops sources the filters exclude, then orders the rest, best first.
    /// Ties keep add-on order, so equal sources stay where add-ons put them.
    static func rank(_ candidates: [AddonStreamCandidate], preferences: StreamSortPreferences) -> [AddonStreamCandidate] {
        guard preferences.profile != .original || preferences.cachedFirst || preferences.filtersAnything else {
            return candidates
        }
        let facts = candidates.enumerated().map { (index: $0.offset, candidate: $0.element, facts: StreamFacts(candidate: $0.element)) }
        let kept = facts.filter { matches($0.facts, preferences) }
        return kept.sorted { left, right in
            switch compare(left.facts, right.facts, preferences) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: left.index < right.index
            }
        }
        .map(\.candidate)
    }

    static func matches(_ facts: StreamFacts, _ preferences: StreamSortPreferences) -> Bool {
        // A source that doesn't say its resolution isn't hidden by a minimum.
        if preferences.minimumResolution > 0, facts.resolution > 0, facts.resolution < preferences.minimumResolution {
            return false
        }
        switch preferences.hdr {
        case .any: break
        case .exclude: if facts.hasHDR { return false }
        case .only: if !facts.hasHDR { return false }
        }
        switch preferences.dolbyVision {
        case .any: break
        case .exclude: if facts.hasDolbyVision { return false }
        case .only: if !facts.hasDolbyVision { return false }
        }
        switch preferences.codec {
        case .any: break
        case .h264: if facts.codec != .avc { return false }
        case .hevc: if facts.codec != .hevc { return false }
        case .av1: if facts.codec != .av1 { return false }
        }
        return true
    }

    /// `.orderedAscending` when `left` should play first.
    static func compare(_ left: StreamFacts, _ right: StreamFacts, _ preferences: StreamSortPreferences) -> ComparisonResult {
        var keys: [(Int, Int)] = []
        if preferences.cachedFirst {
            keys.append((left.cacheState.readiness, right.cacheState.readiness))
        }
        let leftSize = Int(clamping: left.size ?? 0), rightSize = Int(clamping: right.size ?? 0)
        // Each pair is (left, right) where the smaller value plays first.
        let picture: [(Int, Int)] = [
            (-left.resolution, -right.resolution),
            (left.quality.rawValue, right.quality.rawValue),
            (left.visualRank, right.visualRank)
        ]
        let sound: [(Int, Int)] = [
            (left.audioRank, right.audioRank),
            (-left.channels, -right.channels)
        ]
        let codec = (left.codec.rawValue, right.codec.rawValue)
        switch preferences.profile {
        case .original:
            break
        case .bestQuality:
            keys += picture + sound + [codec, (-leftSize, -rightSize)]
        case .largest:
            keys.append((-leftSize, -rightSize))
        case .smallest:
            // A source with no size goes last rather than first.
            keys.append((left.size == nil ? Int.max : leftSize, right.size == nil ? Int.max : rightSize))
        case .audio:
            keys += sound + picture + [(-leftSize, -rightSize)]
        }
        for (lhs, rhs) in keys where lhs != rhs {
            return lhs < rhs ? .orderedAscending : .orderedDescending
        }
        return .orderedSame
    }
}
