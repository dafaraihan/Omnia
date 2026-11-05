import Foundation

struct SubtitleCue: Codable, Equatable, Sendable {
    let startSeconds: Double
    let endSeconds: Double
    let text: String
}

enum SubtitleFormat: Equatable, Sendable {
    case srt
    case webVTT
}

enum SubtitleParserError: Error, Equatable {
    case inputTooLarge
    case unsupportedEncoding
    case malformedCue
    case tooManyCues
    case cueTooLong
    case styledOverrideUnsupported
    case cancelled
}

enum SubtitleParser {
    static let maximumByteCount = 2 * 1_024 * 1_024
    static let maximumCueCount = 10_000
    static let maximumCueCharacters = 2_000

    static func parse(_ data: Data, format: SubtitleFormat) throws -> [SubtitleCue] {
        guard data.count <= maximumByteCount else { throw SubtitleParserError.inputTooLarge }
        guard !Task.isCancelled else { throw SubtitleParserError.cancelled }
        guard var text = String(data: data, encoding: .utf8) else {
            throw SubtitleParserError.unsupportedEncoding
        }
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if text.range(of: #"\{\\[^}]+\}"#, options: .regularExpression) != nil {
            throw SubtitleParserError.styledOverrideUnsupported
        }
        if format == .webVTT {
            guard text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("WEBVTT") else {
                throw SubtitleParserError.malformedCue
            }
        }

        let blocks = text.components(separatedBy: "\n\n")
        var cues: [SubtitleCue] = []
        for block in blocks {
            guard !Task.isCancelled else { throw SubtitleParserError.cancelled }
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let timing = lines[timingIndex].components(separatedBy: "-->")
            guard timing.count == 2,
                  let start = seconds(timing[0]),
                  let end = seconds(timing[1].split(separator: " ").first.map(String.init) ?? timing[1]),
                  start.isFinite, end.isFinite, start >= 0, start < end, end <= 12 * 60 * 60
            else { throw SubtitleParserError.malformedCue }
            let cueText = lines.dropFirst(timingIndex + 1).joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cueText.isEmpty else { throw SubtitleParserError.malformedCue }
            guard cueText.count <= maximumCueCharacters else { throw SubtitleParserError.cueTooLong }
            cues.append(SubtitleCue(startSeconds: start, endSeconds: end, text: cueText))
            guard cues.count <= maximumCueCount else { throw SubtitleParserError.tooManyCues }
        }
        guard !cues.isEmpty else { throw SubtitleParserError.malformedCue }
        return cues.sorted {
            $0.startSeconds == $1.startSeconds
                ? ($0.endSeconds == $1.endSeconds ? $0.text < $1.text : $0.endSeconds < $1.endSeconds)
                : $0.startSeconds < $1.startSeconds
        }
    }

    private static func seconds(_ raw: String) -> Double? {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        let parts = normalized.split(separator: ":").compactMap { Double($0) }
        guard (2 ... 3).contains(parts.count) else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 }
    }
}
