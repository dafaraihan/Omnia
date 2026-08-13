import Foundation

nonisolated enum HTTPSDiscByteSourceError: LocalizedError, Equatable, Sendable {
    case httpsRequired
    case credentialedURL
    case invalidContentLength
    case sourceTooLarge
    case invalidResponse
    case redirectRejected
    case fileSizeMismatch
    case cancelled
    case transportFailure

    var errorDescription: String? {
        switch self {
        case .httpsRequired:
            "A secure connection is required to prepare this disc."
        case .credentialedURL:
            "Omnia rejected credentials embedded in the disc address."
        case .invalidContentLength:
            "The disc server did not provide an exact media size."
        case .sourceTooLarge:
            "This disc is larger than the available resolver cache."
        case .invalidResponse:
            "The disc server returned an invalid response."
        case .redirectRejected:
            "The disc server redirected to an untrusted address."
        case .fileSizeMismatch:
            "The downloaded disc did not match its declared size."
        case .cancelled:
            "Disc preparation was cancelled."
        case .transportFailure:
            "The disc server could not be reached."
        }
    }
}

final class HTTPSDiscByteSource: DiscByteSource, @unchecked Sendable {
    let expectedByteCount: Int64

    private let url: URL
    private let origin: NormalizedOrigin
    private let requestHeaders: [String: String]
    private let configuration: URLSessionConfiguration

    private init(
        url: URL,
        origin: NormalizedOrigin,
        expectedByteCount: Int64,
        requestHeaders: [String: String],
        configuration: URLSessionConfiguration
    ) {
        self.url = url
        self.origin = origin
        self.expectedByteCount = expectedByteCount
        self.requestHeaders = requestHeaders
        self.configuration = configuration
    }

    static func prepare(
        url: URL,
        maximumBytes: Int64,
        requestHeaders: [String: String] = [:],
        configuration: URLSessionConfiguration = .ephemeral
    ) async throws -> HTTPSDiscByteSource {
        guard url.scheme?.lowercased() == "https", let origin = NormalizedOrigin(url: url) else {
            throw HTTPSDiscByteSourceError.httpsRequired
        }
        guard url.user == nil, url.password == nil, url.fragment == nil else {
            throw HTTPSDiscByteSourceError.credentialedURL
        }
        guard maximumBytes > 0 else {
            throw HTTPSDiscByteSourceError.sourceTooLarge
        }

        let configuration = Self.secureCopy(of: configuration)
        let headers = Self.sanitized(headers: requestHeaders)
        let delegate = HTTPSDiscRedirectDelegate(origin: origin)
        let session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        do {
            let (_, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  (200...299).contains(response.statusCode),
                  let responseURL = response.url,
                  origin.permits(responseURL)
            else {
                if delegate.rejectedRedirect { throw HTTPSDiscByteSourceError.redirectRejected }
                throw HTTPSDiscByteSourceError.invalidResponse
            }
            let length = Self.contentLength(in: response)
            guard length > 0 else {
                throw HTTPSDiscByteSourceError.invalidContentLength
            }
            guard length <= maximumBytes else {
                throw HTTPSDiscByteSourceError.sourceTooLarge
            }
            return HTTPSDiscByteSource(
                url: url,
                origin: origin,
                expectedByteCount: length,
                requestHeaders: headers,
                configuration: configuration
            )
        } catch let error as HTTPSDiscByteSourceError {
            throw error
        } catch is CancellationError {
            throw HTTPSDiscByteSourceError.cancelled
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                throw HTTPSDiscByteSourceError.cancelled
            }
            throw HTTPSDiscByteSourceError.transportFailure
        }
    }

