//
//  LiveTVProviders.swift
//  Omnia
//

import Compression
import CryptoKit
import Foundation
import Network
import Synchronization

// MARK: Fetching

/// Downloads for Live TV. Playlists and guides run to tens of megabytes, past
/// the add-on transport's limit, so this reads up to 64 MB and stops as soon
/// as a reply runs over. https:// and local http:// go through URLSession;
/// plain http:// to the internet, which App Transport Security refuses, goes
/// through `LiveTVPlainHTTP`. Redirects may move between the two, at most five.
nonisolated enum LiveTVHTTP {
    static let maximumRedirects = 5

    static let maximumBytes = 64 * 1_024 * 1_024
    static let apiHeaders = ["Accept": "application/json, text/plain, */*", "User-Agent": "Omnia/1.0"]

    @concurrent
    static func data(
        from url: URL,
        headers: [String: String] = apiHeaders,
        maximumBytes: Int = maximumBytes,
        timeout: TimeInterval = 45
    ) async throws -> Data {
        var target = url
        for _ in 0...maximumRedirects {
            guard LiveTVAddressPolicy.permits(target) else { throw LiveTVFailure.insecureAddress }
            if LiveTVAddressPolicy.needsPlainHTTP(target) {
                switch try await LiveTVPlainHTTP.get(
                    target,
                    headers: headers,
                    maximumBytes: maximumBytes,
                    timeout: timeout
                ) {
                case let .body(data):
                    return data
                case let .redirect(next):
                    target = next
                }
            } else {
                do {
                    return try await sessionData(from: target, headers: headers, maximumBytes: maximumBytes, timeout: timeout)
                } catch let redirect as LiveTVPlainRedirect {
                    target = redirect.url
                }
            }
        }
        throw LiveTVFailure.invalidResponse
    }

    private static func sessionData(
        from url: URL,
        headers: [String: String],
        maximumBytes: Int,
        timeout: TimeInterval
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let download = LiveTVDownload(limit: maximumBytes)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration, delegate: download, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.dataTask(with: request)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                download.start(task, continuation: continuation)
            }
        } onCancel: {
            task.cancel()
        }
    }

    @concurrent
    static func json(from url: URL, headers: [String: String] = apiHeaders) async throws -> Any {
        let data = try await data(from: url, headers: headers, maximumBytes: 32 * 1_024 * 1_024)
        guard let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            throw LiveTVFailure.invalidResponse
        }
        return value
    }

    static func text(from data: Data) -> String {
        String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }
}

private nonisolated final class LiveTVDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let limit: Int
    private let lock = NSLock()
    private var buffer = Data()
    private var failure: LiveTVFailure?
    /// A redirect to plain http:// on the internet, handed back to `LiveTVHTTP`.
    private var plainRedirect: URL?
    private var checkedResponse = false
    private var continuation: CheckedContinuation<Data, Error>?

    init(limit: Int) {
        self.limit = limit
    }

    func start(_ task: URLSessionDataTask, continuation: CheckedContinuation<Data, Error>) {
        lock.withLock { self.continuation = continuation }
        task.resume()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let shouldCancel = lock.withLock { () -> Bool in
            guard failure == nil else { return true }
            // The reply's status and size are checked with its first bytes.
            if !checkedResponse {
                checkedResponse = true
                if let problem = Self.problem(with: dataTask.response, limit: limit) {
                    failure = problem
                    return true
                }
            }
            buffer.append(data)
            if buffer.count > limit {
                failure = .tooLarge
                return true
            }
            return false
        }
        if shouldCancel { dataTask.cancel() }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, LiveTVAddressPolicy.permits(url) else {
            lock.withLock { failure = .insecureAddress }
            completionHandler(nil)
            task.cancel()
            return
        }
        if LiveTVAddressPolicy.needsPlainHTTP(url) {
            lock.withLock { plainRedirect = url }
            completionHandler(nil)
            task.cancel()
            return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let (continuation, data, failure, redirect) = lock.withLock {
            let pending = self.continuation
            self.continuation = nil
            return (pending, buffer, self.failure, plainRedirect)
        }
        guard let continuation else { return }
        if let redirect {
            continuation.resume(throwing: LiveTVPlainRedirect(url: redirect))
        } else if let failure {
            continuation.resume(throwing: failure)
        } else if let error {
            let code = (error as? URLError)?.code
            continuation.resume(throwing: code == .cancelled ? CancellationError() : LiveTVFailure.unreachable)
        } else if let problem = Self.problem(with: task.response, limit: limit) {
            continuation.resume(throwing: problem)
        } else {
            continuation.resume(returning: data)
        }
    }

    private static func problem(with response: URLResponse?, limit: Int) -> LiveTVFailure? {
        guard let http = response as? HTTPURLResponse else { return .invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            return [401, 403].contains(http.statusCode) ? .signInRejected : .status(http.statusCode)
        }
        return http.expectedContentLength > Int64(limit) ? .tooLarge : nil
    }
}

