import Foundation

nonisolated protocol HTTPTransporting: Sendable {
    func data(for policy: HTTPRequestPolicy) async throws -> Data
}

nonisolated struct HTTPRequestPolicy: Sendable {
    let url: URL
    let allowedOrigin: NormalizedOrigin
    let timeout: TimeInterval
    var maximumResponseBytes: Int
    let acceptedContentTypes: Set<String>
    let requestHeaders: [String: String]
    /// Stremio clients follow an add-on's redirects to any HTTPS host, such
    /// as a CDN or a moved server. Off unless a caller opts in.
    var allowsCrossOriginRedirects = false
    /// Add-on servers label JSON loosely or not at all; the body is still
    /// validated by decoding it. Off unless a caller opts in.
    var acceptsAnyContentType = false

    init(
        url: URL,
        allowedOrigin: NormalizedOrigin,
        timeout: TimeInterval,
        maximumResponseBytes: Int,
        acceptedContentTypes: Set<String>,
        requestHeaders: [String: String] = [:]
    ) {
        self.url = url
        self.allowedOrigin = allowedOrigin
        self.timeout = min(max(timeout, 1), 120)
        self.maximumResponseBytes = min(max(maximumResponseBytes, 1), 10 * 1_024 * 1_024)
        self.acceptedContentTypes = Set(acceptedContentTypes.map { $0.lowercased() })
        let forbidden = Set(["host", "connection", "content-length", "range"])
        self.requestHeaders = requestHeaders.reduce(into: [:]) { result, entry in
            let name = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty,
                  name.utf8.count <= 256,
                  value.utf8.count <= 8_192,
                  !forbidden.contains(name.lowercased()),
                  !name.contains(where: \.isNewline),
                  !value.contains(where: \.isNewline) else { return }
            result[name] = value
        }
    }
}

nonisolated struct NormalizedOrigin: Equatable, Sendable {
    let scheme: String
    let host: String
    let port: Int?

    init(scheme: String, host: String, port: Int?) {
        self.scheme = scheme.lowercased()
        self.host = host.lowercased()
        self.port = Self.normalizedPort(port, scheme: scheme)
    }

    init?(url: URL) {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        self.init(scheme: scheme, host: host, port: url.port)
    }

    func permits(_ url: URL) -> Bool {
        guard let candidate = NormalizedOrigin(url: url) else { return false }
        return candidate == self
    }

    private static func normalizedPort(_ port: Int?, scheme: String) -> Int? {
        switch (scheme.lowercased(), port) {
        case ("https", 443), ("http", 80):
            nil
        default:
            port
        }
    }
}

nonisolated enum HTTPTransportError: Error, Equatable, LocalizedError {
    case httpsRequired
    case originRejected
    case redirectRejected
    case invalidResponse
    case unsuccessfulStatus(Int)
    case unsupportedContentType
    case responseTooLarge
    case timedOut
    case cancelled
    case transportFailure

    var errorDescription: String? {
        switch self {
        case .httpsRequired:
            "A secure connection is required."
        case .originRejected:
            "The server address is not allowed."
        case .redirectRejected:
            "The server redirected to an untrusted address."
        case .invalidResponse:
            "The server returned an invalid response."
        case let .unsuccessfulStatus(status):
            "The server returned status \(status)."
        case .unsupportedContentType:
            "The server returned an unsupported content type."
        case .responseTooLarge:
            "The server response is too large."
        case .timedOut:
            "The server took too long to respond."
        case .cancelled:
            "The request was cancelled."
        case .transportFailure:
            "The server could not be reached."
        }
    }
}