    func bytes(for file: TorrentMediaFile) -> AsyncThrowingStream<Data, Error> {
        guard file.size == expectedByteCount else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: HTTPSDiscByteSourceError.fileSizeMismatch)
            }
        }

        return AsyncThrowingStream { continuation in
            let operation = Task {
                let delegate = HTTPSDiscRedirectDelegate(origin: origin)
                let session = URLSession(
                    configuration: configuration,
                    delegate: delegate,
                    delegateQueue: nil
                )
                defer { session.invalidateAndCancel() }

                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.timeoutInterval = 120
                request.cachePolicy = .reloadIgnoringLocalCacheData
                requestHeaders.forEach {
                    request.setValue($0.value, forHTTPHeaderField: $0.key)
                }

                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let response = response as? HTTPURLResponse,
                          (200...299).contains(response.statusCode),
                          let responseURL = response.url,
                          origin.permits(responseURL)
                    else {
                        if delegate.rejectedRedirect {
                            throw HTTPSDiscByteSourceError.redirectRejected
                        }
                        throw HTTPSDiscByteSourceError.invalidResponse
                    }
                    let responseLength = Self.contentLength(in: response)
                    guard responseLength == expectedByteCount else {
                        throw HTTPSDiscByteSourceError.fileSizeMismatch
                    }

                    var received: Int64 = 0
                    var chunk = Data()
                    chunk.reserveCapacity(64 * 1_024)
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        received += 1
                        guard received <= expectedByteCount else {
                            throw HTTPSDiscByteSourceError.fileSizeMismatch
                        }
                        chunk.append(byte)
                        if chunk.count == 64 * 1_024 {
                            continuation.yield(chunk)
                            chunk.removeAll(keepingCapacity: true)
                        }
                    }
                    guard received == expectedByteCount else {
                        throw HTTPSDiscByteSourceError.fileSizeMismatch
                    }
                    if !chunk.isEmpty { continuation.yield(chunk) }
                    continuation.finish()
                } catch let error as HTTPSDiscByteSourceError {
                    continuation.finish(throwing: error)
                } catch is CancellationError {
                    continuation.finish(throwing: HTTPSDiscByteSourceError.cancelled)
                } catch {
                    if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                        continuation.finish(throwing: HTTPSDiscByteSourceError.cancelled)
                    } else {
                        continuation.finish(throwing: HTTPSDiscByteSourceError.transportFailure)
                    }
                }
            }
            continuation.onTermination = { _ in operation.cancel() }
        }
    }

    private static func contentLength(in response: HTTPURLResponse) -> Int64 {
        if let value = response.value(forHTTPHeaderField: "Content-Length"),
           let length = Int64(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return length
        }
        return response.expectedContentLength
    }

    private static func secureCopy(
        of configuration: URLSessionConfiguration
    ) -> URLSessionConfiguration {
        let copied = configuration.copy() as? URLSessionConfiguration ?? .ephemeral
        copied.urlCache = nil
        copied.requestCachePolicy = .reloadIgnoringLocalCacheData
        copied.httpCookieStorage = nil
        copied.httpShouldSetCookies = false
        return copied
    }

    private static func sanitized(headers: [String: String]) -> [String: String] {
        let forbidden = Set(["host", "connection", "content-length", "range", "cookie"])
        var result: [String: String] = [:]
        for (name, value) in headers.sorted(by: { $0.key < $1.key }).prefix(32) {
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.range(of: #"^[A-Za-z0-9!#$%&'*+.^_`|~-]{1,128}$"#, options: .regularExpression) != nil,
                  !forbidden.contains(name.lowercased()),
                  !value.isEmpty,
                  value.utf8.count <= 4_096,
                  !value.contains("\r"),
                  !value.contains("\n")
            else { continue }
            result[name] = value
        }
        return result
    }
}

private final class HTTPSDiscRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let origin: NormalizedOrigin
    private let lock = NSLock()
    private var redirectCount = 0
    private var didReject = false

    var rejectedRedirect: Bool {
        lock.withLock { didReject }
    }

    init(origin: NormalizedOrigin) {
        self.origin = origin
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let permitsRedirect = lock.withLock { () -> Bool in
            redirectCount += 1
            guard redirectCount <= 5,
                  let url = request.url,
                  url.scheme?.lowercased() == "https",
                  url.user == nil,
                  url.password == nil,
                  origin.permits(url)
            else {
                didReject = true
                return false
            }
            return true
        }
        completionHandler(permitsRedirect ? request : nil)
    }
}
