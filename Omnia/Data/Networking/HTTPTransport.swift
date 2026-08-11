import Foundation

protocol HTTPTransporting: Sendable {
    func data(for policy: HTTPRequestPolicy) async throws -> Data
}

struct HTTPRequestPolicy: Sendable {
    let url: URL
    let allowedOrigin: NormalizedOrigin
    let timeout: TimeInterval
    var maximumResponseBytes: Int
    let acceptedContentTypes: Set<String>

    init(
        url: URL,
        allowedOrigin: NormalizedOrigin,
        timeout: TimeInterval,
        maximumResponseBytes: Int,
        acceptedContentTypes: Set<String>
    ) {
        self.url = url
        self.allowedOrigin = allowedOrigin
        self.timeout = min(max(timeout, 1), 120)
        self.maximumResponseBytes = min(max(maximumResponseBytes, 1), 10 * 1_024 * 1_024)
        self.acceptedContentTypes = Set(acceptedContentTypes.map { $0.lowercased() })
    }
}

struct NormalizedOrigin: Equatable, Sendable {
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

enum HTTPTransportError: Error, Equatable, LocalizedError {
    case httpsRequired
    case originRejected
    case redirectRejected
    case invalidResponse
    case unsuccessfulStatus(Int)
    case unsupportedContentType
    case responseTooLarge
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
        case .cancelled:
            "The request was cancelled."
        case .transportFailure:
            "The server could not be reached."
        }
    }
}

actor HTTPTransport: HTTPTransporting {
    private let configuration: URLSessionConfiguration

    init(configuration: URLSessionConfiguration = .ephemeral) {
        let copied = configuration.copy() as? URLSessionConfiguration ?? .ephemeral
        copied.urlCache = nil
        copied.requestCachePolicy = .reloadIgnoringLocalCacheData
        copied.httpCookieStorage = nil
        copied.httpShouldSetCookies = false
        self.configuration = copied
    }

    func data(for policy: HTTPRequestPolicy) async throws -> Data {
        guard policy.url.scheme?.lowercased() == "https" else {
            throw HTTPTransportError.httpsRequired
        }
        guard policy.allowedOrigin.permits(policy.url) else {
            throw HTTPTransportError.originRejected
        }

        let redirectDelegate = RedirectDelegate(allowedOrigin: policy.allowedOrigin)
        let session = URLSession(
            configuration: configuration,
            delegate: redirectDelegate,
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: policy.url)
        request.httpMethod = "GET"
        request.timeoutInterval = policy.timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw HTTPTransportError.invalidResponse
            }
            guard (200...299).contains(response.statusCode) else {
                throw HTTPTransportError.unsuccessfulStatus(response.statusCode)
            }
            guard let mimeType = response.mimeType?.lowercased(),
                  policy.acceptedContentTypes.contains(mimeType) else {
                throw HTTPTransportError.unsupportedContentType
            }
            if response.expectedContentLength > Int64(policy.maximumResponseBytes) {
                throw HTTPTransportError.responseTooLarge
            }

            var data = Data()
            data.reserveCapacity(min(
                max(Int(response.expectedContentLength), 0),
                policy.maximumResponseBytes
            ))
            for try await byte in bytes {
                guard data.count < policy.maximumResponseBytes else {
                    throw HTTPTransportError.responseTooLarge
                }
                data.append(byte)
            }
            return data
        } catch let error as HTTPTransportError {
            throw error
        } catch is CancellationError {
            throw HTTPTransportError.cancelled
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                throw HTTPTransportError.cancelled
            }
            throw HTTPTransportError.transportFailure
        }
    }
}

private final class RedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let allowedOrigin: NormalizedOrigin

    init(allowedOrigin: NormalizedOrigin) {
        self.allowedOrigin = allowedOrigin
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, allowedOrigin.permits(url) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
