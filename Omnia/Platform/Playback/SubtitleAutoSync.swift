import Foundation

/// How loud the audio was at one moment of the video.
nonisolated struct SubtitleSyncSample: Equatable, Sendable {
    let time: Double
    let decibels: Double
}

/// Finds the subtitle delay at which a file's lines are on screen while
/// people are talking. Speech makes the audio louder than the quiet between
/// lines, so the right delay is the one where "a line is showing" rises and
/// falls together with the loudness. This only needs the subtitle file's
/// timing and a stretch of audio already played, so it works with any
/// add-on subtitle and any stream.
nonisolated enum SubtitleAutoSync {
    struct Match: Equatable, Sendable {
        /// mpv's sub-delay in seconds; positive shows subtitles later.
        let delay: Double
        /// How far the best delay stands out from the next best one.
        let confidence: Double
    }

    static let searchRange: ClosedRange<Double> = -15 ... 15
    static let step = 0.1
    /// Ten samples a second; 30 seconds of listening is the least that
    /// gives a usable answer.
    static let minimumSampleCount = 300

    private static let minimumCorrelation = 0.07
    private static let minimumMargin = 0.015
    private static let distinctDelay = 1.0

    static func bestDelay(cues: [SubtitleCue], samples: [SubtitleSyncSample]) -> Match? {
        let samples = samples.filter { $0.time.isFinite && $0.decibels.isFinite }
        guard samples.count >= minimumSampleCount else { return nil }
        let intervals = merged(cues)
        guard intervals.count >= 8 else { return nil }

        // Rank loudness instead of using raw decibels, so one explosion
        // weighs no more than any other loud moment.
        let order = samples.indices.sorted { samples[$0].decibels < samples[$1].decibels }
        var loudness = [Double](repeating: 0, count: samples.count)
        for (rank, index) in order.enumerated() {
            loudness[index] = Double(rank) / Double(samples.count - 1) - 0.5
        }
        let loudnessEnergy = loudness.reduce(0) { $0 + $1 * $1 }
        guard loudnessEnergy > 0 else { return nil }

        var scores: [(delay: Double, score: Double)] = []
        let steps = Int(((searchRange.upperBound - searchRange.lowerBound) / step).rounded())
        var covered = [Double](repeating: 0, count: samples.count)
        for index in 0 ... steps {
            let delay = searchRange.lowerBound + Double(index) * step
            var coveredCount = 0.0
            for (sampleIndex, sample) in samples.enumerated() {
                let isCovered = contains(intervals, sample.time - delay)
                covered[sampleIndex] = isCovered ? 1 : 0
                if isCovered { coveredCount += 1 }
            }
            let fraction = coveredCount / Double(samples.count)
            // Lines on screen all the time, or never, say nothing about timing.
            guard fraction > 0.08, fraction < 0.92 else { continue }
            var product = 0.0
            for sampleIndex in samples.indices {
                product += loudness[sampleIndex] * (covered[sampleIndex] - fraction)
            }
            let coverageEnergy = coveredCount * (1 - fraction)
            scores.append((delay, product / (loudnessEnergy * coverageEnergy).squareRoot()))
        }

        guard let best = scores.max(by: { $0.score < $1.score }),
              best.score >= minimumCorrelation
        else { return nil }
        let runnerUp = scores
            .filter { abs($0.delay - best.delay) > distinctDelay }
            .map(\.score)
            .max() ?? 0
        let margin = best.score - runnerUp
        guard margin >= minimumMargin else { return nil }
        return Match(delay: (best.delay * 10).rounded() / 10, confidence: margin)
    }

    /// Each line's timing and text, from SRT, WebVTT or ASS/SSA. Lines the
    /// app's subtitle parser would refuse (styling tags, odd blocks) still
    /// count here, because only when they show matters.
    static func cues(fromSubtitleData data: Data) -> [SubtitleCue] {
        guard data.count <= 4 * 1_024 * 1_024 else { return [] }
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? String(decoding: data, as: UTF8.self)
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var cues: [SubtitleCue] = []
        var assFields = ["layer", "start", "end", "style", "name", "marginl", "marginr", "marginv", "effect", "text"]
        var index = 0
        while index < lines.count, cues.count < 20_000 {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            index += 1
            if line.hasPrefix("Format:") {
                let fields = line.dropFirst("Format:".count).split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                if fields.contains("start"), fields.contains("end") { assFields = fields }
            } else if line.hasPrefix("Dialogue:") {
                guard let startIndex = assFields.firstIndex(of: "start"),
                      let endIndex = assFields.firstIndex(of: "end")
                else { continue }
                let fields = line.dropFirst("Dialogue:".count)
                    .split(separator: ",", maxSplits: assFields.count - 1, omittingEmptySubsequences: false)
                    .map(String.init)
                guard fields.count == assFields.count,
                      let start = seconds(fields[startIndex]),
                      let end = seconds(fields[endIndex]),
                      end > start
                else { continue }
                let body = fields[assFields.firstIndex(of: "text") ?? assFields.count - 1]
                    .replacingOccurrences(of: #"\{[^}]*\}"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: "\\N", with: "\n")
                    .replacingOccurrences(of: "\\n", with: "\n")
                cues.append(SubtitleCue(startSeconds: start, endSeconds: end, text: plain(body)))
            } else if line.contains("-->") {
                let parts = line.components(separatedBy: "-->")
                guard parts.count == 2,
                      let start = seconds(parts[0]),
                      let end = seconds(parts[1].split(separator: " ").first.map(String.init) ?? ""),
                      end > start
                else { continue }
                var body: [String] = []
                while index < lines.count {
                    let textLine = lines[index].trimmingCharacters(in: .whitespaces)
                    if textLine.isEmpty || textLine.contains("-->") { break }
                    body.append(textLine)
                    index += 1
                }
                cues.append(SubtitleCue(startSeconds: start, endSeconds: end, text: plain(body.joined(separator: "\n"))))
            }
        }
        return cues.sorted { $0.startSeconds < $1.startSeconds }
    }

    /// Text without HTML-style or ASS styling tags.
    private static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\{[^}]*\}"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "01:02:03,450", "02:03.450" or ASS's "1:02:03.45".
    private static func seconds(_ raw: String) -> Double? {
        let parts = raw.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
            .split(separator: ":")
            .map { Double($0) }
        guard (2 ... 3).contains(parts.count), !parts.contains(nil) else { return nil }
        let value = parts.compactMap { $0 }.reduce(0) { $0 * 60 + $1 }
        return value.isFinite && value >= 0 && value < 24 * 3_600 ? value : nil
    }

    /// Cue times as sorted, non-overlapping ranges.
    static func merged(_ cues: [SubtitleCue]) -> [ClosedRange<Double>] {
        let sorted = cues
            .filter { $0.startSeconds.isFinite && $0.endSeconds > $0.startSeconds }
            .sorted { $0.startSeconds < $1.startSeconds }
        var result: [ClosedRange<Double>] = []
        for cue in sorted {
            if let last = result.last, cue.startSeconds <= last.upperBound {
                result[result.count - 1] = last.lowerBound ... max(last.upperBound, cue.endSeconds)
            } else {
                result.append(cue.startSeconds ... cue.endSeconds)
            }
        }
        return result
    }

    private static func contains(_ intervals: [ClosedRange<Double>], _ time: Double) -> Bool {
        var low = 0
        var high = intervals.count - 1
        while low <= high {
            let middle = (low + high) / 2
            let interval = intervals[middle]
            if time < interval.lowerBound {
                high = middle - 1
            } else if time > interval.upperBound {
                low = middle + 1
            } else {
                return true
            }
        }
        return false
    }
}

/// Subtitle delays chosen during playback, kept per title so coming back to
/// an episode keeps it in sync. Settings' delay stays the default for
/// everything else.
@MainActor
enum SubtitleDelayMemory {
    private static let key = "subtitle-delay-by-title"
    private static let orderKey = "subtitle-delay-by-title-order"
    private static let limit = 300

    static func delay(for id: String) -> Double? {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: Double])?[id]
    }

    static func remember(_ delay: Double?, for id: String) {
        let defaults = UserDefaults.standard
        var stored = (defaults.dictionary(forKey: key) as? [String: Double]) ?? [:]
        var order = (defaults.stringArray(forKey: orderKey) ?? []).filter { $0 != id }
        stored[id] = delay
        if delay != nil { order.append(id) }
        // Oldest titles go first once the list is full.
        while order.count > limit {
            stored[order.removeFirst()] = nil
        }
        defaults.set(stored, forKey: key)
        defaults.set(order, forKey: orderKey)
    }
}
