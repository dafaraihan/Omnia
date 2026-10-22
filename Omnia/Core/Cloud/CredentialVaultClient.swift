import CryptoKit
import Foundation

/// A separate no-cache transport for the authenticated credential boundary.
/// Never follows redirects or includes request/response data in errors.
@MainActor
final class CredentialVaultClient {
    private let account: OmniaAccount
    private let configuration: SupabaseConfiguration?

    init(account: OmniaAccount, configuration: SupabaseConfiguration? = .load()) {
        self.account = account
        self.configuration = configuration
    }

    func list() async throws -> [CredentialVaultEntry] {
        struct Reply: Decodable { let entries: [CredentialVaultEntry] }
        let reply: Reply = try await call(["action": "list"])
        guard reply.entries.count <= 2_000,
              Set(reply.entries.map(\.id)).count == reply.entries.count,
              reply.entries.allSatisfy({ $0.revision > 0 && $0.id.utf8.count <= 200 })
        else { throw CredentialVaultError.invalidData }
        return reply.entries
    }

    func read(id: String) async throws -> CredentialVaultEntry {
        struct Reply: Decodable { let entry: CredentialVaultEntry }
        let reply: Reply = try await call(["action": "read", "id": id])
        guard reply.entry.id == id, reply.entry.revision > 0 else { throw CredentialVaultError.invalidData }
        return reply.entry
    }

    func write(id: String, revision: Int, data: Data?) async throws -> CredentialVaultEntry {
        guard (data?.count ?? 0) <= 256 * 1_024 else { throw CredentialVaultError.invalidData }
        var body: [String: Any] = ["action": "write", "id": id, "expectedRevision": revision, "deleted": data == nil]
        if let data { body["payload"] = data.base64EncodedString() }
        struct Reply: Decodable { let entry: CredentialVaultEntry }
        let reply: Reply = try await call(body)
        guard reply.entry.id == id, reply.entry.revision > revision else { throw CredentialVaultError.invalidData }
        return reply.entry
    }

    func upload(id: String, revision: Int, data: Data) async throws -> CredentialVaultEntry {
        guard data.count <= 64 * 1_024 * 1_024 else { throw CredentialVaultError.invalidData }
        struct Begin: Decodable {
            let uploadID: String
            let generation: String
            let chunkSize: Int
            let chunkCount: Int
        }
        let begin: Begin = try await call([
            "action": "attachmentBegin", "id": id, "expectedRevision": revision,
            "byteCount": data.count, "sha256": Self.digest(data)
        ])
        guard UUID(uuidString: begin.uploadID) != nil,
              begin.chunkSize == 512 * 1_024,
              begin.chunkCount == max(1, (data.count + begin.chunkSize - 1) / begin.chunkSize)
        else { throw CredentialVaultError.invalidData }
        struct Ack: Decodable { let ok: Bool }
        for index in 0..<begin.chunkCount {
            try Task.checkCancellation()
            let lower = index * begin.chunkSize
            let chunk = data.subdata(in: lower..<min(lower + begin.chunkSize, data.count))
            let ack: Ack = try await call([
                "action": "attachmentPut", "uploadID": begin.uploadID,
                "index": index, "payload": chunk.base64EncodedString()
            ])
            guard ack.ok else { throw CredentialVaultError.unavailable }
        }
        struct Reply: Decodable { let entry: CredentialVaultEntry }
        let reply: Reply = try await call(["action": "attachmentCommit", "uploadID": begin.uploadID])
        guard reply.entry.id == id, reply.entry.revision > revision else { throw CredentialVaultError.invalidData }
        return reply.entry
    }

    func download(_ entry: CredentialVaultEntry) async throws -> Data {
        guard let payload = entry.payload, let encoded = Data(base64Encoded: payload), encoded.count <= 256 * 1_024,
              let manifest = try? JSONDecoder().decode(CredentialVaultAttachment.self, from: encoded),
              manifest.version == 1, UUID(uuidString: manifest.uploadID) != nil,
              manifest.byteCount >= 0, manifest.byteCount <= 64 * 1_024 * 1_024,
              manifest.chunkSize == 512 * 1_024,
              manifest.chunkCount == max(1, (manifest.byteCount + manifest.chunkSize - 1) / manifest.chunkSize)
        else { throw CredentialVaultError.invalidData }
        var data = Data()
        data.reserveCapacity(manifest.byteCount)
        struct Chunk: Decodable { let payload: String }
        for index in 0..<manifest.chunkCount {
            try Task.checkCancellation()
            let chunk: Chunk = try await call([
                "action": "attachmentGet", "id": entry.id, "revision": entry.revision, "index": index
            ])
            guard let bytes = Data(base64Encoded: chunk.payload),
                  bytes.count == min(manifest.chunkSize, manifest.byteCount - data.count)
            else { throw CredentialVaultError.invalidData }
            data.append(bytes)
        }
        guard data.count == manifest.byteCount, Self.digest(data) == manifest.sha256 else {
            throw CredentialVaultError.invalidData
        }
        return data
    }

    private func call<T: Decodable>(_ body: [String: Any]) async throws -> T {
        guard let configuration, let owner = account.user?.id else { throw CredentialVaultError.signedOut }
        let token = try await account.metadataAccessToken()
        guard account.user?.id == owner else { throw CancellationError() }
        let endpoint = configuration.projectURL.appending(path: "functions/v1/credential-vault")
        guard endpoint.scheme == "https", endpoint.user == nil, endpoint.password == nil,
              let origin = NormalizedOrigin(url: configuration.projectURL), origin.permits(endpoint)
        else { throw CredentialVaultError.invalidData }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: .sortedKeys)
        guard (request.httpBody?.count ?? 0) <= 1_024 * 1_024 else { throw CredentialVaultError.invalidData }
        let data = try await Self.perform(request)
        guard account.user?.id == owner else { throw CancellationError() }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw CredentialVaultError.invalidData }
    }

    @concurrent
    private static func perform(_ request: URLRequest) async throws -> Data {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.urlCredentialStorage = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        config.timeoutIntervalForResource = 45
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: VaultRedirectDelegate())
            guard let response = response as? HTTPURLResponse,
                  response.url == request.url,
                  response.mimeType?.lowercased() == "application/json",
                  response.expectedContentLength <= 1_024 * 1_024
            else { throw CredentialVaultError.invalidData }
            var data = Data()
            for try await byte in bytes {
                if data.count >= 1_024 * 1_024 { throw CredentialVaultError.invalidData }
                data.append(byte)
            }
            if response.statusCode == 409 {
                struct Conflict: Decodable { let entry: CredentialVaultEntry }
                guard let conflict = try? JSONDecoder().decode(Conflict.self, from: data) else {
                    throw CredentialVaultError.unavailable
                }
                throw CredentialVaultError.conflict(conflict.entry)
            }
            guard response.statusCode == 200 else { throw CredentialVaultError.unavailable }
            return data
        } catch is CancellationError { throw CancellationError() }
        catch let error as CredentialVaultError { throw error }
        catch {
            if Task.isCancelled { throw CancellationError() }
            throw CredentialVaultError.unavailable
        }
    }

    nonisolated static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private nonisolated final class VaultRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