private nonisolated struct LiveTVPlainRedirect: Error {
    let url: URL
}

/// A small HTTP/1.1 GET over Network.framework for Live TV's plain http://
/// providers. App Transport Security covers URLSession, not raw connections,
/// so this is the narrow way past it: Live TV only, GET only, no cookies or
/// cache, the same byte limit and timeout, and redirects returned to
/// `LiveTVHTTP` so each hop is checked again.
nonisolated enum LiveTVPlainHTTP {
    enum Outcome: Sendable {
        case body(Data)
        case redirect(URL)
    }

    static let maximumHeaderBytes = 64 * 1_024

    @concurrent
    static func get(
        _ url: URL,
        headers: [String: String],
        maximumBytes: Int,
        timeout: TimeInterval
    ) async throws -> Outcome {
        guard let host = url.host, !host.isEmpty,
              let port = NWEndpoint.Port(rawValue: UInt16(clamping: url.port ?? 80)) else {
            throw LiveTVFailure.invalidAddress
        }
        let connection = LiveTVConnection(NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp))
        let timer = Task {
            try? await Task.sleep(for: .seconds(timeout))
            if !Task.isCancelled { connection.cancel() }
        }
        defer {
            timer.cancel()
            connection.cancel()
        }
        return try await withTaskCancellationHandler {
            try await connection.ready()
            try await connection.send(request(for: url, host: host, headers: headers))
            return try await read(from: connection, url: url, maximumBytes: maximumBytes)
        } onCancel: {
            connection.cancel()
        }
    }

    static func request(for url: URL, host: String, headers: [String: String]) -> Data {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var target = components?.percentEncodedPath ?? "/"
        if target.isEmpty { target = "/" }
        if let query = components?.percentEncodedQuery, !query.isEmpty { target += "?" + query }
        let hostHeader = url.port.map { "\(host):\($0)" } ?? host
        var lines = [
            "GET \(target) HTTP/1.1",
            "Host: \(hostHeader)",
            "Connection: close",
            "Accept-Encoding: identity",
        ]
        let reserved: Set<String> = ["host", "connection", "accept-encoding", "content-length", "transfer-encoding"]
        for (name, value) in headers.sorted(by: { $0.key < $1.key }) {
            // Header injection: no line breaks in names or values.
            guard !reserved.contains(name.lowercased()),
                  !name.contains(where: \.isNewline), !value.contains(where: \.isNewline),
                  !name.contains(":") else { continue }
            lines.append("\(name): \(value)")
        }
        return Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
    }

    private static func read(from connection: LiveTVConnection, url: URL, maximumBytes: Int) async throws -> Outcome {
        var buffer = Data()
        var head: Head?
        let separator = Data("\r\n\r\n".utf8)
        while true {
            let (chunk, isComplete) = try await connection.receive()
            buffer.append(chunk)
            if head == nil {
                if let range = buffer.range(of: separator) {
                    let parsed = try Head(Data(buffer[buffer.startIndex..<range.lowerBound]))
                    head = parsed
                    buffer = Data(buffer[range.upperBound...])
                    if let outcome = try check(parsed, url: url, maximumBytes: maximumBytes) { return outcome }
                } else if buffer.count > maximumHeaderBytes {
                    throw LiveTVFailure.invalidResponse
                }
            }
            if let head {
                if head.isChunked {
                    // Decoded once the last chunk is in, not on every read.
                    if buffer.suffix(5) == Data("0\r\n\r\n".utf8),
                       let body = try dechunked(buffer, limit: maximumBytes) {
                        return .body(try decoded(body, head))
                    }
                } else if let length = head.contentLength, buffer.count >= length {
                    return .body(try decoded(Data(buffer.prefix(length)), head))
                }
                if buffer.count > maximumBytes + (head.isChunked ? maximumBytes / 8 + 4_096 : 0) {
                    throw LiveTVFailure.tooLarge
                }
            }
            if isComplete {
                guard let head else { throw LiveTVFailure.invalidResponse }
                if head.isChunked {
                    guard let body = try dechunked(buffer, limit: maximumBytes) else { throw LiveTVFailure.unreachable }
                    return .body(try decoded(body, head))
                }
                // Closed early: a sized reply must be whole.
                guard head.contentLength == nil else { throw LiveTVFailure.unreachable }
                return .body(try decoded(buffer, head))
            }
        }
    }

    /// Identity is asked for, but a server that gzips anyway is unpacked.
    private static func decoded(_ body: Data, _ head: Head) throws -> Data {
        guard head.fields["content-encoding"]?.lowercased() == "gzip" else { return body }
        return try LiveTVGzip.unpackedIfNeeded(body)
    }

    /// Status, size and redirects, checked once the headers are in.
    private static func check(_ head: Head, url: URL, maximumBytes: Int) throws -> Outcome? {
        if [301, 302, 303, 307, 308].contains(head.status) {
            guard let location = head.fields["location"],
                  let next = URL(string: location, relativeTo: url)?.absoluteURL else {
                throw LiveTVFailure.invalidResponse
            }
            return .redirect(next)
        }
        guard (200...299).contains(head.status) else {
            throw [401, 403].contains(head.status) ? LiveTVFailure.signInRejected : LiveTVFailure.status(head.status)
        }
        if let length = head.contentLength, length > maximumBytes { throw LiveTVFailure.tooLarge }
        if let encoding = head.fields["content-encoding"]?.lowercased(), !["", "identity", "gzip"].contains(encoding) {
            throw LiveTVFailure.invalidResponse
        }
        return nil
    }

    /// The body of a chunked reply, or nil while chunks are still arriving.
    static func dechunked(_ data: Data, limit: Int) throws -> Data? {
        let bytes = [UInt8](data)
        var body = Data()
        var index = 0
        while true {
            guard let lineEnd = lineEnd(in: bytes, from: index) else { return nil }
            let sizeText = String(decoding: bytes[index..<lineEnd], as: UTF8.self)
                .split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            guard let size = Int(sizeText, radix: 16), size >= 0 else { throw LiveTVFailure.invalidResponse }
            index = lineEnd + 2
            if size == 0 { return body }
            guard index + size + 2 <= bytes.count else { return nil }
            body.append(contentsOf: bytes[index..<(index + size)])
            if body.count > limit { throw LiveTVFailure.tooLarge }
            index += size + 2
        }
    }

    private static func lineEnd(in bytes: [UInt8], from start: Int) -> Int? {
        var index = start
        while index + 1 < bytes.count {
            if bytes[index] == 13, bytes[index + 1] == 10 { return index }
            index += 1
        }
        return nil
    }

    struct Head {
        let status: Int
        let fields: [String: String]

        init(_ data: Data) throws {
            let lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\r\n")
            let statusParts = lines.first?.split(separator: " ", maxSplits: 2) ?? []
            guard statusParts.count >= 2, statusParts[0].hasPrefix("HTTP/1."),
                  let status = Int(statusParts[1]) else { throw LiveTVFailure.invalidResponse }
            self.status = status
            var fields: [String: String] = [:]
            for line in lines.dropFirst() {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                fields[name] = value
            }
            self.fields = fields
        }

        var isChunked: Bool {
            fields["transfer-encoding"]?.lowercased().contains("chunked") == true
        }

        var contentLength: Int? {
            guard !isChunked else { return nil }
            return fields["content-length"].flatMap { Int($0) }
        }
    }
}

