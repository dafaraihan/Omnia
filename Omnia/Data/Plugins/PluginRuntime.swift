//
//  PluginRuntime.swift
//  Omnia
//

import CommonCrypto
import CryptoKit
import Foundation
@preconcurrency import JavaScriptCore
import os

nonisolated enum PluginRuntimeError: LocalizedError, Equatable {
    case timedOut
    case failed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .timedOut: "The plugin didn't finish within a minute."
        case let .failed(message): message
        case .cancelled: "The plugin was stopped."
        }
    }
}

/// Runs Nuvio-format plugins with JavaScriptCore. Every run gets a fresh
/// context, so plugins can't see each other or keep state between runs. At
/// most ten run at once and each has a minute, as in Nuvio.
nonisolated enum PluginRuntime {
    static let timeout: TimeInterval = 60
    static let maximumConcurrentRuns = 10
    private static let limiter = PluginRunLimiter(limit: maximumConcurrentRuns)

    struct Configuration: Sendable {
        let code: String
        let scraperID: String
        let settingsJSON: String
        let tmdbAPIKey: String?
    }

    /// What a plugin returned, plus the last thing that went wrong while it
    /// ran (a console error, a failed request or an error status), so an
    /// empty answer can say why.
    struct StreamsOutcome: Sendable {
        let results: [PluginStreamResult]
        let problem: String?
    }

    /// Calls the plugin's `getStreams` for a title.
    static func streams(
        _ configuration: Configuration,
        tmdbID: String,
        mediaType: String,
        season: Int?,
        episode: Int?
    ) async throws -> StreamsOutcome {
        var arguments: [String: Any] = ["tmdbId": tmdbID, "mediaType": PluginScraper.normalizedType(mediaType)]
        arguments["season"] = season ?? NSNull()
        arguments["episode"] = episode ?? NSNull()
        let argumentsJSON = String(data: try JSONSerialization.data(withJSONObject: arguments), encoding: .utf8) ?? "{}"
        let output = try await run(configuration, call: PluginPrelude.streamsCall, argumentsJSON: argumentsJSON)
        return StreamsOutcome(results: PluginStreamResult.results(fromJSON: output.text), problem: output.problem)
    }

    /// The fields the plugin's `onSettings` describes, if it has any.
    static func settingsLayout(_ configuration: Configuration) async throws -> [PluginSettingsField] {
        let output = try await run(configuration, call: PluginPrelude.settingsCall, argumentsJSON: "{}")
        return PluginSettingsField.fields(fromJSON: output.text)
    }

    private static func run(_ configuration: Configuration, call: String, argumentsJSON: String) async throws -> PluginRunOutput {
        await limiter.acquire()
        defer { Task { await limiter.release() } }
        try Task.checkCancellation()

        let session = PluginSession(configuration: configuration, call: call, argumentsJSON: argumentsJSON)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                session.start { result in continuation.resume(with: result) }
            }
        } onCancel: {
            session.cancel()
        }
    }
}

private actor PluginRunLimiter {
    private let limit: Int
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { self.limit = limit }

    func acquire() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    func release() {
        if waiting.isEmpty {
            running = max(0, running - 1)
        } else {
            waiting.removeFirst().resume()
        }
    }
}

private nonisolated struct PluginRunOutput: Sendable {
    let text: String
    let problem: String?
}