/// Requests made with the default configuration share one session, so the
/// connection and TLS handshake to an add-on are reused instead of being set
/// up again for every catalog. Redirects are still checked per request.
nonisolated final class HTTPTransport: HTTPTransporting, Sendable {
    private static let sharedSession = URLSession(configuration: hardened(.ephemeral))

    private let session: URLSession
    private let ownsSession: Bool

    init(configuration: URLSessionConfiguration? = nil) {
        if let configuration {
            session = URLSession(configuration: Self.hardened(configuration))
            ownsSession = true
        } else {
            session = Self.sharedSession
            ownsSession = false
        }
    }

    deinit {
        if ownsSession { session.finishTasksAndInvalidate() }
    }

    private static func hardened(_ configuration: URLSessionConfiguration) -> URLSessionConfiguration {
        let copied = configuration.copy() as? URLSessionConfiguration ?? .ephemeral
        copied.urlCache = nil
        copied.requestCachePolicy = .reloadIgnoringLocalCacheData
        copied.httpCookieStorage = nil
        copied.httpShouldSetCookies = false
        copied.httpMaximumConnectionsPerHost = 8
        return copied
    }

    func data(for policy: HTTPRequestPolicy) async throws -> Data {
        try await Self.perform(policy, session: session)
    }

    /// Runs away from the caller's actor, so reading a large reply never
    /// holds up the interface.
    @concurrent
    private static func perform(_ policy: HTTPRequestPolicy, session: URLSession) async throws -> Data {
        guard policy.url.scheme?.lowercased() == "https" else {
            throw HTTPTransportError.httpsRequired
        }
        guard policy.allowedOrigin.permits(policy.url) else {
            throw HTTPTransportError.originRejected
        }

        var request = URLRequest(url: policy.url)
        request.httpMethod = "GET"
        request.timeoutInterval = policy.timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        for (name, value) in policy.requestHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }

        do {
            // Read the reply in one go. Reading it a byte at a time took
            // seconds for the multi-megabyte stream lists aggregators send.
            let (data, response) = try await session.data(
                for: request,
                delegate: RedirectDelegate(
                    allowedOrigin: policy.allowedOrigin,
                    allowsAnySecureOrigin: policy.allowsCrossOriginRedirects
                )
            )
            guard let response = response as? HTTPURLResponse else {
                throw HTTPTransportError.invalidResponse
            }
            // The delegate refuses redirects elsewhere; this confirms where
            // the answer actually came from.
            guard let finalURL = response.url,
                  policy.allowsCrossOriginRedirects
                    ? finalURL.scheme?.lowercased() == "https"
                    : policy.allowedOrigin.permits(finalURL)
            else {
                throw HTTPTransportError.redirectRejected
            }
            guard (200...299).contains(response.statusCode) else {
                throw HTTPTransportError.unsuccessfulStatus(response.statusCode)
            }
            if !policy.acceptsAnyContentType {
                guard let mimeType = response.mimeType?.lowercased(),
                      policy.acceptedContentTypes.contains(mimeType) else {
                    throw HTTPTransportError.unsupportedContentType
                }
            }
            if response.expectedContentLength > Int64(policy.maximumResponseBytes) {
                throw HTTPTransportError.responseTooLarge
            }

            guard data.count <= policy.maximumResponseBytes else {
                throw HTTPTransportError.responseTooLarge
            }
            return data
        } catch let error as HTTPTransportError {
            throw error
        } catch is CancellationError {
            throw HTTPTransportError.cancelled
        } catch {
            if (error as? URLError)?.code == .timedOut {
                throw HTTPTransportError.timedOut
            }
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                throw HTTPTransportError.cancelled
            }
            throw HTTPTransportError.transportFailure
        }
    }
}

private nonisolated final class RedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let allowedOrigin: NormalizedOrigin
    private let allowsAnySecureOrigin: Bool

    init(allowedOrigin: NormalizedOrigin, allowsAnySecureOrigin: Bool = false) {
        self.allowedOrigin = allowedOrigin
        self.allowsAnySecureOrigin = allowsAnySecureOrigin
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url,
              allowsAnySecureOrigin ? url.scheme?.lowercased() == "https" : allowedOrigin.permits(url)
        else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