/// An NWConnection with async start, send and receive.
private nonisolated final class LiveTVConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "omnia.livetv.http")
    private let lock = NSLock()
    private var readyContinuation: CheckedContinuation<Void, Error>?

    init(_ connection: NWConnection) {
        self.connection = connection
    }

    func ready() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.withLock { readyContinuation = continuation }
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.finishReady(nil)
                case .failed, .cancelled:
                    self?.finishReady(LiveTVFailure.unreachable)
                case .waiting:
                    // No route or refused: fail now rather than wait for a network.
                    self?.finishReady(LiveTVFailure.unreachable)
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    private func finishReady(_ error: Error?) {
        let continuation = lock.withLock {
            let pending = readyContinuation
            readyContinuation = nil
            return pending
        }
        if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
    }

    func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if error != nil {
                    continuation.resume(throwing: LiveTVFailure.unreachable)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    func receive() async throws -> (Data, Bool) {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, Bool), Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1_024) { data, _, isComplete, error in
                if let data, !data.isEmpty {
                    continuation.resume(returning: (data, isComplete))
                } else if isComplete {
                    continuation.resume(returning: (Data(), true))
                } else if error != nil {
                    continuation.resume(throwing: LiveTVFailure.unreachable)
                } else {
                    continuation.resume(returning: (Data(), false))
                }
            }
        }
    }

    func cancel() {
        connection.cancel()
        finishReady(LiveTVFailure.unreachable)
    }
}