/// One plugin run. Everything that touches its JSContext happens on `queue`.
private nonisolated final class PluginSession: @unchecked Sendable {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Omnia", category: "Plugins")
    private static let maximumResponseBytes = 20 * 1024 * 1024
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    private let configuration: PluginRuntime.Configuration
    private let call: String
    private let argumentsJSON: String
    private let queue = DispatchQueue(label: "omnia.plugin.run", qos: .userInitiated)
    private let redirects: RedirectPolicy
    private let urlSession: URLSession

    private var context: JSContext?
    private var documents: [Int: PluginHTMLDocument] = [:]
    private var completion: ((Result<PluginRunOutput, Error>) -> Void)?
    private var lastException: String?
    /// The plugin's latest console error, and the latest failed request or
    /// error status.
    private var consoleProblem: String?
    private var networkProblem: String?

    init(configuration: PluginRuntime.Configuration, call: String, argumentsJSON: String) {
        self.configuration = configuration
        self.call = call
        self.argumentsJSON = argumentsJSON
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = 30
        sessionConfiguration.httpCookieAcceptPolicy = .always
        sessionConfiguration.waitsForConnectivity = false
        let redirects = RedirectPolicy()
        self.redirects = redirects
        urlSession = URLSession(configuration: sessionConfiguration, delegate: redirects, delegateQueue: nil)
    }

    func start(completion: @escaping (Result<PluginRunOutput, Error>) -> Void) {
        queue.async { [self] in
            self.completion = completion
            queue.asyncAfter(deadline: .now() + PluginRuntime.timeout) { [weak self] in
                self?.finish(.failure(PluginRuntimeError.timedOut))
            }
            guard let context = JSContext() else {
                finish(.failure(PluginRuntimeError.failed("JavaScript isn't available.")))
                return
            }
            self.context = context
            context.name = configuration.scraperID
            context.exceptionHandler = { [weak self] _, exception in
                let message = exception?.toString() ?? "Unknown error"
                let line = exception?.objectForKeyedSubscript("line")?.toString() ?? "?"
                self?.lastException = "\(message) (line \(line))"
                Self.logger.error("Plugin \(self?.configuration.scraperID ?? "", privacy: .public): \(message, privacy: .private)")
            }
            install(in: context)

            context.evaluateScript(PluginPrelude.source)
            if let lastException {
                finish(.failure(PluginRuntimeError.failed("Omnia's plugin support failed to start: \(lastException)")))
                return
            }
            context.evaluateScript(PluginPrelude.module(wrapping: configuration.code))
            if let lastException {
                finish(.failure(PluginRuntimeError.failed("The plugin couldn't load: \(lastException)")))
                return
            }
            context.evaluateScript(call)
        }
    }

    func cancel() {
        queue.async { [weak self] in self?.finish(.failure(PluginRuntimeError.cancelled)) }
    }

    private func finish(_ result: Result<String, Error>) {
        guard let completion else { return }
        self.completion = nil
        let problem = [consoleProblem, networkProblem].compactMap { $0 }.joined(separator: " · ")
        completion(result.map { PluginRunOutput(text: $0, problem: problem.isEmpty ? nil : problem) })
        urlSession.invalidateAndCancel()
        documents.removeAll()
        context?.exceptionHandler = nil
        context = nil
    }

    // MARK: Host functions

    private func install(in context: JSContext) {
        func define(_ name: String, _ value: Any) {
            context.setObject(value, forKeyedSubscript: name as NSString)
        }

        define("__omnia_scraper_id", configuration.scraperID)
        define("__omnia_scraper_settings", configuration.settingsJSON)
        define("__omnia_tmdb_key", configuration.tmdbAPIKey ?? "")
        define("__omnia_call_arguments", argumentsJSON)

        let result: @convention(block) (String) -> Void = { [weak self] output in
            self?.finish(.success(output))
        }
        let fail: @convention(block) (String) -> Void = { [weak self] message in
            self?.finish(.failure(PluginRuntimeError.failed(message)))
        }
        let log: @convention(block) (String, String) -> Void = { [weak self] level, message in
            let id = self?.configuration.scraperID ?? ""
            if level == "error" || level == "warn" {
                self?.queue.async { self?.consoleProblem = String(message.prefix(300)) }
            }
            if level == "error" {
                Self.logger.error("Plugin \(id, privacy: .public): \(message, privacy: .private)")
            } else {
                Self.logger.debug("Plugin \(id, privacy: .public): \(message, privacy: .private)")
            }
        }
        define("__omnia_result", result)
        define("__omnia_fail", fail)
        define("__omnia_log", log)

        let sleep: @convention(block) (Double) -> JSValue? = { [weak self] milliseconds in
            self?.promise { resolve, _ in
                let delay = max(0, min(milliseconds, 60_000)) / 1000
                self?.queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard self?.completion != nil else { return }
                    resolve.call(withArguments: [])
                }
            }
        }
        define("__omnia_sleep", sleep)

        let fetch: @convention(block) (String) -> JSValue? = { [weak self] payload in
            self?.promise { resolve, _ in
                self?.performFetch(payload) { output, problem in
                    self?.queue.async {
                        guard self?.completion != nil else { return }
                        if let problem { self?.networkProblem = problem }
                        resolve.call(withArguments: [output])
                    }
                }
            }
        }
        define("__omnia_fetch", fetch)

        installEncoding(define)
        installCrypto(define)
        installHTML(define)
    }

    /// A promise whose resolve and reject functions Swift calls later, on `queue`.
    private func promise(_ body: (JSValue, JSValue) -> Void) -> JSValue? {
        guard let context else { return nil }
        var resolve: JSValue?
        var reject: JSValue?
        let promise = JSValue(newPromiseIn: context) { resolveFunction, rejectFunction in
            resolve = resolveFunction
            reject = rejectFunction
        }
        if let resolve, let reject { body(resolve, reject) }
        return promise
    }

    private func throwJS(_ message: String) {
        guard let context = JSContext.current() else { return }
        context.exception = JSValue(newErrorFromMessage: message, in: context)
    }

    private func installEncoding(_ define: (String, Any) -> Void) {
        let atob: @convention(block) (String) -> String? = { [weak self] text in
            var cleaned = text.filter { !$0.isWhitespace }
            while cleaned.count % 4 != 0 { cleaned += "=" }
            guard let data = Data(base64Encoded: cleaned) else {
                self?.throwJS("atob: the string to be decoded is not correctly encoded.")
                return nil
            }
            return String(data: data, encoding: .isoLatin1)
        }
        let btoa: @convention(block) (String) -> String = { text in
            (text.data(using: .isoLatin1) ?? Data(text.utf8)).base64EncodedString()
        }
        let random: @convention(block) (Int) -> String = { count in
            var bytes = [UInt8](repeating: 0, count: max(0, min(count, 65_536)))
            _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            return Self.hex(bytes)
        }
        let uuid: @convention(block) () -> String = { UUID().uuidString.lowercased() }
        define("__omnia_atob", atob)
        define("__omnia_btoa", btoa)
        define("__omnia_random", random)
        define("__omnia_uuid", uuid)
    }

    // MARK: fetch

    private func performFetch(_ payload: String, completion: @escaping (String, String?) -> Void) {
        @Sendable func failure(_ message: String, host: String = "the server") -> (String, String?) {
            (Self.json(["error": message]), "\(host): \(message)")
        }
        guard let data = payload.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let urlString = object["url"] as? String,
              let url = URL(string: urlString) ?? URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? ""),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        else {
            let (output, problem) = failure("Only http and https addresses can be fetched.")
            completion(output, problem)
            return
        }
        let host = url.host ?? "the server"

        var request = URLRequest(url: url)
        request.httpMethod = (object["method"] as? String ?? "GET").uppercased()
        let headers = object["headers"] as? [String: String] ?? [:]
        // URLSession manages these itself; setting Accept-Encoding by hand
        // can leave a compressed body undecoded.
        let reservedHeaders: Set<String> = ["accept-encoding", "connection", "host", "content-length", "keep-alive", "transfer-encoding"]
        for (name, value) in headers where !reservedHeaders.contains(name.lowercased()) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if headers.keys.contains(where: { $0.lowercased() == "user-agent" }) == false {
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        }
        if let base64 = object["bodyBase64"] as? String {
            request.httpBody = Data(base64Encoded: base64)
        } else if let body = object["body"] as? String {
            request.httpBody = Data(body.utf8)
        }
        let followRedirects = object["followRedirects"] as? Bool ?? true

        let task = urlSession.dataTask(with: request) { data, response, error in
            if let error {
                let (output, problem) = failure((error as NSError).localizedDescription, host: host)
                completion(output, problem)
                return
            }
            guard let http = response as? HTTPURLResponse else {
                let (output, problem) = failure("The server's answer wasn't HTTP.", host: host)
                completion(output, problem)
                return
            }
            let body = data ?? Data()
            guard body.count <= Self.maximumResponseBytes else {
                let (output, problem) = failure("The response was larger than 20 MB.", host: host)
                completion(output, problem)
                return
            }
            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                headers[String(describing: key).lowercased()] = String(describing: value)
            }
            var output: [String: Any] = [
                "status": http.statusCode,
                "statusText": HTTPURLResponse.localizedString(forStatusCode: http.statusCode).capitalized,
                "url": http.url?.absoluteString ?? urlString,
                "redirected": http.url != nil && http.url != url,
                "headers": headers
            ]
            // Text bodies cross as text; anything else as base64 bytes.
            if let text = String(data: body, encoding: .utf8) {
                output["text"] = text
            } else {
                output["bodyBase64"] = body.base64EncodedString()
            }
            let problem = (200...399).contains(http.statusCode)
                ? nil
                : "\(host) answered \(http.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: http.statusCode))"
            completion(Self.json(output), problem)
        }
        redirects.setFollows(followRedirects, for: task.taskIdentifier)
        task.resume()
    }

    // MARK: crypto

    private func installCrypto(_ define: (String, Any) -> Void) {
        let digest: @convention(block) (String, String) -> String? = { [weak self] name, hex in
            guard let output = Self.digest(name, Self.bytes(hex)) else {
                self?.throwJS("Unsupported hash algorithm: \(name)")
                return nil
            }
            return Self.hex(output)
        }
        let hmac: @convention(block) (String, String, String) -> String? = { [weak self] name, keyHex, dataHex in
            guard let algorithm = Self.hmacAlgorithm(name) else {
                self?.throwJS("Unsupported HMAC algorithm: \(name)")
                return nil
            }
            let key = Self.bytes(keyHex)
            let data = Self.bytes(dataHex)
            var output = [UInt8](repeating: 0, count: algorithm.length)
            CCHmac(algorithm.algorithm, key, key.count, data, data.count, &output)
            return Self.hex(output)
        }
        let pbkdf2: @convention(block) (String, String, Int, Int, String) -> String? = { [weak self] passwordHex, saltHex, iterations, length, hash in
            let password = Self.bytes(passwordHex)
            let salt = Self.bytes(saltHex)
            guard let prf = Self.pbkdf2Algorithm(hash), length > 0, length <= 1024 else {
                self?.throwJS("Unsupported PBKDF2 parameters")
                return nil
            }
            var output = [UInt8](repeating: 0, count: length)
            let status = password.withUnsafeBufferPointer { passwordBuffer in
                passwordBuffer.withMemoryRebound(to: CChar.self) { passwordChars in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2), passwordChars.baseAddress, password.count,
                        salt, salt.count, prf, UInt32(max(1, iterations)), &output, length
                    )
                }
            }
            return status == Int32(kCCSuccess) ? Self.hex(output) : nil
        }
        let cipher: @convention(block) (String, Bool, String, Bool, String, String, String) -> String? = { algorithm, encrypt, mode, pkcs7, keyHex, ivHex, dataHex in
            Self.cipher(
                algorithm: algorithm, encrypt: encrypt, mode: mode, pkcs7: pkcs7,
                key: Self.bytes(keyHex), iv: Self.bytes(ivHex), data: Self.bytes(dataHex)
            ).map(Self.hex)
        }
        let gcm: @convention(block) (Bool, String, String, String, String) -> String? = { encrypt, keyHex, ivHex, dataHex, aadHex in
            let key = SymmetricKey(data: Self.bytes(keyHex))
            let data = Data(Self.bytes(dataHex))
            let aad = Data(Self.bytes(aadHex))
            guard let nonce = try? AES.GCM.Nonce(data: Self.bytes(ivHex)) else { return nil }
            if encrypt {
                guard let sealed = try? AES.GCM.seal(data, using: key, nonce: nonce, authenticating: aad) else { return nil }
                return Self.hex(Array(sealed.ciphertext + sealed.tag))
            }
            guard data.count >= 16,
                  let box = try? AES.GCM.SealedBox(nonce: nonce, ciphertext: data.dropLast(16), tag: data.suffix(16)),
                  let opened = try? AES.GCM.open(box, using: key, authenticating: aad)
            else { return nil }
            return Self.hex(Array(opened))
        }
        define("__omnia_digest", digest)
        define("__omnia_hmac", hmac)
        define("__omnia_pbkdf2", pbkdf2)
        define("__omnia_cipher", cipher)
        define("__omnia_aes_gcm", gcm)
    }

    private static func digest(_ name: String, _ data: [UInt8]) -> [UInt8]? {
        switch normalizedHash(name) {
        case "MD5": Array(Insecure.MD5.hash(data: data))
        case "SHA1": Array(Insecure.SHA1.hash(data: data))
        case "SHA256": Array(SHA256.hash(data: data))
        case "SHA384": Array(SHA384.hash(data: data))
        case "SHA512": Array(SHA512.hash(data: data))
        case "SHA224":
            {
                var output = [UInt8](repeating: 0, count: Int(CC_SHA224_DIGEST_LENGTH))
                CC_SHA224(data, CC_LONG(data.count), &output)
                return output
            }()
        default: nil
        }
    }

    private static func normalizedHash(_ name: String) -> String {
        name.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func hmacAlgorithm(_ name: String) -> (algorithm: CCHmacAlgorithm, length: Int)? {
        switch normalizedHash(name) {
        case "MD5": (CCHmacAlgorithm(kCCHmacAlgMD5), Int(CC_MD5_DIGEST_LENGTH))
        case "SHA1": (CCHmacAlgorithm(kCCHmacAlgSHA1), Int(CC_SHA1_DIGEST_LENGTH))
        case "SHA224": (CCHmacAlgorithm(kCCHmacAlgSHA224), Int(CC_SHA224_DIGEST_LENGTH))
        case "SHA256": (CCHmacAlgorithm(kCCHmacAlgSHA256), Int(CC_SHA256_DIGEST_LENGTH))
        case "SHA384": (CCHmacAlgorithm(kCCHmacAlgSHA384), Int(CC_SHA384_DIGEST_LENGTH))
        case "SHA512": (CCHmacAlgorithm(kCCHmacAlgSHA512), Int(CC_SHA512_DIGEST_LENGTH))
        default: nil
        }
    }

    private static func pbkdf2Algorithm(_ name: String) -> CCPseudoRandomAlgorithm? {
        switch normalizedHash(name) {
        case "SHA1": CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1)
        case "SHA224": CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA224)
        case "SHA256": CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256)
        case "SHA384": CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA384)
        case "SHA512": CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512)
        default: nil
        }
    }

    /// AES, DES and Triple DES in the modes CryptoJS offers. Nil when the key
    /// or padding is wrong, which CryptoJS reports as malformed data.
    private static func cipher(algorithm: String, encrypt: Bool, mode: String, pkcs7: Bool, key: [UInt8], iv: [UInt8], data: [UInt8]) -> [UInt8]? {
        let (ccAlgorithm, blockSize): (CCAlgorithm, Int) = switch algorithm.uppercased() {
        case "DES": (CCAlgorithm(kCCAlgorithmDES), kCCBlockSizeDES)
        case "TRIPLEDES", "3DES": (CCAlgorithm(kCCAlgorithm3DES), kCCBlockSize3DES)
        default: (CCAlgorithm(kCCAlgorithmAES), kCCBlockSizeAES128)
        }
        let ccMode: CCMode = switch mode.uppercased() {
        case "ECB": CCMode(kCCModeECB)
        case "CTR": CCMode(kCCModeCTR)
        case "CFB": CCMode(kCCModeCFB)
        case "OFB": CCMode(kCCModeOFB)
        default: CCMode(kCCModeCBC)
        }
        let streamMode = ccMode == CCMode(kCCModeCTR) || ccMode == CCMode(kCCModeCFB) || ccMode == CCMode(kCCModeOFB)
        let padding = pkcs7 && !streamMode ? CCPadding(ccPKCS7Padding) : CCPadding(ccNoPadding)
        var vector = iv
        if vector.count < blockSize { vector += [UInt8](repeating: 0, count: blockSize - vector.count) }

        let isECB = ccMode == CCMode(kCCModeECB)
        let options = ccMode == CCMode(kCCModeCTR) ? CCModeOptions(kCCModeOptionCTR_BE) : 0
        var cryptor: CCCryptorRef?
        let created = vector.withUnsafeBytes { ivBuffer in
            key.withUnsafeBytes { keyBuffer in
                CCCryptorCreateWithMode(
                    CCOperation(encrypt ? kCCEncrypt : kCCDecrypt), ccMode, ccAlgorithm, padding,
                    isECB ? nil : ivBuffer.baseAddress, keyBuffer.baseAddress, key.count, nil, 0, 0,
                    options, &cryptor
                )
            }
        }
        guard created == CCCryptorStatus(kCCSuccess), let cryptor else { return nil }
        defer { CCCryptorRelease(cryptor) }

        var output = [UInt8](repeating: 0, count: CCCryptorGetOutputLength(cryptor, data.count, true) + blockSize)
        var moved = 0
        let updated = data.withUnsafeBytes { input in
            output.withUnsafeMutableBytes { buffer in
                CCCryptorUpdate(cryptor, input.baseAddress, data.count, buffer.baseAddress, buffer.count, &moved)
            }
        }
        guard updated == CCCryptorStatus(kCCSuccess) else { return nil }
        var finalMoved = 0
        let finished = output.withUnsafeMutableBytes { buffer in
            CCCryptorFinal(cryptor, buffer.baseAddress! + moved, buffer.count - moved, &finalMoved)
        }
        guard finished == CCCryptorStatus(kCCSuccess) else { return nil }
        return Array(output.prefix(moved + finalMoved))
    }

    // MARK: cheerio

    private func installHTML(_ define: (String, Any) -> Void) {
        let load: @convention(block) (String) -> Int = { [weak self] html in
            guard let self else { return 0 }
            let id = documents.count + 1
            documents[id] = PluginHTMLDocument(html: html)
            return id
        }
        let select: @convention(block) (Int, JSValue, String) -> String = { [weak self] documentID, roots, selector in
            guard let document = self?.documents[documentID] else { return "[]" }
            let scope: [Int]? = roots.isNull || roots.isUndefined ? nil : Self.ids(roots.toString())
            return Self.json(document.select(selector, within: scope))
        }
        let text: @convention(block) (Int, String) -> String = { [weak self] documentID, ids in
            guard let document = self?.documents[documentID] else { return "" }
            return Self.ids(ids).map(document.textContent(of:)).joined()
        }
        let inner: @convention(block) (Int, Int) -> String = { [weak self] documentID, id in
            self?.documents[documentID]?.innerHTML(of: id) ?? ""
        }
        let outer: @convention(block) (Int, Int) -> String = { [weak self] documentID, id in
            self?.documents[documentID]?.outerHTML(of: id) ?? ""
        }
        let attribute: @convention(block) (Int, Int, String) -> JSValue? = { [weak self] documentID, id, name in
            guard let context = JSContext.current() else { return nil }
            guard let value = self?.documents[documentID]?.attribute(name, of: id) else { return JSValue(nullIn: context) }
            return JSValue(object: value, in: context)
        }
        let attributes: @convention(block) (Int, Int) -> String = { [weak self] documentID, id in
            guard let document = self?.documents[documentID], document.nodes.indices.contains(id) else { return "{}" }
            var object: [String: String] = [:]
            for attribute in document.nodes[id].attributes { object[attribute.name] = attribute.value }
            return Self.json(object)
        }
        let tag: @convention(block) (Int, Int) -> String = { [weak self] documentID, id in
            guard let document = self?.documents[documentID], document.nodes.indices.contains(id) else { return "" }
            return document.nodes[id].kind == .document ? "root" : document.nodes[id].name
        }
        let relation: @convention(block) (Int, String, String) -> String = { [weak self] documentID, ids, kind in
            guard let document = self?.documents[documentID] else { return "[]" }
            var result: [Int] = []
            var seen = Set<Int>()
            func add(_ id: Int?) {
                if let id, seen.insert(id).inserted { result.append(id) }
            }
            for id in Self.ids(ids) {
                switch kind {
                case "children": document.elementChildren(of: id).forEach(add)
                case "parent": add(document.parentElement(of: id))
                case "parents":
                    var current = document.parentElement(of: id)
                    while let parent = current {
                        add(parent)
                        current = document.parentElement(of: parent)
                    }
                case "next": add(document.nextElement(of: id))
                case "prev": add(document.previousElement(of: id))
                case "nextAll": document.elementSiblings(of: id).drop { $0 != id }.dropFirst().forEach(add)
                case "prevAll": document.elementSiblings(of: id).prefix { $0 != id }.reversed().forEach(add)
                case "siblings": document.elementSiblings(of: id).filter { $0 != id }.forEach(add)
                default: break
                }
            }
            return Self.json(result)
        }
        let matches: @convention(block) (Int, Int, String) -> Bool = { [weak self] documentID, id, selector in
            self?.documents[documentID]?.matches(id, selector: selector) ?? false
        }
        define("__omnia_html_load", load)
        define("__omnia_html_select", select)
        define("__omnia_html_text", text)
        define("__omnia_html_inner", inner)
        define("__omnia_html_outer", outer)
        define("__omnia_html_attr", attribute)
        define("__omnia_html_attrs", attributes)
        define("__omnia_html_tag", tag)
        define("__omnia_html_relation", relation)
        define("__omnia_html_matches", matches)
    }

    // MARK: Helpers

    private static func ids(_ json: String) -> [Int] {
        guard let data = json.data(using: .utf8),
              let array = (try? JSONSerialization.jsonObject(with: data)) as? [NSNumber]
        else { return [] }
        return array.map(\.intValue)
    }

    private static func json(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]) else { return "null" }
        return String(data: data, encoding: .utf8) ?? "null"
    }

    private static func bytes(_ hex: String) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.utf8.count / 2)
        var high: UInt8?
        for character in hex.utf8 {
            let value: UInt8
            switch character {
            case 48...57: value = character - 48
            case 97...102: value = character - 87
            case 65...70: value = character - 55
            default: continue
            }
            if let current = high {
                bytes.append(current << 4 | value)
                high = nil
            } else {
                high = value
            }
        }
        return bytes
    }

    private static func hex(_ bytes: [UInt8]) -> String {
        let digits = Array("0123456789abcdef".utf8)
        var output = [UInt8]()
        output.reserveCapacity(bytes.count * 2)
        for byte in bytes {
            output.append(digits[Int(byte >> 4)])
            output.append(digits[Int(byte & 15)])
        }
        return String(decoding: output, as: UTF8.self)
    }
}

/// Lets a plugin ask fetch not to follow redirects (`redirect: 'manual'`).
private nonisolated final class RedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var manual = Set<Int>()

    func setFollows(_ follows: Bool, for taskID: Int) {
        lock.lock()
        defer { lock.unlock() }
        if follows { manual.remove(taskID) } else { manual.insert(taskID) }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        lock.lock()
        let isManual = manual.contains(task.taskIdentifier)
        lock.unlock()
        completionHandler(isManual ? nil : request)
    }
}