// MARK: Gzip

nonisolated enum LiveTVGzip {
    /// Guides are often served as .xml.gz. Unpacks at most `limit` bytes so a
    /// small download can't expand without bound.
    static func unpackedIfNeeded(_ data: Data, limit: Int = 160 * 1_024 * 1_024) throws -> Data {
        guard data.count > 18, data[data.startIndex] == 0x1f, data[data.startIndex + 1] == 0x8b else { return data }
        let bytes = [UInt8](data)
        guard bytes[2] == 8 else { throw LiveTVFailure.invalidResponse }
        let flags = bytes[3]
        var offset = 10
        if flags & 0x04 != 0 {
            guard offset + 2 <= bytes.count else { throw LiveTVFailure.invalidResponse }
            offset += 2 + Int(bytes[offset]) + Int(bytes[offset + 1]) << 8
        }
        for flag in [UInt8(0x08), 0x10] where flags & flag != 0 {
            while offset < bytes.count, bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x02 != 0 { offset += 2 }
        guard offset < bytes.count - 8 else { throw LiveTVFailure.invalidResponse }
        return try inflate(bytes[offset..<(bytes.count - 8)], limit: limit)
    }

    private static func inflate(_ input: ArraySlice<UInt8>, limit: Int) throws -> Data {
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw LiveTVFailure.invalidResponse
        }
        defer { compression_stream_destroy(stream) }
        let chunkSize = 256 * 1_024
        let chunk = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer { chunk.deallocate() }
        var output = Data()
        return try input.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { throw LiveTVFailure.invalidResponse }
            stream.pointee.src_ptr = base
            stream.pointee.src_size = source.count
            while true {
                stream.pointee.dst_ptr = chunk
                stream.pointee.dst_size = chunkSize
                let status = compression_stream_process(stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = chunkSize - stream.pointee.dst_size
                output.append(chunk, count: produced)
                guard output.count <= limit else { throw LiveTVFailure.tooLarge }
                if status == COMPRESSION_STATUS_END { return output }
                guard status == COMPRESSION_STATUS_OK else { throw LiveTVFailure.invalidResponse }
            }
        }
    }
}

// MARK: XMLTV

/// What one XMLTV guide holds for the window Omnia shows: channel names by
/// guide id and their programmes.
nonisolated struct LiveTVGuideDocument: Sendable {
    var displayNames: [String: [String]] = [:]
    var programs: [String: [LiveTVProgram]] = [:]
}

nonisolated enum LiveTVGuideParser {
    static func parse(_ data: Data, from start: Date, to end: Date) -> LiveTVGuideDocument {
        let delegate = XMLTVDelegate(windowStart: start, windowEnd: end)
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        parser.parse()
        var document = delegate.document
        for key in document.programs.keys {
            document.programs[key]?.sort { $0.start < $1.start }
        }
        return document
    }
}

private nonisolated final class XMLTVDelegate: NSObject, XMLParserDelegate {
    private struct OpenProgramme {
        let channel: String
        let start: Date
        let stop: Date?
    }

    let windowStart: Date
    let windowEnd: Date
    var document = LiveTVGuideDocument()

    private var channelID: String?
    private var programme: OpenProgramme?
    private var title: String?
    private var detail: String?
    private var category: String?
    private var text = ""
    private var collecting = false
    /// Programmes without a stop time end where the next one starts.
    private var openEnded: [String: Int] = [:]

    init(windowStart: Date, windowEnd: Date) {
        self.windowStart = windowStart
        self.windowEnd = windowEnd
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        switch elementName {
        case "channel":
            channelID = attributes["id"]
        case "display-name" where channelID != nil:
            startText()
        case "programme":
            guard let channel = attributes["channel"], let startText = attributes["start"],
                  let start = LiveTVGuideTime.date(from: startText) else { return }
            programme = OpenProgramme(channel: channel, start: start, stop: attributes["stop"].flatMap(LiveTVGuideTime.date(from:)))
            title = nil
            detail = nil
            category = nil
        case "title" where programme != nil && title == nil,
             "desc" where programme != nil && detail == nil,
             "category" where programme != nil && category == nil:
            startText()
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if collecting { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        switch elementName {
        case "channel":
            channelID = nil
        case "display-name" where collecting:
            if let channelID, let name = finishText() {
                document.displayNames[channelID, default: []].append(name)
            }
        case "title" where collecting:
            title = finishText()
        case "desc" where collecting:
            detail = finishText()
        case "category" where collecting:
            category = finishText()
        case "programme":
            if let programme, let title { add(programme, title: title) }
            programme = nil
        default:
            break
        }
    }

    private func add(_ entry: OpenProgramme, title: String) {
        // Close the channel's previous open-ended programme at this start.
        if let index = openEnded.removeValue(forKey: entry.channel),
           var list = document.programs[entry.channel], index < list.count {
            let previous = list[index]
            if entry.start > previous.start {
                list[index] = LiveTVProgram(
                    title: previous.title, start: previous.start, end: entry.start,
                    detail: previous.detail, category: previous.category
                )
                document.programs[entry.channel] = list
            }
        }
        let end = entry.stop ?? entry.start.addingTimeInterval(3_600)
        guard end >= windowStart, entry.start <= windowEnd else { return }
        document.programs[entry.channel, default: []].append(LiveTVProgram(
            title: title, start: entry.start, end: end, detail: detail, category: category
        ))
        if entry.stop == nil, let count = document.programs[entry.channel]?.count {
            openEnded[entry.channel] = count - 1
        }
    }

    private func startText() {
        text = ""
        collecting = true
    }

    private func finishText() -> String? {
        collecting = false
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = ""
        return value.isEmpty ? nil : value
    }
}

// MARK: Xtream

nonisolated enum LiveTVXtreamClient {
    static let sourceID = "provider:xtream"

    /// Checks the account with player_api.php, as Xtream apps do.
    static func verify(_ account: LiveTVXtreamAccount) async throws {
        let value = try await LiveTVHTTP.json(from: apiURL(account, action: nil))
        guard let object = value as? [String: Any], let user = object["user_info"] as? [String: Any] else {
            throw LiveTVFailure.invalidResponse
        }
        guard jsonString(user["auth"]) == "1" || (user["auth"] as? Bool) == true else {
            throw LiveTVFailure.signInRejected
        }
    }

    static func channels(_ account: LiveTVXtreamAccount) async throws -> [LiveTVChannel] {
        let categoriesURL = try apiURL(account, action: "get_live_categories")
        let streamsURL = try apiURL(account, action: "get_live_streams")
        async let categoryValue = LiveTVHTTP.json(from: categoriesURL)
        let streams = jsonList(try await LiveTVHTTP.json(from: streamsURL))
        var categories: [String: String] = [:]
        for item in jsonList(try? await categoryValue) {
            guard let id = jsonString(item["category_id"]) ?? jsonString(item["id"]) else { continue }
            categories[id] = jsonString(item["category_name"]) ?? jsonString(item["name"]) ?? id
        }
        var seen = Set<String>()
        return streams.compactMap { item -> LiveTVChannel? in
            guard let name = jsonString(item["name"]),
                  let streamID = jsonString(item["stream_id"]) ?? jsonString(item["id"]),
                  seen.insert(streamID).inserted else { return nil }
            let fileExtension = jsonString(item["container_extension"])?
                .trimmingCharacters(in: CharacterSet(charactersIn: ". ")) ?? ""
            let stream: LiveTVChannel.Stream
            if let direct = jsonString(item["direct_source"]).flatMap(URL.init(string:)),
               ["http", "https"].contains(direct.scheme?.lowercased() ?? "") {
                stream = .direct(url: direct, headers: [:])
            } else {
                stream = .xtream(streamID: streamID, containerExtension: fileExtension.isEmpty ? "ts" : fileExtension)
            }
            return LiveTVChannel(
                id: "xtream:\(streamID)",
                name: name,
                logoURL: (jsonString(item["stream_icon"]) ?? jsonString(item["logo"])).flatMap(URL.init(string:)),
                group: jsonString(item["category_id"]).flatMap { categories[$0] },
                sourceID: sourceID,
                sourceName: "Xtream",
                guideID: jsonString(item["epg_channel_id"]),
                stream: stream
            )
        }
    }

    static func streamURL(_ account: LiveTVXtreamAccount, streamID: String, containerExtension: String) -> URL {
        var url = account.server
        for segment in ["live", account.username, account.password, "\(streamID).\(containerExtension)"] {
            url.append(component: segment, directoryHint: .notDirectory)
        }
        return url
    }

    static func guideURL(_ account: LiveTVXtreamAccount) -> URL? {
        var components = URLComponents(url: account.server.appending(path: "xmltv.php"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "username", value: account.username),
            URLQueryItem(name: "password", value: account.password)
        ]
        return components?.url
    }

    private static func apiURL(_ account: LiveTVXtreamAccount, action: String?) throws -> URL {
        var components = URLComponents(url: account.server.appending(path: "player_api.php"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "username", value: account.username),
            URLQueryItem(name: "password", value: account.password)
        ] + (action.map { [URLQueryItem(name: "action", value: $0)] } ?? [])
        guard let url = components?.url else { throw LiveTVFailure.invalidAddress }
        return url
    }
}

// MARK: Stalker portal

/// A MAG set-top box portal: a handshake for a token, then channel lists,
/// links made at play time and two days of guide.
nonisolated enum LiveTVStalkerClient {
    static let sourceID = "provider:stalker"
    private static let session = LiveTVStalkerSessionCache()

    static func verify(_ account: LiveTVStalkerAccount) async throws {
        await session.clear()
        _ = try await token(account)
    }

    static func channels(_ account: LiveTVStalkerAccount) async throws -> [LiveTVChannel] {
        let token = try await token(account)
        let genreValue = try? await request(account, token: token, type: "itv", action: "get_genres")
        var genres: [String: String] = [:]
        for item in jsonList(stalkerContent(genreValue)) {
            guard let id = jsonString(item["id"]) ?? jsonString(item["alias"]) else { continue }
            genres[id] = jsonString(item["title"]) ?? jsonString(item["name"]) ?? id
        }
        var channels: [LiveTVChannel] = []
        var seen = Set<String>()
        for page in 1...20 {
            let value = try await request(account, token: token, type: "itv", action: "get_ordered_list", extra: ["p": String(page)])
            let content = stalkerContent(value)
            let items = jsonList(content)
            if items.isEmpty { break }
            for item in items {
                guard let id = jsonString(item["id"]),
                      let name = jsonString(item["name"]) ?? jsonString(item["title"]),
                      let command = jsonString(item["cmd"]) ?? jsonString(item["mc_cmd"]) ?? jsonString(item["url"]),
                      seen.insert(id).inserted else { continue }
                channels.append(LiveTVChannel(
                    id: "stalker:\(id)",
                    name: name,
                    logoURL: (jsonString(item["logo"]) ?? jsonString(item["logo_url"])).flatMap(URL.init(string:)),
                    group: (jsonString(item["tv_genre_id"]) ?? jsonString(item["genre_id"])).flatMap { genres[$0] },
                    sourceID: sourceID,
                    sourceName: "Stalker Portal",
                    guideID: jsonString(item["xmltv_id"]),
                    stream: .stalker(command: command)
                ))
            }
            if let total = Int(jsonString(content["total_items"]) ?? ""), channels.count >= total { break }
        }
        return channels
    }

    /// The portal makes a fresh link for each play.
    static func playback(_ account: LiveTVStalkerAccount, command: String) async throws -> (URL, [String: String]) {
        let token = try await token(account)
        let value = try await request(account, token: token, type: "itv", action: "create_link", extra: ["cmd": command])
        let result = stalkerContent(value)
        let link = jsonString(result["cmd"]) ?? jsonString(result["url"]) ?? jsonString(result["stream_url"]) ?? command
        guard let url = URL(string: playableLink(link)), url.host != nil else { throw LiveTVFailure.invalidResponse }
        return (url, headers(account, token: token))
    }

    /// Two days of guide, keyed by Omnia's channel id.
    static func guide(_ account: LiveTVStalkerAccount, from start: Date, to end: Date) async throws -> [String: [LiveTVProgram]] {
        let token = try await token(account)
        let value = try await request(account, token: token, type: "itv", action: "get_epg_info", extra: ["period": "48"])
        guard let data = stalkerContent(value)["data"] as? [String: Any] else { return [:] }
        var programs: [String: [LiveTVProgram]] = [:]
        for (channelID, entries) in data {
            let items = jsonList(entries).compactMap { item -> LiveTVProgram? in
                guard let title = jsonString(item["name"]),
                      let startValue = Double(jsonString(item["start_timestamp"]) ?? ""),
                      let stopValue = Double(jsonString(item["stop_timestamp"]) ?? "") else { return nil }
                let program = LiveTVProgram(
                    title: title,
                    start: Date(timeIntervalSince1970: startValue),
                    end: Date(timeIntervalSince1970: stopValue),
                    detail: jsonString(item["descr"]),
                    category: jsonString(item["category"])
                )
                return program.end >= start && program.start <= end ? program : nil
            }
            if !items.isEmpty {
                programs["stalker:\(channelID)"] = items.sorted { $0.start < $1.start }
            }
        }
        return programs
    }

    private static func token(_ account: LiveTVStalkerAccount) async throws -> String {
        if let token = await session.token(for: account) { return token }
        let value = try await request(account, token: nil, type: "stb", action: "handshake")
        guard let token = jsonString(stalkerContent(value)["token"]) else { throw LiveTVFailure.signInRejected }
        await session.store(token, for: account)
        return token
    }

    private static func request(
        _ account: LiveTVStalkerAccount,
        token: String?,
        type: String,
        action: String,
        extra: [String: String] = [:]
    ) async throws -> Any {
        var parameters = ["type": type, "action": action, "JsHttpRequest": "1-xml"]
        if let token { parameters["token"] = token }
        if !account.username.isEmpty { parameters["login"] = account.username }
        if !account.password.isEmpty { parameters["password"] = account.password }
        parameters.merge(extra) { _, latest in latest }
        var components = URLComponents(url: endpoint(account.portal), resolvingAgainstBaseURL: false)
        components?.queryItems = parameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components?.url else { throw LiveTVFailure.invalidAddress }
        return try await LiveTVHTTP.json(from: url, headers: headers(account, token: token))
    }

    private static func endpoint(_ portal: URL) -> URL {
        let text = portal.absoluteString
        let lowered = text.lowercased()
        if lowered.contains("portal.php") || lowered.contains("server/load.php") { return portal }
        if lowered.hasSuffix("/c") { return URL(string: String(text.dropLast(2)) + "/portal.php") ?? portal }
        return portal.appending(path: "portal.php")
    }

    private static func headers(_ account: LiveTVStalkerAccount, token: String?) -> [String: String] {
        var base = account.portal.absoluteString
        for marker in ["/portal.php", "/server/load.php"] {
            if let range = base.range(of: marker, options: .caseInsensitive) { base = String(base[..<range.lowerBound]) }
        }
        while base.hasSuffix("/") { base.removeLast() }
        if base.lowercased().hasSuffix("/c") { base.removeLast(2) }
        let timeZone = TimeZone.current.identifier.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "UTC"
        var headers = [
            "User-Agent": "Mozilla/5.0 (QtEmbedded; U; Linux; MAG254; en) AppleWebKit/533.3 MAG200 stbapp ver: 4 rev: 2721 Mobile Safari/533.3",
            "X-User-Agent": "Model: MAG254; Link: Ethernet",
            "Referer": "\(base)/c/",
            "Cookie": "mac=\(account.macAddress); stb_lang=en; timezone=\(timeZone)"
        ]
        if let token { headers["Authorization"] = "Bearer \(token)" }
        return headers
    }

    private static func playableLink(_ command: String) -> String {
        var text = command.trimmingCharacters(in: .whitespaces)
        for prefix in ["ffmpeg ", "auto "] where text.lowercased().hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
        }
        return String(text.split(separator: " ").first ?? Substring(text))
    }
}

private actor LiveTVStalkerSessionCache {
    private var account: LiveTVStalkerAccount?
    private var token: String?

    func token(for account: LiveTVStalkerAccount) -> String? {
        self.account == account ? token : nil
    }

    func store(_ token: String, for account: LiveTVStalkerAccount) {
        self.account = account
        self.token = token
    }

    func clear() {
        account = nil
        token = nil
    }
}

// MARK: JSON helpers

private nonisolated func jsonString(_ value: Any?) -> String? {
    let text: String? = switch value {
    case let value as String: value
    case let value as NSNumber: value.stringValue
    default: nil
    }
    let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed?.isEmpty == false ? trimmed : nil
}

/// Portals answer either `[...]` or `{"data": [...]}`.
private nonisolated func jsonList(_ value: Any?) -> [[String: Any]] {
    if let array = value as? [Any] { return array.compactMap { $0 as? [String: Any] } }
    if let object = value as? [String: Any], let data = object["data"] as? [Any] {
        return data.compactMap { $0 as? [String: Any] }
    }
    return []
}

/// Stalker replies wrap their content in `js`.
private nonisolated func stalkerContent(_ value: Any?) -> [String: Any] {
    guard let object = value as? [String: Any] else { return [:] }
    if let inner = object["js"] as? [String: Any] { return inner }
    if let inner = object["js"] as? [Any] { return ["data": inner] }
    return object
}

// MARK: Encrypted store

/// Live TV's saved files: playlist files, the channel list and the guide.
/// Channel lists and playlist files hold stream links that often carry an
/// account's password, so they are sealed with AES-GCM under a key kept in
/// the Keychain.
nonisolated enum LiveTVVault {
    private static let keyAccount = "live-tv-store-key"
    private static let cachedKey = Mutex<SymmetricKey?>(nil)

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var url = base.appending(path: "LiveTV", directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        }
        return url
    }

    static func write(_ data: Data, named name: String) throws {
        guard let key = key() else { throw LiveTVFailure.fileUnreadable }
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else { throw LiveTVFailure.fileUnreadable }
        try combined.write(to: directory.appending(path: name), options: .atomic)
    }

    static func read(named name: String) -> Data? {
        guard let key = key(),
              let combined = try? Data(contentsOf: directory.appending(path: name)),
              let box = try? AES.GCM.SealedBox(combined: combined) else { return nil }
        return try? AES.GCM.open(box, using: key)
    }

    static func remove(named name: String) {
        try? FileManager.default.removeItem(at: directory.appending(path: name))
    }

    private static func key() -> SymmetricKey? {
        cachedKey.withLock { cached in
            if let cached { return cached }
            if let saved = try? KeychainStore.value(account: keyAccount), let data = Data(base64Encoded: saved) {
                cached = SymmetricKey(data: data)
                return cached
            }
            let key = SymmetricKey(size: .bits256)
            let encoded = key.withUnsafeBytes { Data($0).base64EncodedString() }
            guard (try? KeychainStore.save(encoded, account: keyAccount)) != nil else { return nil }
            cached = key
            return key
        }
    }
}
